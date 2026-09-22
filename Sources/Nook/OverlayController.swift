import AppKit
import SwiftUI
import NookCore

/// Showing and hiding the overlay, re-reading the schedule on every showing.
@MainActor
final class OverlayController {
    private let preferences: Preferences
    private let store: ScheduleStore
    private let onSettings: () -> Void
    private var panel: OverlayPanel?

    /// `onSettings` is injected rather than reached for: the overlay knows
    /// that settings exist, not how the window is built. `sourceFactory` is
    /// the same seam `ScheduleStore` has — `--demo` puts a made-up day behind
    /// the panel through it.
    init(
        preferences: Preferences,
        sourceFactory: ((String) -> any ScheduleSource)? = nil,
        onSettings: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.store = sourceFactory.map { ScheduleStore(preferences: preferences, sourceFactory: $0) }
            ?? ScheduleStore(preferences: preferences)
        self.onSettings = onSettings
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// `query` pre-fills the input line — needed by the `--show-overlay`
    /// launch flag; on an ordinary showing the line is empty.
    func show(query: String = "") {
        let panel = panel ?? makePanel()
        self.panel = panel

        // The content is rebuilt on every showing: “today” and “now” go stale,
        // and the input line should open empty. Rebuilt rather than updated:
        // swapping `rootView` on an existing `NSHostingView` keeps the view’s
        // identity, and with it the `@State` of the previous showing — the
        // input line would still hold the previous request.
        let hosting = NSHostingView(rootView: makeView(query: query, panel: panel))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting

        store.reload()
        center(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        store.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: OverlayMetrics.width, height: 160))
        panel.onSettings = { [weak self] in self?.openSettings() }
        return panel
    }

    /// The overlay closes on the way out. The settings window activates the
    /// app, and a non-activating panel that stayed behind it would be a window
    /// nobody asked to keep.
    private func openSettings() {
        hide()
        onSettings()
    }

    private func makeView(query: String = "", panel: NSPanel) -> OverlayView {
        OverlayView(
            store: store,
            preferences: preferences,
            today: CalendarDate(Date()),
            now: Self.timeOfDayNow(),
            query: query,
            onOpen: { [weak self] space, query in self?.open(space, query) },
            onClose: { [weak self] in self?.hide() },
            onSettings: { [weak self] in self?.openSettings() },
            onResize: { [weak self, weak panel] size in
                guard let self, let panel else { return }
                self.resize(panel, to: size)
            }
        )
    }

    private func resize(_ panel: NSPanel, to contentSize: CGSize) {
        let screen = panel.screen ?? NSScreen.main
        let maximumHeight = (screen?.visibleFrame.height ?? contentSize.height) * 0.8
        let size = NSSize(width: contentSize.width, height: min(contentSize.height, maximumHeight))
        guard abs(panel.contentLayoutRect.height - size.height) > 0.5 else { return }
        panel.setContentSize(size)
        center(panel)
    }

    /// Opens the space tab with the booking’s cells selected. The first
    /// version does not write to the sheet — a person types the name in
    /// themselves.
    private func open(_ space: Space, _ query: Query) {
        guard let schedule = store.schedule,
              let url = store.source?.bookingLink(for: space, query: query, in: schedule)
        else { return }

        NSWorkspace.shared.open(url)
        hide()
    }

    private func center(_ panel: NSPanel) {
        // The screen with the pointer, not the main one: the overlay comes up
        // where the person is looking.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.1
        ))
    }

    private static func timeOfDayNow() -> TimeOfDay {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}
