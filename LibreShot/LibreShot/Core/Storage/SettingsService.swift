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
    
    @Published var editLongCaptureAfterFinish: Bool {
        didSet { defaults.set(editLongCaptureAfterFinish, forKey: "editLongCaptureAfterFinish") }
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

    @Published private(set) var defaultEditorTool: ToolbarItem {
        didSet { defaults.set(defaultEditorTool.rawValue, forKey: "defaultEditorTool") }
    }

    @Published var numberAnnotationStyle: NumberAnnotationStyle {
        didSet { defaults.set(numberAnnotationStyle.rawValue, forKey: "numberAnnotationStyle") }
    }

    @Published private(set) var annotationToolStyles: [String: AnnotationToolStyle] {
        didSet {
            if let data = try? JSONEncoder().encode(annotationToolStyles) {
                defaults.set(data, forKey: "annotationToolStyles")
            }
        }
    }

    func annotationStyle(for tool: AnnotationType) -> AnnotationToolStyle {
        if let saved = annotationToolStyles[tool.rawValue] { return saved.validated }
        var style = AnnotationToolStyle.factory(for: tool)
        // Preserve the existing sequence-number preference until this tool is configured.
        if tool == .number { style.numberStyle = numberAnnotationStyle }
        return style
    }

    func setAnnotationStyle(_ style: AnnotationToolStyle, for tool: AnnotationType) {
        annotationToolStyles[tool.rawValue] = style.validated
        if tool == .number { numberAnnotationStyle = style.numberStyle }
    }

    var initialAnnotationTool: AnnotationType? {
        guard toolbarConfiguration.isVisible(defaultEditorTool) else { return nil }
        return defaultEditorTool.annotationType
    }

    func setDefaultEditorTool(_ item: ToolbarItem) {
        guard item == .select || (item.annotationType != nil && toolbarConfiguration.isVisible(item)) else { return }
        defaultEditorTool = item
    }

    private let defaults: UserDefaults

    @Published private(set) var editorShortcuts: [String: EditorShortcut] {
        didSet {
            if let data = try? JSONEncoder().encode(editorShortcuts) {
                defaults.set(data, forKey: "editorShortcuts")
            }
        }
    }
    @Published var editorSpaceAction: EditorSpaceAction {
        didSet { defaults.set(editorSpaceAction.rawValue, forKey: "editorSpaceAction") }
    }
    @Published var doubleClickCompletesCapture: Bool {
        didSet { defaults.set(doubleClickCompletesCapture, forKey: "doubleClickCompletesCapture") }
    }
    @Published var doubleOptionEnabled: Bool {
        didSet {
            defaults.set(doubleOptionEnabled, forKey: "doubleOptionEnabled")
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        }
    }
    @Published private(set) var shortcutError: String?
    @Published private(set) var hotkeyRegistrationError: String?

    func reportHotkeyRegistrationFailures(_ titles: [String]) {
        hotkeyRegistrationError = titles.isEmpty ? nil : "全局快捷键未生效：\(titles.joined(separator: "、"))。可能已被系统或其他应用占用，请更换组合键。"
    }

    private var globalShortcuts: [(title: String, shortcut: EditorShortcut)] {
        [("区域截图", .init(keyCode: shortcutKey, modifiers: shortcutModifiers)),
         ("全屏截图", .init(keyCode: fullScreenShortcutKey, modifiers: fullScreenShortcutModifiers)),
         ("长截图", .init(keyCode: longScreenshotShortcutKey, modifiers: longScreenshotShortcutModifiers))]
            .filter { $0.shortcut.keyCode >= 0 }
    }

    func setEditorShortcut(_ shortcut: EditorShortcut?, for item: ToolbarItem) -> String? {
        guard item != .cancel else { return "Esc 始终用于取消截图" }
        if let shortcut {
            guard shortcut.isAllowed else { return "此按键保留给文字编辑、空格动作或系统操作" }
            if let conflict = globalShortcuts.first(where: { $0.shortcut.conflicts(with: shortcut) }) {
                return "已用于全局“\(conflict.title)”"
            }
            if let conflict = ToolbarItem.allCases.first(where: {
                $0 != item && editorShortcuts[$0.rawValue]?.conflicts(with: shortcut) == true
            }) { return "已用于“\(conflict.title)”" }
        }
        editorShortcuts[item.rawValue] = shortcut
        return nil
    }

    func restoreDefaultEditorShortcuts() {
        editorShortcuts = EditorShortcut.defaults.filter { _, shortcut in
            !globalShortcuts.contains { $0.shortcut.conflicts(with: shortcut) }
        }
        editorSpaceAction = .disabled
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.annotationToolStyles = defaults.data(forKey: "annotationToolStyles")
            .flatMap { try? JSONDecoder().decode([String: AnnotationToolStyle].self, from: $0) } ?? [:]
        self.numberAnnotationStyle = NumberAnnotationStyle(rawValue: defaults.string(forKey: "numberAnnotationStyle") ?? "") ?? .filled
        if let data = defaults.data(forKey: "editorShortcuts"),
           let saved = try? JSONDecoder().decode([String: EditorShortcut].self, from: data) {
            var validated: [String: EditorShortcut] = [:]
            for item in ToolbarItem.allCases where item != .cancel {
                if let shortcut = saved[item.rawValue], shortcut.isAllowed,
                   !validated.values.contains(where: { $0.conflicts(with: shortcut) }) {
                    validated[item.rawValue] = shortcut
                }
            }
            self.editorShortcuts = validated
        } else {
            self.editorShortcuts = EditorShortcut.defaults
        }
        self.editorSpaceAction = EditorSpaceAction(rawValue: defaults.string(forKey: "editorSpaceAction") ?? "") ?? .disabled
        self.doubleClickCompletesCapture = defaults.object(forKey: "doubleClickCompletesCapture") as? Bool ?? true
        self.doubleOptionEnabled = defaults.bool(forKey: "doubleOptionEnabled")
        self.toolbarConfiguration = ToolbarConfiguration(
            hiddenItems: Set(defaults.stringArray(forKey: "hiddenToolbarItems") ?? []),
            itemOrder: defaults.stringArray(forKey: "toolbarItemOrder") ?? []
        )
        let savedTool = ToolbarItem(rawValue: defaults.string(forKey: "defaultEditorTool") ?? "") ?? .select
        self.defaultEditorTool = (savedTool == .select || savedTool.annotationType != nil)
            && !(defaults.stringArray(forKey: "hiddenToolbarItems") ?? []).contains(savedTool.rawValue) ? savedTool : .select
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
        self.editLongCaptureAfterFinish = defaults.object(forKey: "editLongCaptureAfterFinish") as? Bool ?? true
        self.playSound = defaults.object(forKey: "playSound") as? Bool ?? true // Default to true
        // Legacy installs may have used the old default without storing the toggle.
        // Persist the resolved choice once so a new install remains copy-only later.
        let legacyKeys = ["saveDirectoryBookmark", "shortcutKey", "fullScreenShortcutKey",
                          "longScreenshotShortcutKey", "doubleOptionEnabled", "launchAtLogin",
                          "useRoundedCorners", "toolbarItemOrder", "editorShortcuts", "defaultEditorTool"]
        let hasLegacyPreferences = legacyKeys.contains { defaults.object(forKey: $0) != nil }
        self.autoSaveEnabled = defaults.object(forKey: "autoSaveEnabled") as? Bool ?? hasLegacyPreferences
        defaults.set(autoSaveEnabled, forKey: "autoSaveEnabled")
        // Existing global bindings win when loading a previously conflicting configuration.
        self.editorShortcuts = editorShortcuts.filter { _, shortcut in
            !globalShortcuts.contains { $0.shortcut.conflicts(with: shortcut) }
        }
    }
    
    func setToolbarItem(_ item: ToolbarItem, visible: Bool) {
        toolbarConfiguration.setVisible(visible, for: item)
        if !visible && defaultEditorTool == item { defaultEditorTool = .select }
    }

    func restoreDefaultToolbar() {
        toolbarConfiguration = ToolbarConfiguration()
        defaultEditorTool = .select
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
    
    @discardableResult
    func saveSaveDirectory(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            // Use property setter to trigger publish/save
            saveDirectoryBookmark = data
            return true
        } catch {
            print("Failed to create bookmark: \(error)")
            return false
        }
    }
    
    @discardableResult
    func saveShortcut(keyCode: Int, modifiers: Int) -> Bool {
        guard validateGlobalShortcut(.init(keyCode: keyCode, modifiers: modifiers), replacing: "区域截图") else { return false }
        shortcutKey = keyCode
        shortcutModifiers = modifiers
        
        // Notify changes
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        
        // This reports configuration validation; AppDelegate reports actual registration separately.
        return true
    }
    
    @discardableResult
    func saveFullScreenShortcut(keyCode: Int, modifiers: Int) -> Bool {
        guard validateGlobalShortcut(.init(keyCode: keyCode, modifiers: modifiers), replacing: "全屏截图") else { return false }
        fullScreenShortcutKey = keyCode
        fullScreenShortcutModifiers = modifiers
        
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        return true
    }
    
    @discardableResult
    func saveLongScreenshotShortcut(keyCode: Int, modifiers: Int) -> Bool {
        guard validateGlobalShortcut(.init(keyCode: keyCode, modifiers: modifiers), replacing: "长截图") else { return false }
        longScreenshotShortcutKey = keyCode
        longScreenshotShortcutModifiers = modifiers
        
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        return true
    }

    private func validateGlobalShortcut(_ shortcut: EditorShortcut, replacing title: String) -> Bool {
        shortcutError = nil
        if shortcut.keyCode == -1 { return true }
        if let conflict = globalShortcuts.first(where: { $0.title != title && $0.shortcut.conflicts(with: shortcut) }) {
            shortcutError = "已用于全局“\(conflict.title)”"
        } else if let item = ToolbarItem.allCases.first(where: { editorShortcuts[$0.rawValue]?.conflicts(with: shortcut) == true }) {
            shortcutError = "已用于编辑工具“\(item.title)”"
        }
        return shortcutError == nil
    }
}
