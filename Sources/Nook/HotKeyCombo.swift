import AppKit
import Carbon.HIToolbox

/// The key combination that shows the overlay.
///
/// Stored and registered by **physical key code**, not by character: that is
/// what `RegisterEventHotKey` takes, and it keeps the combination on the same
/// physical key when a person switches keyboard layout. The label can go stale
/// after such a switch; the binding does not.
struct HotKeyCombo: Sendable, Hashable, CustomStringConvertible {
    let keyCode: UInt32
    /// A Carbon modifier mask — `optionKey`, `cmdKey`, `shiftKey`, `controlKey`.
    let modifiers: UInt32

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    /// What settings offer without recording. The list is deliberately short:
    /// a long one invites picking a combination the system has already taken,
    /// and then the key silently never fires.
    static let presets: [HotKeyCombo] = [
        .default,
        HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)),
    ]

    /// A combination from a key press, or `nil` when it would be a bad hot key.
    ///
    /// A key without modifiers is refused unless it is a function key: a global
    /// hot key takes the press away from every other application, and someone
    /// who bound a bare `N` would lose the letter everywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }

        let code = UInt32(event.keyCode)
        guard mask != 0 || Self.functionKeys.keys.contains(code) else { return nil }
        self.init(keyCode: code, modifiers: mask)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// `⌥Space`, `⌃⌥N`, `F5` — the order of glyphs is the one macOS uses in menus.
    var description: String {
        var glyphs = ""
        if modifiers & UInt32(controlKey) != 0 { glyphs += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { glyphs += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { glyphs += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { glyphs += "⌘" }
        return glyphs + Self.label(for: keyCode)
    }

    private static func label(for keyCode: UInt32) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let named = functionKeys[keyCode] { return named }
        return layoutLabel(for: keyCode) ?? "#\(keyCode)"
    }

    /// Keys that have a name or a glyph rather than a character.
    private static let namedKeys: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
    ]

    /// The only keys allowed to stand without a modifier.
    static let functionKeys: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    /// The character the physical key produces on the layout in use. Asked of
    /// the layout rather than kept in a table of its own: on a Russian layout
    /// the key next to `L` is `Ж`, and a table would call it `;`.
    private static func layoutLabel(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,                                      // no modifiers: the glyphs carry them
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeys,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
