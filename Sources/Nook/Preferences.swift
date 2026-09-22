import Foundation
import NookCore
import NookSheet
import Observation

/// Application settings. They live in `UserDefaults` on a person’s machine.
///
/// The sheet ID lives here — the only thing that differs between installs, and
/// the only thing that must not reach the repository: the sheet is read
/// without authorisation, so its identifier amounts to access to every booking
/// name.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let spreadsheetID = "spreadsheetID"
        static let bookingName = "bookingName"
        static let floor = "floor"
        static let hotKeyOff = "hotKeyOff"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let clipboardHoldSeconds = "clipboardHoldSeconds"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spreadsheetID = defaults.string(forKey: Key.spreadsheetID)
        bookingName = Self.normalizedBookingName(defaults.string(forKey: Key.bookingName) ?? "")
        // 0 means “all floors”, which is also what an unset value looks like.
        let stored = defaults.integer(forKey: Key.floor)
        floor = stored == 0 ? nil : stored
        hotKey = Self.storedHotKey(in: defaults)
        // “Never restore” is stored as 0, which is also what an unset value
        // reads as — so the two are told apart by the key’s presence.
        clipboardHoldSeconds = defaults.object(forKey: Key.clipboardHoldSeconds) == nil
            ? BookingClipboard.defaultHoldSeconds
            : defaults.integer(forKey: Key.clipboardHoldSeconds)
    }

    /// The combination that shows the overlay; `nil` means nobody set one —
    /// the overlay is then reachable only from the menu bar.
    ///
    /// “Off” and “never configured” are different states, and one number cannot
    /// carry both: hence a separate flag. Without it a fresh install and a
    /// deliberate “off” would be indistinguishable, and the default would come
    /// back on every launch.
    private(set) var hotKey: HotKeyCombo?

    func setHotKey(_ combo: HotKeyCombo?) {
        hotKey = combo
        guard let combo else {
            defaults.set(true, forKey: Key.hotKeyOff)
            return
        }
        defaults.set(false, forKey: Key.hotKeyOff)
        defaults.set(Int(combo.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(combo.modifiers), forKey: Key.hotKeyModifiers)
    }

    private static func storedHotKey(in defaults: UserDefaults) -> HotKeyCombo? {
        if defaults.bool(forKey: Key.hotKeyOff) { return nil }
        guard defaults.object(forKey: Key.hotKeyCode) != nil else { return .default }
        return HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Key.hotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
        )
    }

    /// How long the copied booking name stays on the clipboard, in seconds.
    /// `0` means it is left there until something else is copied.
    ///
    /// Chosen from a list rather than typed: the value has to exceed however
    /// long the sheet takes to open in a browser, and one that is too small
    /// means ⌘V puts the previous clipboard into cells the whole coworking
    /// shares. A list cannot express a value that is merely a slip of the
    /// finger; whether the chosen one is long enough is still the person’s
    /// call, and the slow end of the list is what a slow sheet is for.
    private(set) var clipboardHoldSeconds: Int

    func setClipboardHoldSeconds(_ seconds: Int) {
        clipboardHoldSeconds = seconds
        defaults.set(seconds, forKey: Key.clipboardHoldSeconds)
    }

    /// `nil` — do not put the previous clipboard back at all.
    var clipboardHold: Duration? {
        clipboardHoldSeconds > 0 ? .seconds(clipboardHoldSeconds) : nil
    }

    /// The floor a person restricted the search to. `nil` means all of them.
    ///
    /// The coworking occupies two floors, and walking between them is usually
    /// not worth it: “O2 is free” is of little use to someone sitting on the
    /// first floor.
    var floor: Int? {
        didSet {
            if let floor {
                defaults.set(floor, forKey: Key.floor)
            } else {
                defaults.removeObject(forKey: Key.floor)
            }
        }
    }

    /// The spaces the search runs over, with the chosen floor applied.
    func spaces(from all: [Space]) -> [Space] {
        guard let floor else { return all }
        return all.filter { $0.floor == floor }
    }

    /// How this person’s own bookings are spelled in the sheet.
    ///
    /// A cell holds nothing but text, and the sheet has no idea who is reading
    /// it — so without this there is no way to tell someone’s own rows from
    /// everyone else’s, and the overlay shows no agenda at all. `nil` means it
    /// was never filled in.
    ///
    /// Stays on this machine, like the rest of the settings: it is a person’s
    /// own name, and it has no business leaving.
    private(set) var bookingName: String?

    /// Blank is stored as “not set”: a field cleared by hand means the same as
    /// one never filled in. Tabs and line breaks cannot be part of the value:
    /// Sheets treats them as TSV separators and would paste outside the booking.
    func setBookingName(_ input: String) {
        bookingName = Self.normalizedBookingName(input)
        if let bookingName {
            defaults.set(bookingName, forKey: Key.bookingName)
        } else {
            defaults.removeObject(forKey: Key.bookingName)
        }
    }

    static func normalizedBookingName(_ input: String) -> String? {
        let safe = replacingBookingSeparators(in: input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? nil : safe
    }

    static func replacingBookingSeparators(in input: String) -> String {
        input.map { character in
            character == "\t" || character.isNewline ? " " : String(character)
        }.joined()
    }

    /// `nil` until the sheet has been configured.
    private(set) var spreadsheetID: String?

    var isConfigured: Bool { spreadsheetID != nil }

    /// Accepts both a browser link and a bare ID. Returns `false` when
    /// nothing could be recognised — the previous setting then stays.
    @discardableResult
    func setSpreadsheet(_ input: String) -> Bool {
        guard let id = GoogleSheet.spreadsheetID(from: input) else { return false }
        spreadsheetID = id
        defaults.set(id, forKey: Key.spreadsheetID)
        return true
    }

    func clearSpreadsheet() {
        spreadsheetID = nil
        defaults.removeObject(forKey: Key.spreadsheetID)
    }
}
