import AppKit

private final class CountingSaveService: CaptureService {
    var encodes = 0
    override func pngData(from image: NSImage) -> Data? {
        encodes += 1
        return super.pngData(from: image)
    }
}

@main struct SavePermissionRecoveryChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let suite = "LibreShot.SavePermission.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let chosen = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: chosen) }
        let fixture = NSImage(size: NSSize(width: 32, height: 24))
        fixture.lockFocus(); NSColor.red.setFill(); NSRect(x: 0,y: 0,width: 32,height: 24).fill(); fixture.unlockFocus()
        var prompts = 0
        let service = CountingSaveService(settings: settings, pasteboard: board, directoryChooser: { _ in
            precondition(Thread.isMainThread)
            prompts += 1
            precondition(board.data(forType: .png) != nil, "Copy must precede the permission panel")
            return chosen
        }, fileWriter: { data, url in
            precondition(!Thread.isMainThread, "Image writes must remain off the UI thread")
            guard url.deletingLastPathComponent().resolvingSymlinksInPath() == chosen.resolvingSymlinksInPath() else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try data.write(to: url)
        })
        do {
            let first = try await service.completeCapture(fixture)!
            precondition(prompts == 1 && settings.saveDirectory != nil && service.encodes == 1)
            let firstData = try Data(contentsOf: first)
            precondition(firstData == board.data(forType: .png))
            let second = try await service.completeCapture(fixture)!
            precondition(prompts == 1 && first != second)
            let restartedSettings = SettingsService(defaults: defaults)
            precondition(restartedSettings.saveDirectory?.resolvingSymlinksInPath() == chosen.resolvingSymlinksInPath())
            print("PASS: default permission denial recovers, identical PNG saved, subsequent capture and restart retain directory")
        } catch {
            print("FAIL: default directory permission denial did not recover: \(error)")
            exit(1)
        }

        settings.saveDirectoryBookmark = nil
        var cancellations = 0
        let cancelled = CaptureService(settings: settings, pasteboard: board, directoryChooser: { _ in
            cancellations += 1
            return nil
        }, fileWriter: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        do { _ = try await cancelled.completeCapture(fixture); preconditionFailure("Expected cancellation") }
        catch is CancellationError { }
        precondition(cancellations == 1 && settings.saveDirectoryBookmark == nil && board.data(forType: .png) != nil)
        print("PASS: cancelling directory choice preserves copied PNG and leaves settings unchanged")

        let noSpace = CaptureService(settings: settings, pasteboard: board, directoryChooser: { _ in
            preconditionFailure("Disk-full errors must not prompt for permissions")
        }, fileWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        do { _ = try await noSpace.completeCapture(fixture); preconditionFailure("Expected disk-full error") }
        catch { precondition((error as NSError).code == CocoaError.fileWriteOutOfSpace.rawValue) }
        precondition(board.data(forType: .png) != nil)
        print("PASS: unrelated disk-full error propagates while preserving copied PNG")

        var retries = 0
        let retryFails = CaptureService(settings: settings, pasteboard: board, directoryChooser: { _ in
            retries += 1
            return chosen
        }, fileWriter: { _, _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) })
        do { _ = try await retryFails.completeCapture(fixture); preconditionFailure("Expected retry failure") }
        catch { precondition((error as NSError).domain == NSPOSIXErrorDomain) }
        precondition(retries == 1 && board.data(forType: .png) != nil)
        print("PASS: POSIX permission denial retries only once, without a panel loop")

        settings.autoSaveEnabled = false
        let disabled = CaptureService(settings: settings, pasteboard: board, directoryChooser: { _ in
            preconditionFailure("Copy-only must not request directory access")
        }, fileWriter: { _, _ in preconditionFailure("Copy-only must not write") })
        let copiedOnly = try await disabled.completeCapture(fixture)
        precondition(copiedOnly == nil && board.data(forType: .png) != nil)
        print("PASS: disabled automatic save remains copy-only")

        // A previously chosen folder can also lose access; reselecting must recover
        // direct Save while leaving the clipboard untouched.
        let old = chosen.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        precondition(settings.saveSaveDirectory(old))
        board.clearContents()
        board.setString("save-only sentinel", forType: .string)
        var reselections = 0
        let manual = CountingSaveService(settings: settings, pasteboard: board, directoryChooser: { suggested in
            precondition(suggested.resolvingSymlinksInPath() == old.resolvingSymlinksInPath())
            reselections += 1
            return chosen
        }, fileWriter: { data, url in
            if url.deletingLastPathComponent().resolvingSymlinksInPath() == old.resolvingSymlinksInPath() {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
            }
            try data.write(to: url)
        })
        let manualURL = try await manual.saveImageDirectly(fixture)
        precondition(FileManager.default.fileExists(atPath: manualURL.path) && reselections == 1 && manual.encodes == 1)
        precondition(board.string(forType: .string) == "save-only sentinel")
        print("PASS: lost configured-folder permission recovers direct Save with one encoding and unchanged clipboard")
    }
}
