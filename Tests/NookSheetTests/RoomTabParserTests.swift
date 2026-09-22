import Testing
import NookCore
@testable import NookSheet

/// CSV of a space tab: a four-row header and 49 slots.
/// `occupied` holds names by (slot index, date index).
private func tabCSV(
    title: String = "Phone Booth C1 ",
    dates: [String] = ["18/09/2026", "21/09/2026"],
    occupied: [Int: [Int: String]] = [:],
    slotCount: Int = SheetGrid.slotCount
) -> String {
    var lines = [
        ",\(title)" + String(repeating: ",", count: dates.count),
        "September 18" + String(repeating: ",", count: dates.count),
        "," + dates.joined(separator: ","),
        "," + dates.map { _ in "FRIDAY" }.joined(separator: ","),
    ]
    for slotIndex in 0..<slotCount {
        let time = SheetGrid.slots[slotIndex].description
        let cells = dates.indices.map { occupied[slotIndex]?[$0] ?? "" }
        lines.append(([time] + cells).joined(separator: ","))
    }
    // The last line has no newline — as in the real export.
    return lines.joined(separator: "\n")
}

@Suite("Space tab parsing")
struct RoomTabParserTests {

    @Test("Header, dates and slots")
    func shape() throws {
        let tab = try RoomTabParser.parse(tabCSV())
        #expect(tab.title == "Phone Booth C1")
        #expect(tab.dates == [CalendarDate(year: 2026, month: 9, day: 18),
                              CalendarDate(year: 2026, month: 9, day: 21)])
        #expect(tab.slots.count == SheetGrid.slotCount)
        #expect(tab.slots.first == TimeOfDay(hour: 8))
        #expect(tab.slots.last == TimeOfDay(hour: 20))
    }

    @Test("A name lands in its own cell")
    func occupantLandsInPlace() throws {
        // 10:00 on the first date is the verified cell B13.
        let tab = try RoomTabParser.parse(tabCSV(occupied: [8: [0: "Ana Petrović"]]))
        #expect(tab.cells[0][8] == "Ana Petrović")
        #expect(tab.cells[1][8] == nil)
        #expect(tab.cells[0][7] == nil)
    }

    @Test("An empty cell is nil, not an empty string")
    func emptyIsNil() throws {
        let tab = try RoomTabParser.parse(tabCSV())
        #expect(tab.cells.allSatisfy { $0.allSatisfy { $0 == nil } })
    }

    @Test("An incomplete grid is an error, not a silent shift")
    func rejectsShortGrid() {
        #expect(throws: RoomTabParseError.self) {
            try RoomTabParser.parse(tabCSV(slotCount: 40))
        }
    }

    @Test("A tab without dates is an error")
    func rejectsNoDates() {
        #expect(throws: RoomTabParseError.self) {
            try RoomTabParser.parse(tabCSV(dates: []))
        }
    }

    @Test("An invalid date between valid dates is rejected instead of shifting columns")
    func rejectsDateHole() {
        #expect(throws: RoomTabParseError.self) {
            try RoomTabParser.parse(tabCSV(dates: ["18/09/2026", "bad", "21/09/2026"]))
        }
    }

    @Test("The slot labels must match the fixed grid")
    func rejectsShiftedSlots() {
        let shifted = tabCSV().replacingOccurrences(of: "\n8:15,", with: "\n8:00,")
        #expect(throws: RoomTabParseError.self) {
            try RoomTabParser.parse(shifted)
        }
    }

    @Test("A fragment instead of a tab is an error")
    func rejectsTruncated() {
        #expect(throws: RoomTabParseError.self) {
            try RoomTabParser.parse("Phone Booth C1\n")
        }
    }
}
