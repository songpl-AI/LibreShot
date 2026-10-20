import AppKit

/// Single owner of the app's Dock presence.
///
/// The user preference decides between a menu-bar-only app (`.accessory`) and a
/// regular app with a Dock icon (`.regular`). System panels may borrow `.regular`
/// temporarily, but they must restore the preference rather than a stale value.
@MainActor
enum AppActivationPolicy {
    nonisolated static func policy(showInDock: Bool) -> NSApplication.ActivationPolicy {
        showInDock ? .regular : .accessory
    }

    nonisolated static func needsForegroundPolicy(current: NSApplication.ActivationPolicy) -> Bool {
        current == .accessory
    }

    static var preferred: NSApplication.ActivationPolicy {
        policy(showInDock: SettingsService.shared.showInDock)
    }

    static func apply() {
        guard NSApp.activationPolicy() != preferred else { return }
        NSApp.setActivationPolicy(preferred)
    }

    /// Returns true when the policy was changed and the caller must restore it.
    static func beginForegroundPanel() -> Bool {
        guard needsForegroundPolicy(current: NSApp.activationPolicy()) else { return false }
        NSApp.setActivationPolicy(.regular)
        return true
    }

    static func endForegroundPanel(_ changed: Bool) {
        guard changed else { return }
        NSApp.setActivationPolicy(preferred)
    }
}
