import AppKit
import CoreGraphics

/// Fixed metrics of the overlay.
///
/// Its own type rather than a static on `OverlayView`: the width is needed by
/// the panel, by the view and by the size preference, and a static on a view
/// that is pinned to the main actor cannot be read from a `PreferenceKey`.
enum OverlayMetrics {
    /// 460 rather than the 520 it started at: once the bookings were listed,
    /// the right-hand “how soon” column sat a hundred points away from the
    /// times, and the gap read as an empty column.
    ///
    /// **What sets the floor is the line of keys at the bottom**, which is on
    /// screen in every state. Measured in the fonts the app draws it in, the
    /// widest translation of it is 416 pt (Russian; English 415), against
    /// 420 pt of content at this width — four points of slack. At 440 both wrap
    /// to a second line.
    ///
    /// Not everything fits, and that is deliberate. Six strings out of the
    /// catalogue’s thirty-six wrap here — the period listing of “that day is
    /// not in the sheet”, the Serbian “paste the link to your booking sheet”,
    /// the Russian line of query examples. All of them are rare, and the
    /// content is laid out with `fixedSize(horizontal: false, vertical: true)`,
    /// so a long line wraps rather than being cut: the panel gains a row and
    /// says everything it meant to.
    ///
    /// Going narrower means shortening the hints themselves, not the window.
    static let width: CGFloat = 460

    /// The rounding of the panel. The view's material and the window's own
    /// mask both take it, so the two cannot disagree.
    static let cornerRadius: CGFloat = 14
}

/// The overlay window.
///
/// `.nonactivatingPanel` plus `canBecomeKey` is the defining property of the
/// whole thing: the panel takes keyboard input **without activating the app**
/// and without stealing focus from whatever a person is working in. The
/// `.statusBar` level and the collection behaviour put it above full-screen
/// windows on any desktop.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// ⌘, — settings, the way every other Mac application opens them.
    var onSettings: (() -> Void)?

    /// Handled on the panel rather than on a SwiftUI button: the shortcut
    /// belongs to **every** state of the overlay, while the ⓘ button exists
    /// only in the one where no name has been set. A key equivalent also has
    /// to work while the query field holds focus, and the field editor sees
    /// plain key presses first — a key equivalent goes down this path instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "," {
            onSettings?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
