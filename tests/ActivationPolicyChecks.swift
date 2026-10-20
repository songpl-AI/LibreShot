import AppKit

@main struct ActivationPolicyChecks {
    static func main() {
        precondition(AppActivationPolicy.policy(showInDock: false) == .accessory,
                     "Dock icon off must keep the menu-bar-only policy")
        precondition(AppActivationPolicy.policy(showInDock: true) == .regular,
                     "Dock icon on must use the regular policy")
        precondition(AppActivationPolicy.needsForegroundPolicy(current: .accessory),
                     "Accessory apps must borrow a foreground policy for system panels")
        precondition(!AppActivationPolicy.needsForegroundPolicy(current: .regular),
                     "Regular apps must not toggle their policy for system panels")
        print("PASS: Dock visibility maps to activation policy and system panels only borrow .regular from .accessory")
    }
}
