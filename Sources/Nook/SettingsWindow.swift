import AppKit
import Observation
import SwiftUI

/// What the settings window should put the caret in when it opens.
///
/// A token rather than a flag: the ⓘ in the overlay can be clicked again while
/// the window is already open, and a flag that is already `true` does not
/// change — so nothing would move.
@MainActor
@Observable
final class SettingsFocus {
    enum Field {
        case bookingName
    }

    private(set) var field: Field?
    private(set) var token = 0

    func request(_ field: Field) {
        self.field = field
        token += 1
    }
}

/// The settings window.
///
/// A plain `NSWindow` rather than a `Settings` scene: the app lives in the
/// menu bar as an accessory, and on first launch the scene’s window does not
/// come forward — the scene is not registered yet when it is asked to open.
@MainActor
final class SettingsWindow {
    private let preferences: Preferences
    private let loginItem: LoginItem
    private let hotKeys: HotKeyController
    private let focus = SettingsFocus()
    /// A store of its own: the name typed here is checked against the sheet,
    /// and the overlay’s store is gone by the time this window is open.
    private let store: ScheduleStore
    private var window: NSWindow?

    init(preferences: Preferences, loginItem: LoginItem, hotKeys: HotKeyController) {
        self.preferences = preferences
        self.loginItem = loginItem
        self.hotKeys = hotKeys
        self.store = ScheduleStore(preferences: preferences)
    }

    func show(focusing field: SettingsFocus.Field? = nil) {
        let window = window ?? make()
        self.window = window

        // The login item may have been switched off in System Settings while
        // this window was closed.
        loginItem.refresh()
        // Re-read for the same reason the overlay does: the sheet is edited
        // during the day, and a name checked against yesterday is a lie.
        store.reload()
        if let field {
            focus.request(field)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// The window never goes below this. The size is generous on purpose:
    /// the form’s `fittingSize` understates the height, and the content slides
    /// under a scroll bar.
    private static let minimumSize = NSSize(width: 520, height: 460)

    private func make() -> NSWindow {
        let window = EscapableWindow(
            contentRect: NSRect(origin: .zero, size: Self.minimumSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = Self.minimumSize
        window.title = String(localized: "Nook Settings")
        window.isReleasedWhenClosed = false
        window.level = .floating
        let hosting = NSHostingView(rootView: SettingsView(
            preferences: preferences,
            loginItem: loginItem,
            hotKeys: hotKeys,
            store: store,
            focus: focus
        ))
        hosting.sizingOptions = [.preferredContentSize]
        window.contentView = hosting

        // Fit the window to its content, otherwise the form slides under a
        // scroll bar. The size is asked for only after layout: before it,
        // `fittingSize` is zero and the window collapses to a title bar.
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        window.setContentSize(NSSize(
            width: max(fitting.width, Self.minimumSize.width),
            height: max(fitting.height, Self.minimumSize.height)
        ))
        return window
    }
}

/// A window that closes on Esc.
///
/// `NSWindow` does not handle Esc on its own: the command reaches it only if
/// the text editor inside did not take it first — there the first Esc cancels
/// editing, which is its rightful behaviour.
private final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
