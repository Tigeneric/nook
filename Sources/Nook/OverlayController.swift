import AppKit
import SwiftUI
import NookCore

/// What ⏎ managed to do. The overlay needs to know, because one of these is
/// the single case where it stays on screen instead of stepping aside.
enum BookingOpenResult {
    case opened
    /// The clipboard holds something that cannot be put back afterwards, so
    /// the name was not copied and nothing was opened — the person’s own
    /// clipboard is worth more than the convenience. Pressing ⏎ again opens
    /// the sheet without copying, and the name is then picked in the sheet.
    case clipboardUnavailable
    /// The source offers nowhere to write. Nothing for the overlay to say.
    case nothingToOpen
}

/// Showing and hiding the overlay, re-reading the schedule on every showing.
@MainActor
final class OverlayController {
    private let preferences: Preferences
    private let store: ScheduleStore
    private let onSettings: () -> Void
    private let clipboard: BookingClipboard
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
        self.clipboard = BookingClipboard()
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
        // The rounded material alone is not enough before macOS 26: there the
        // hosting view fills the whole window and its corners stay square.
        // Clipping the layer rounds them on every version, and the shadow,
        // taken from what is drawn, follows the curve.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = OverlayMetrics.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting

        store.reload()
        center(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        store.cancel()
        panel?.orderOut(nil)
    }

    func restoreClipboardBeforeTermination() {
        clipboard.restoreBeforeTermination()
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
            onOpen: { [weak self] space, query, copyName in
                self?.open(space, query, copyName: copyName) ?? .nothingToOpen
            },
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

    /// Opens the space tab with the booking’s cells selected, and puts the
    /// person’s name on the clipboard so that the whole span takes one ⌘V.
    ///
    /// The first version does not write to the sheet — the keystroke is the
    /// person’s, and so is the decision to overwrite anything that has
    /// appeared in those cells since the schedule was read.
    /// `copyName` is false on the second press: the first one found the
    /// clipboard impossible to put back and said so, and going ahead without
    /// the copy is then the person’s own decision.
    private func open(_ space: Space, _ query: Query, copyName: Bool) -> BookingOpenResult {
        guard let schedule = store.schedule,
              let url = store.source?.bookingLink(for: space, query: query, in: schedule)
        else { return .nothingToOpen }

        // Nothing to offer when the name was never set: the overlay says so
        // instead of promising a paste that would put an empty line in.
        // The sheet's own spelling when it has one, and the typed name when it
        // does not. The cell is validated against the roster literally, while
        // a name is matched folded, so the two forms of one name part company
        // exactly here — see `Agenda.canonicalName`.
        if copyName, let typed = preferences.bookingName {
            let name = Agenda.canonicalName(for: typed, in: schedule) ?? typed
            // A refusal stops here on purpose. The sheet is not opened and the
            // overlay is not hidden: with four cells selected and the old
            // clipboard still loaded, ⌘V would put it into the sheet, and the
            // person would have no way of learning why.
            // Which application the link will open in is known before opening
            // it, and leaving that application is the end of the booking.
            let browser = NSWorkspace.shared.urlForApplication(toOpen: url)
                .flatMap { Bundle(url: $0)?.bundleIdentifier }
            guard clipboard.place(name, slots: query.slotCount,
                                  hold: preferences.clipboardHold, openedIn: browser) else {
                return .clipboardUnavailable
            }
        }
        NSWorkspace.shared.open(url)
        hide()
        return .opened
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
