import AppKit
import Observation

/// Keeps the registered hot key in step with the setting.
///
/// Registration can fail — `RegisterEventHotKey` refuses a combination another
/// application already holds — and that failure has to be visible: a key that
/// silently never fires reads as a broken app rather than as a taken shortcut.
@MainActor
@Observable
final class HotKeyController {
    private let preferences: Preferences
    private let action: () -> Void
    private var registered: GlobalHotKey?

    /// The combination macOS refused, if the current setting is one. Cleared by
    /// the next successful registration.
    private(set) var rejected: HotKeyCombo?

    init(preferences: Preferences, action: @escaping () -> Void) {
        self.preferences = preferences
        self.action = action
    }

    /// (Re-)registers from the setting. Safe to call repeatedly: the previous
    /// registration is dropped first, because two hot keys on one combination
    /// would leave the old one live after a change.
    func apply() {
        registered?.invalidate()
        registered = nil
        rejected = nil

        guard let combo = preferences.hotKey else { return }
        guard let hotKey = GlobalHotKey(combo, action: action) else {
            rejected = combo
            return
        }
        registered = hotKey
    }
}
