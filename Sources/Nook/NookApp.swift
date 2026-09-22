import SwiftUI
import AppKit

@main
struct NookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Where the menu bar icon goes, in points from the right edge of the
        // screen. Unset, macOS puts a new icon leftmost, right by the notch,
        // and on a full menu bar that is the one hidden under it. A registered
        // default only fills the gap: once the icon is ⌘-dragged, macOS stores
        // the person's position under the same key and that one wins.
        // `Item-0` is the autosave name SwiftUI gives the MenuBarExtra's item.
        UserDefaults.standard.register(defaults: [
            "NSStatusItem Preferred Position Item-0": 100,
        ])
    }

    var body: some Scene {
        MenuBarExtra("Nook", systemImage: "rectangle.grid.3x2") {
            // The combination is configurable, so the menu reads it rather
            // than spelling it out: a stale ⌥Space here would be a lie.
            if let combo = delegate.preferences.hotKey {
                Button("Show overlay  \(combo.description)") { delegate.overlay.show() }
            } else {
                Button("Show overlay") { delegate.overlay.show() }
            }
            Button("Settings…") { delegate.settings.show() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `--demo` puts a made-up day behind the panel and settings of its own
    /// behind the app, so it can be shown — and photographed — without a sheet.
    /// See `Demo`: the README’s pictures cannot be taken against the real one.
    private static let isDemo = CommandLine.arguments.contains("--demo")

    let preferences: Preferences = isDemo ? Demo.preferences() : Preferences()
    let loginItem = LoginItem()
    // The types are spelled out: these three refer to one another, and left to
    // inference the compiler has to resolve a cycle it cannot.
    lazy var overlay: OverlayController = OverlayController(
        preferences: preferences,
        sourceFactory: Self.isDemo ? { _ in DemoSource() } : nil
    ) { [weak self] in
        guard let self else { return }
        // While no name is set, settings opened from the overlay land on the
        // name field — that is the only thing the overlay had to say about
        // them, whether it was the ⓘ or ⌘, that asked.
        settings.show(focusing: preferences.bookingName == nil ? .bookingName : nil)
    }
    lazy var hotKeys: HotKeyController = HotKeyController(preferences: preferences) { [weak self] in
        self?.overlay.toggle()
    }
    lazy var settings: SettingsWindow = SettingsWindow(
        preferences: preferences,
        loginItem: loginItem,
        hotKeys: hotKeys
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app lives in the menu bar: no Dock icon, no window at launch.
        NSApp.setActivationPolicy(.accessory)

        hotKeys.apply()
        if let rejected = hotKeys.rejected {
            NSLog("Nook: could not register \(rejected) — the combination is taken by another app")
        }

        // Without a sheet there is nothing to read, so a first run starts in settings.
        if CommandLine.arguments.contains("--show-settings") {
            settings.show()
        } else if preferences.isConfigured {
            showOverlayIfRequested()
        } else {
            settings.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.restoreClipboardBeforeTermination()
    }

    /// Opening the app again - Spotlight, Finder, `open` - while it runs brings
    /// up settings. The menu bar icon is not guaranteed to be seen: macOS hides
    /// what does not fit, under the notch included, and there is no API to keep
    /// it in. This is the way back in that does not depend on it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// `--show-overlay [query]` opens the panel right at launch: a hot key
    /// cannot be pressed from the command line, and both a person and an agent
    /// need to look at the overlay. `--show-settings` does the same for the
    /// settings window, which otherwise opens only from the menu bar.
    /// For example:
    /// `Nook.app/Contents/MacOS/Nook --show-overlay "14:00 45m"`
    private func showOverlayIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--show-overlay") else { return }
        let query = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
        overlay.show(query: query)
    }
}
