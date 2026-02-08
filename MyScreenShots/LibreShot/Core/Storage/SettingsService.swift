import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("com.allensong.MyScreenShots.hotkeyDidChange")
}

class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    @Published var saveDirectoryBookmark: Data? {
        didSet {
            UserDefaults.standard.set(saveDirectoryBookmark, forKey: "saveDirectoryBookmark")
        }
    }
    
    @Published var shortcutKey: Int {
        didSet {
            UserDefaults.standard.set(shortcutKey, forKey: "shortcutKey")
        }
    }
    
    @Published var shortcutModifiers: Int {
        didSet {
            UserDefaults.standard.set(shortcutModifiers, forKey: "shortcutModifiers")
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        }
    }
    
    @Published var useRoundedCorners: Bool {
        didSet {
            UserDefaults.standard.set(useRoundedCorners, forKey: "useRoundedCorners")
        }
    }
    
    private init() {
        self.saveDirectoryBookmark = UserDefaults.standard.data(forKey: "saveDirectoryBookmark")
        self.shortcutKey = UserDefaults.standard.object(forKey: "shortcutKey") as? Int ?? -1
        self.shortcutModifiers = UserDefaults.standard.object(forKey: "shortcutModifiers") as? Int ?? 0
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.useRoundedCorners = UserDefaults.standard.object(forKey: "useRoundedCorners") as? Bool ?? true // Default to true (Rounded)
    }
    
    var saveDirectory: URL? {
        get {
            guard let data = saveDirectoryBookmark else { return nil }
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    // Refresh bookmark if needed
                    saveSaveDirectory(url)
                }
                return url
            } catch {
                print("Failed to resolve bookmark: \(error)")
                return nil
            }
        }
    }
    
    func withSaveDirectory<T>(block: (URL) throws -> T) rethrows -> T? {
        guard let url = saveDirectory else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try block(url)
    }
    
    func saveSaveDirectory(_ url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            // Use property setter to trigger publish/save
            saveDirectoryBookmark = data
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }
    
    @discardableResult
    func saveShortcut(keyCode: Int, modifiers: Int) -> Bool {
        shortcutKey = keyCode
        shortcutModifiers = modifiers
        
        let success: Bool
        if keyCode < 0 {
            HotkeyService.shared.unregisterHotkey()
            success = true
        } else {
            success = HotkeyService.shared.registerHotkey(keyCode: keyCode, modifiers: modifiers)
        }
        
        // Notify that hotkey has changed
        if success {
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        }
        
        return success
    }
}
