import AppKit
import SwiftUI

/// The query input line.
///
/// A hand-made field rather than `TextField`, for the sake of the caret: the
/// arrows edit the fragment it stands on and have to put it back afterwards.
/// SwiftUI only offers a selection binding from macOS 15, and the deployment
/// target is macOS 14.
struct QueryField: NSViewRepresentable {
    /// Text and caret after an edit; `nil` means the event is not ours.
    typealias Edit = (text: String, caret: Int)?

    @Binding var text: String
    let placeholder: String
    /// Hides the blinking caret while the focus is elsewhere — over the list of
    /// bookings below.
    ///
    /// The field stays first responder, because typing has to keep working and
    /// the first character typed brings the focus back. So the caret is made
    /// invisible rather than surrendered: two places claiming the focus at once
    /// is what a blinking caret over a selected row looked like.
    var caretHidden = false
    /// An arrow: +1 for up, −1 for down — like a stepper, up means more.
    /// Receives the current text and caret position.
    let onArrow: (Int, String, Int) -> Edit
    let onTab: (String, Int) -> Edit
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = OverlayView.queryNSFont
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // The panel is already key by now, but the field becomes first
        // responder only once its view hierarchy has been assembled.
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
            // Focus selects the whole text by default, which puts the caret at
            // offset zero — an arrow would then edit the first fragment rather
            // than the last one typed. Put the caret at the end.
            field.currentEditor()?.selectedRange = NSRange(
                location: (field.stringValue as NSString).length,
                length: 0
            )
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        // The caret belongs to the field editor, which exists only while the
        // field is being edited — so this is set here rather than once at
        // creation, and asked for again on every change.
        (field.currentEditor() as? NSTextView)?.insertionPointColor =
            caretHidden ? .clear : .controlTextColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QueryField

        init(_ parent: QueryField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return apply(parent.onArrow(1, textView.string, caret(textView)), to: textView)
            case #selector(NSResponder.moveDown(_:)):
                return apply(parent.onArrow(-1, textView.string, caret(textView)), to: textView)
            case #selector(NSResponder.insertTab(_:)):
                return apply(parent.onTab(textView.string, caret(textView)), to: textView)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        private func caret(_ textView: NSTextView) -> Int {
            textView.selectedRange().location
        }

        private func apply(_ edit: Edit, to textView: NSTextView) -> Bool {
            guard let edit else { return false }
            textView.string = edit.text
            let length = (edit.text as NSString).length
            textView.setSelectedRange(NSRange(location: min(edit.caret, length), length: 0))
            parent.text = edit.text
            return true
        }
    }
}
