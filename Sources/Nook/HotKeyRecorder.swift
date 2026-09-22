import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Captures one key press for the hot-key setting.
///
/// An `NSView` rather than SwiftUI’s key-press modifiers: the press has to be
/// taken away from the menu as well. Otherwise recording ⌘Q quits the
/// application instead of being recorded — `performKeyEquivalent` is where
/// that is stopped, and returning `true` there tells AppKit the event is
/// handled and must not travel on to the menu.
struct HotKeyRecorder: NSViewRepresentable {
    /// `nil` when the person pressed Esc — recording was cancelled.
    let onFinish: (HotKeyCombo?) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onFinish = onFinish
        // The view becomes first responder only once it is in a window, which
        // it is not while SwiftUI is still assembling the hierarchy.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onFinish = onFinish
    }

    final class CaptureView: NSView {
        var onFinish: ((HotKeyCombo?) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            handle(event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            handle(event)
            return true
        }

        /// Holding ⌘ before the letter is not an attempt at a combination, so
        /// modifier presses are ignored rather than refused.
        override func flagsChanged(with event: NSEvent) {}

        private func handle(_ event: NSEvent) {
            let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            if bare, event.keyCode == UInt16(kVK_Escape) {
                onFinish?(nil)
                return
            }
            // An unusable press (a bare letter) leaves recording running: the
            // footer says what is needed, and an error flash for “not yet a
            // combination” would be noise.
            guard let combo = HotKeyCombo(event: event) else { return }
            onFinish?(combo)
        }
    }
}
