import AppKit

extension NSApplication {
    /// Transitions the app to a regular foreground application (shows Dock icon)
    func elevate() {
        if activationPolicy() != .regular {
            setActivationPolicy(.regular)
        }
        
        // Bring everything to front
        windows.forEach { window in
            window.collectionBehavior = [.moveToActiveSpace, .managed]
        }
        
        activate(ignoringOtherApps: true)
    }

    /// Transitions the app back to an accessory background application (hides Dock icon)
    func lower() {
        if activationPolicy() != .accessory {
            setActivationPolicy(.accessory)
        }
    }
}
