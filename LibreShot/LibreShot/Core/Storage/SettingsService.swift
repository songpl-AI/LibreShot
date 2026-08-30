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

    @Published var fullScreenShortcutKey: Int {
        didSet {
            UserDefaults.standard.set(fullScreenShortcutKey, forKey: "fullScreenShortcutKey")
        }
    }
    
    @Published var fullScreenShortcutModifiers: Int {
        didSet {
            UserDefaults.standard.set(fullScreenShortcutModifiers, forKey: "fullScreenShortcutModifiers")
        }
    }
    
    @Published var longScreenshotShortcutKey: Int {
        didSet {
            UserDefaults.standard.set(longScreenshotShortcutKey, forKey: "longScreenshotShortcutKey")
        }
    }
    
    @Published var longScreenshotShortcutModifiers: Int {
        didSet {
            UserDefaults.standard.set(longScreenshotShortcutModifiers, forKey: "longScreenshotShortcutModifiers")
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
    
    @Published var playSound: Bool {
        didSet {
            UserDefaults.standard.set(playSound, forKey: "playSound")
        }
    }

    @Published var autoSaveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSaveEnabled, forKey: "autoSaveEnabled")
        }
    }

    private init() {
        self.saveDirectoryBookmark = UserDefaults.standard.data(forKey: "saveDirectoryBookmark")
        
        // Defaults:
        // Area Capture: Cmd + Shift + X (KeyCode: 7, Modifiers: 768)
        // Full Screen: Cmd + Shift + A (KeyCode: 0, Modifiers: 768)
        self.shortcutKey = UserDefaults.standard.object(forKey: "shortcutKey") as? Int ?? 7
        self.shortcutModifiers = UserDefaults.standard.object(forKey: "shortcutModifiers") as? Int ?? 768
        
        self.fullScreenShortcutKey = UserDefaults.standard.object(forKey: "fullScreenShortcutKey") as? Int ?? 0
        self.fullScreenShortcutModifiers = UserDefaults.standard.object(forKey: "fullScreenShortcutModifiers") as? Int ?? 768
        
        self.longScreenshotShortcutKey = UserDefaults.standard.object(forKey: "longScreenshotShortcutKey") as? Int ?? 37
        self.longScreenshotShortcutModifiers = UserDefaults.standard.object(forKey: "longScreenshotShortcutModifiers") as? Int ?? 768
        
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.useRoundedCorners = UserDefaults.standard.object(forKey: "useRoundedCorners") as? Bool ?? true // Default to true (Rounded)
        self.playSound = UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true // Default to true
        self.autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true // Default to true
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
