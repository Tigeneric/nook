import Foundation
import NookCore

/// The Google Sheet this adapter reads: document address and cell addressing.
///
/// Everything Google-shaped lives in this module. The core knows only
/// `ScheduleSource`, so pointing Nook at a different kind of source means
/// writing a sibling of this file rather than touching the logic.
///
/// The sheet identifier is **not** in the code and must not be. The sheet is
/// read without authorisation, which makes its ID the key to every booking
/// name in the coworking; an open repository is no place for it. The ID is set
/// in the app’s settings and stays on the person’s machine.
public enum GoogleSheet {
    /// CSV export of a tab. Readable without authorisation — verified.
    public static func csvExportURL(spreadsheetID: String, gid: String) -> URL {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv&gid=\(gid)")!
    }

    /// The ID out of whatever a person pasted into settings: a whole link from
    /// the browser, or the identifier itself.
    ///
    /// `nil` when there is nothing to recognise. People paste the whole link,
    /// and demanding they cut the ID out by hand only creates a way to get it
    /// wrong.
    public static func spreadsheetID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           components.scheme == "https", components.host == "docs.google.com",
           let range = components.path.range(of: "/spreadsheets/d/") {
            let tail = components.path[range.upperBound...]
            let id = tail.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            let value = String(id)
            return isValidID(value) ? value : nil
        }
        // A bare identifier: Google issues letters, digits, dash and underscore.
        return isValidID(trimmed) ? trimmed : nil
    }

    private static func isValidID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Cell addressing inside a space tab.
///
/// ```
/// row    = 5 + slotIndex          slotIndex = (minutes − 480) / 15
/// column = 'B' + dateIndex
/// ```
///
/// Verified against a live cell: 10:00 → slot 8 → row 13; the first date →
/// index 0 → column `B`. Every space tab is laid out the same way, so the
/// space does not affect the address inside the tab — it only picks which tab
/// the link opens.
public enum SheetAddress {
    /// How many header rows come before the first slot (rows 1–4).
    public static let headerRows = 4
    /// Column of the first date: `B`, the second one.
    public static let firstDateColumn = 1

    public static func row(slotIndex: Int) -> Int {
        headerRows + 1 + slotIndex
    }

    public static func column(dateIndex: Int) -> String {
        columnName(firstDateColumn + dateIndex)
    }

    /// The address of a booking: one cell, or the span of slots it covers —
    /// `B13` for a quarter of an hour, `B13:B16` for an hour.
    ///
    /// The span is what a person pastes into, so it must not run past the end
    /// of the day: a booking that starts at 19:30 and lasts two hours is
    /// clipped to the last row of the grid rather than addressing rows that
    /// hold nothing.
    public static func a1(dateIndex: Int, slotIndex: Int, slots: Int = 1) -> String {
        let column = column(dateIndex: dateIndex)
        let first = row(slotIndex: slotIndex)
        let lastRow = row(slotIndex: SheetGrid.slotCount - 1)
        let last = min(first + max(1, slots) - 1, lastRow)
        guard last > first else { return "\(column)\(first)" }
        return "\(column)\(first):\(column)\(last)"
    }

    /// A link that opens the space tab with the booking’s cells selected.
    ///
    /// The first version uses it instead of writing to the sheet. The URL
    /// fragment is handled by the client only, so no HTTP request can verify
    /// that it works — it is checked by opening it in a browser.
    ///
    /// The whole span is selected rather than its first cell: it shows the
    /// person how long the booking they are about to make is, and one paste
    /// then fills all of it.
    public static func deepLink(
        spreadsheetID: String,
        space: Space,
        dateIndex: Int,
        slotIndex: Int,
        slots: Int = 1
    ) -> URL {
        let cells = a1(dateIndex: dateIndex, slotIndex: slotIndex, slots: slots)
        return URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/edit#gid=\(space.sourceKey)&range=\(cells)")!
    }

    /// 0 → `A`, 25 → `Z`, 26 → `AA`.
    static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + index % 26))) + name
            index = index / 26 - 1
        } while index >= 0
        return name
    }
}
