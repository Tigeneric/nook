import Foundation
import NookCore

/// One parsed space tab.
public struct RoomTab: Sendable {
    /// The title from `B1` — for diagnostics only. Identification goes by
    /// `gid`: titles lie (a typo, trailing spaces, inconsistent word order).
    public let title: String
    public let dates: [CalendarDate]
    public let slots: [TimeOfDay]
    /// Who holds the cell, or `nil`. Indexing: `cells[dateIndex][slotIndex]`.
    public let cells: [[String?]]
}

public enum RoomTabParseError: Error, CustomStringConvertible, Sendable {
    case tooFewRows(Int)
    case noDates
    case invalidDate(column: Int, value: String)
    case unexpectedSlots(expected: Int, got: Int)
    case unexpectedSlot(row: Int, expected: TimeOfDay, got: String)
    case malformedCSV

    public var description: String {
        switch self {
        case let .tooFewRows(count):
            "the tab has \(count) rows — the header is incomplete"
        case .noDates:
            "row 3 holds no dates"
        case let .invalidDate(column, value):
            "column \(column) holds an invalid date: \(value)"
        case let .unexpectedSlots(expected, got):
            "expected \(expected) slots, the tab has \(got)"
        case let .unexpectedSlot(row, expected, got):
            "row \(row) should hold \(expected), got \(got)"
        case .malformedCSV:
            "the tab is not valid CSV"
        }
    }
}

/// Space tab → model. Layout of a tab:
/// row 1 — title, 2 — start of the period, 3 — dates, 4 — weekday names,
/// 5…53 — slots from 8:00 to 20:00, time in column A.
public enum RoomTabParser {
    public static func parse(_ text: String) throws -> RoomTab {
        let rows: [[String]]
        do {
            rows = try CSVReader.rows(from: text)
        } catch {
            throw RoomTabParseError.malformedCSV
        }
        guard rows.count > SheetAddress.headerRows else {
            throw RoomTabParseError.tooFewRows(rows.count)
        }

        let title = cell(rows[0], 1).trimmingCharacters(in: .whitespaces)

        // Row 3: dates from column B onwards. Empty trailing columns are skipped.
        let dateRow = rows[2]
        var dates: [CalendarDate] = []
        let lastDateColumn = dateRow.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let lastDateColumn, lastDateColumn >= SheetAddress.firstDateColumn else {
            throw RoomTabParseError.noDates
        }
        for column in SheetAddress.firstDateColumn...lastDateColumn {
            let raw = cell(dateRow, column).trimmingCharacters(in: .whitespaces)
            guard let date = CalendarDate(sheetLabel: raw) else {
                throw RoomTabParseError.invalidDate(column: column + 1, value: raw)
            }
            dates.append(date)
        }
        guard !dates.isEmpty else { throw RoomTabParseError.noDates }

        // Slot rows: for as long as column A holds a time.
        var slots: [TimeOfDay] = []
        var byDate: [[String?]] = Array(repeating: [], count: dates.count)
        let slotRows = rows.dropFirst(SheetAddress.headerRows)
        guard slotRows.count >= SheetGrid.slotCount else {
            throw RoomTabParseError.unexpectedSlots(expected: SheetGrid.slotCount, got: slotRows.count)
        }
        for (slotIndex, row) in slotRows.prefix(SheetGrid.slotCount).enumerated() {
            let rawSlot = cell(row, 0).trimmingCharacters(in: .whitespaces)
            let expectedSlot = SheetGrid.slots[slotIndex]
            guard let slot = TimeOfDay(sheetLabel: rawSlot), slot == expectedSlot else {
                throw RoomTabParseError.unexpectedSlot(
                    row: SheetAddress.headerRows + slotIndex + 1,
                    expected: expectedSlot,
                    got: rawSlot
                )
            }
            slots.append(slot)
            for dateIndex in dates.indices {
                let raw = cell(row, SheetAddress.firstDateColumn + dateIndex)
                    .trimmingCharacters(in: .whitespaces)
                byDate[dateIndex].append(raw.isEmpty ? nil : raw)
            }
        }
        return RoomTab(title: title, dates: dates, slots: slots, cells: byDate)
    }

    private static func cell(_ row: [String], _ index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }
}
