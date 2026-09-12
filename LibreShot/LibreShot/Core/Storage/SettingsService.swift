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
            defaults.set(saveDirectoryBookmark, forKey: "saveDirectoryBookmark")
        }
    }
    
    @Published var shortcutKey: Int {
        didSet {
            defaults.set(shortcutKey, forKey: "shortcutKey")
        }
    }
    
    @Published var shortcutModifiers: Int {
        didSet {
            defaults.set(shortcutModifiers, forKey: "shortcutModifiers")
        }
    }

    @Published var fullScreenShortcutKey: Int {
        didSet {
            defaults.set(fullScreenShortcutKey, forKey: "fullScreenShortcutKey")
        }
    }
    
    @Published var fullScreenShortcutModifiers: Int {
        didSet {
            defaults.set(fullScreenShortcutModifiers, forKey: "fullScreenShortcutModifiers")
        }
    }
    
    @Published var longScreenshotShortcutKey: Int {
        didSet {
            defaults.set(longScreenshotShortcutKey, forKey: "longScreenshotShortcutKey")
        }
    }
    
    @Published var longScreenshotShortcutModifiers: Int {
        didSet {
            defaults.set(longScreenshotShortcutModifiers, forKey: "longScreenshotShortcutModifiers")
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
        }
    }
    
    @Published var useRoundedCorners: Bool {
        didSet {
            defaults.set(useRoundedCorners, forKey: "useRoundedCorners")
        }
    }
    
    @Published var playSound: Bool {
        didSet {
            defaults.set(playSound, forKey: "playSound")
        }
    }

    @Published var autoSaveEnabled: Bool {
        didSet {
            defaults.set(autoSaveEnabled, forKey: "autoSaveEnabled")
        }
    }

    @Published private(set) var toolbarConfiguration: ToolbarConfiguration {
        didSet {
            defaults.set(toolbarConfiguration.hiddenItems.sorted(), forKey: "hiddenToolbarItems")
            defaults.set(toolbarConfiguration.orderedItems.map(\.rawValue), forKey: "toolbarItemOrder")
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.toolbarConfiguration = ToolbarConfiguration(
            hiddenItems: Set(defaults.stringArray(forKey: "hiddenToolbarItems") ?? []),
            itemOrder: defaults.stringArray(forKey: "toolbarItemOrder") ?? []
        )
        self.saveDirectoryBookmark = defaults.data(forKey: "saveDirectoryBookmark")
        
        // Defaults:
        // Area Capture: Cmd + Shift + X (KeyCode: 7, Modifiers: 768)
        // Full Screen: Cmd + Shift + A (KeyCode: 0, Modifiers: 768)
        self.shortcutKey = defaults.object(forKey: "shortcutKey") as? Int ?? 7
        self.shortcutModifiers = defaults.object(forKey: "shortcutModifiers") as? Int ?? 768
        
        self.fullScreenShortcutKey = defaults.object(forKey: "fullScreenShortcutKey") as? Int ?? 0
        self.fullScreenShortcutModifiers = defaults.object(forKey: "fullScreenShortcutModifiers") as? Int ?? 768
        
        self.longScreenshotShortcutKey = defaults.object(forKey: "longScreenshotShortcutKey") as? Int ?? 37
        self.longScreenshotShortcutModifiers = defaults.object(forKey: "longScreenshotShortcutModifiers") as? Int ?? 768
        
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.useRoundedCorners = defaults.object(forKey: "useRoundedCorners") as? Bool ?? true // Default to true (Rounded)
        self.playSound = defaults.object(forKey: "playSound") as? Bool ?? true // Default to true
        self.autoSaveEnabled = defaults.object(forKey: "autoSaveEnabled") as? Bool ?? true // Default to true
    }
    
    func setToolbarItem(_ item: ToolbarItem, visible: Bool) {
        toolbarConfiguration.setVisible(visible, for: item)
    }

    func restoreDefaultToolbar() {
        toolbarConfiguration = ToolbarConfiguration()
    }

    func moveToolbarItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        toolbarConfiguration.moveItems(fromOffsets: source, toOffset: destination)
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
        // Unregister old if needed (handled by registerHotkey internals or explicit unregister)
        // For simplicity, we just try to register new one.
        // Note: Real app should check if key is already taken by fullScreenShortcut
        
        shortcutKey = keyCode
        shortcutModifiers = modifiers
        
        // Notify changes
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        
        // We return true here because actual registration happens in AppDelegate
        // Ideally we should move registration logic here or return actual status
        return true
    }
    
    @discardableResult
    func saveFullScreenShortcut(keyCode: Int, modifiers: Int) -> Bool {
        fullScreenShortcutKey = keyCode
        fullScreenShortcutModifiers = modifiers
        
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        return true
    }
    
    @discardableResult
    func saveLongScreenshotShortcut(keyCode: Int, modifiers: Int) -> Bool {
        longScreenshotShortcutKey = keyCode
        longScreenshotShortcutModifiers = modifiers
        
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        return true
    }
}
