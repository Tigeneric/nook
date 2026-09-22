import Foundation

/// The list a booking cell is validated against: every name the sheet will
/// accept, spelled the way the sheet spells it.
///
/// Why it is worth a request of its own. The cells carry a dropdown built from
/// this tab, and the rule behind the dropdown compares literally, while Nook
/// compares names folded — case, diacritics and spaces dropped. A name can
/// therefore find all of its owner's bookings and still be refused when pasted
/// in. The roster is the only place with an answer to “how is it spelled
/// here”, and it answers for people who have never booked at all, which the
/// booking cells cannot.
public enum RosterParser {
    /// Names in the tab's own order.
    ///
    /// Only the first column is read: the tab has exactly one. The first row
    /// goes because it is the column's header rather than a member, and blank
    /// cells go because the export pads its rows out well past the last name.
    public static func parse(_ text: String) throws -> [String] {
        try CSVReader.rows(from: text)
            .dropFirst()
            .compactMap { $0.first?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
