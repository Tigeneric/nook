import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Nook

/// Bound to the main actor: the label is asked of the current keyboard layout
/// through Text Input Services, and those are not safe to call from the
/// arbitrary threads a test run uses.
@Suite("The hot key")
@MainActor
struct HotKeyComboTests {
    /// Only keys that carry a name or a glyph are asserted in full: a letter
    /// key is labelled from the keyboard layout in use, so on a Russian one
    /// `⌃⌥N` reads `⌃⌥Т` — the same physical key, honestly named.
    @Test("A combination reads as the glyphs a menu would show", arguments: [
        (UInt32(kVK_Space), UInt32(optionKey), "⌥Space"),
        (UInt32(kVK_Space), UInt32(controlKey | optionKey), "⌃⌥Space"),
        (UInt32(kVK_Return), UInt32(cmdKey), "⌘↩"),
        (UInt32(kVK_Escape), UInt32(shiftKey), "⇧⎋"),
        (UInt32(kVK_F5), UInt32(0), "F5"),
    ])
    func description(keyCode: UInt32, modifiers: UInt32, expected: String) {
        #expect(HotKeyCombo(keyCode: keyCode, modifiers: modifiers).description == expected)
    }

    /// The glyph order is the one macOS uses, not the order of the mask.
    @Test("Modifiers are written in the system order")
    func modifierOrder() {
        let all = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        #expect(HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: all).description == "⌃⌥⇧⌘Space")
    }

    /// The binding is by physical key code, so the label follows the layout
    /// and cannot be asserted — only that the key is named at all, and that
    /// the modifiers in front of it are.
    @Test("A letter key is named by the active layout")
    func letterFollowsLayout() {
        let combo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey))
        #expect(combo.description.hasPrefix("⌃⌥"))
        #expect(combo.description.count > 2)
        #expect(!combo.description.hasSuffix("#\(kVK_ANSI_N)"))    // not the fallback
    }

    @Test("A key press becomes a combination")
    func fromEvent() throws {
        let combo = try #require(HotKeyCombo(event: press(kVK_Space, [.option, .command])))
        #expect(combo.keyCode == UInt32(kVK_Space))
        #expect(combo.description == "⌥⌘Space")
    }

    /// A bare key is refused because a global hot key takes the press away
    /// from every other application — binding `N` would lose the letter.
    @Test("A key without modifiers is refused", arguments: [kVK_ANSI_N, kVK_Space, kVK_Return])
    func refusesBareKey(keyCode: Int) {
        #expect(HotKeyCombo(event: press(keyCode, [])) == nil)
    }

    @Test("A function key may stand alone")
    func allowsBareFunctionKey() throws {
        let combo = try #require(HotKeyCombo(event: press(kVK_F5, [])))
        #expect(combo.description == "F5")
        #expect(combo.modifiers == 0)
    }

    /// Caps Lock and the numeric-pad flag are not modifiers anyone means.
    @Test("Flags that are not modifiers do not make a combination")
    func ignoresStrayFlags() {
        #expect(HotKeyCombo(event: press(kVK_ANSI_N, [.capsLock, .numericPad])) == nil)
    }

    @Test("Every preset is a combination the recorder would also accept")
    func presetsAreValid() {
        for preset in HotKeyCombo.presets {
            #expect(preset.modifiers != 0, "\(preset) would be stolen from other apps")
        }
    }

    private func press(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }
}

@Suite("Storing the hot key")
@MainActor
struct HotKeyPreferencesTests {
    @Test("Nothing stored means the default combination")
    func freshInstall() {
        #expect(makePreferences().hotKey == .default)
    }

    @Test("A chosen combination survives a restart")
    func remembersCombination() {
        let defaults = makeDefaults()
        let combo = HotKeyCombo(keyCode: UInt32(kVK_F9), modifiers: UInt32(cmdKey))
        Preferences(defaults: defaults).setHotKey(combo)

        #expect(Preferences(defaults: defaults).hotKey == combo)
    }

    /// “Off” and “never configured” are different states: without that
    /// distinction the default would come back on the next launch.
    @Test("Off is remembered rather than read as unset")
    func remembersOff() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).setHotKey(nil)

        #expect(Preferences(defaults: defaults).hotKey == nil)
    }

    @Test("Turning it back on after off restores a combination")
    func backOn() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.setHotKey(nil)
        preferences.setHotKey(.default)

        #expect(Preferences(defaults: defaults).hotKey == .default)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "HotKeyPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makePreferences() -> Preferences {
        Preferences(defaults: makeDefaults())
    }
}
