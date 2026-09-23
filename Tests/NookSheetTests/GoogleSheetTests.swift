import Testing
import NookCore
@testable import NookSheet

@Suite("Google Sheet addressing")
struct SheetAddressTests {

    /// The one check of addressing against live data: slot 10:00 → row 13,
    /// the first date → column B, and that cell held a booking.
    @Test("10:00 on the first date is B13")
    func knownCell() throws {
        let slot = try #require(SheetGrid.slotIndex(of: TimeOfDay(hour: 10)))
        #expect(slot == 8)
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: slot) == "B13")
    }

    /// Row 53 of the tab holds the 20:00 label and is not a slot, so the last
    /// addressable row is 52 — see `SheetGrid`.
    @Test("First and last slot of the day")
    func dayEdges() throws {
        let first = try #require(SheetGrid.slotIndex(of: SheetGrid.dayStart))
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: first) == "B5")

        let last = SheetGrid.slotCount - 1
        #expect(SheetGrid.slots[last] == TimeOfDay(hour: 19, minute: 45))
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: last) == "B52")
        #expect(SheetGrid.slotIndex(of: SheetGrid.dayEnd) == nil)
    }

    /// An hour is four rows, and the person pastes into all of them at once.
    @Test("A booking longer than a slot addresses a range")
    func spanOfSlots() throws {
        let slot = try #require(SheetGrid.slotIndex(of: TimeOfDay(hour: 10)))
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: slot, slots: 1) == "B13")
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: slot, slots: 3) == "B13:B15")
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: slot, slots: 4) == "B13:B16")
    }

    /// A span that would run off the end of the day stops at the last row
    /// rather than pointing at rows the grid does not have.
    @Test("The range is clipped to the end of the day")
    func spanClippedAtDayEnd() {
        let last = SheetGrid.slotCount - 1
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: last, slots: 4) == "B52")
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: last - 1, slots: 8) == "B51:B52")
    }

    @Test("The tenth date is column K")
    func lastDateColumn() {
        #expect(SheetAddress.column(dateIndex: 9) == "K")
    }

    @Test("Columns past Z")
    func columnNames() {
        #expect(SheetAddress.columnName(0) == "A")
        #expect(SheetAddress.columnName(25) == "Z")
        #expect(SheetAddress.columnName(26) == "AA")
        #expect(SheetAddress.columnName(27) == "AB")
    }

    @Test("The link carries the tab’s gid and the cell address")
    func deepLink() throws {
        let c1 = try #require(Space.named("C1"))
        let url = SheetAddress.deepLink(spreadsheetID: "SHEET", space: c1, dateIndex: 0, slotIndex: 8)
        #expect(url.absoluteString ==
            "https://docs.google.com/spreadsheets/d/SHEET/edit#gid=1248761150&range=B13")
    }

    @Test("The link selects the whole booking, not its first cell")
    func deepLinkSpan() throws {
        let c1 = try #require(Space.named("C1"))
        let url = SheetAddress.deepLink(spreadsheetID: "SHEET", space: c1,
                                        dateIndex: 0, slotIndex: 8, slots: 4)
        #expect(url.absoluteString ==
            "https://docs.google.com/spreadsheets/d/SHEET/edit#gid=1248761150&range=B13:B16")
    }

    /// The duration reaches the address through the request, so a 45-minute
    /// booking selects three rows without anybody counting slots by hand.
    @Test("The source turns a request into a range")
    func sourceAddressesTheRequest() throws {
        let c1 = try #require(Space.named("C1"))
        let date = CalendarDate(year: 2026, month: 9, day: 18)
        let schedule = Schedule(spaces: [c1], dates: [date], slots: SheetGrid.slots,
                                cells: [c1.id: [[String?](repeating: nil, count: SheetGrid.slotCount)]])
        let source = GoogleSheetSource(spreadsheetID: "SHEET")
        let query = Query(date: date, start: TimeOfDay(hour: 10), minutes: 45)

        let url = try #require(source.bookingLink(for: c1, query: query, in: schedule))
        #expect(url.absoluteString.hasSuffix("&range=B13:B15"))
    }

    @Test("The ID is pulled out of a link pasted from the browser", arguments: [
        "https://docs.google.com/spreadsheets/d/ABC123_x-y/edit#gid=0&range=B13",
        "https://docs.google.com/spreadsheets/d/ABC123_x-y/edit?usp=sharing",
        "https://docs.google.com/spreadsheets/d/ABC123_x-y",
        "ABC123_x-y",
        "  ABC123_x-y  ",
    ])
    func parsesSpreadsheetID(input: String) {
        #expect(GoogleSheet.spreadsheetID(from: input) == "ABC123_x-y")
    }

    @Test("Neither a link nor an identifier — the setting is refused",
          arguments: ["", "   ", "https://example.com/", "some text with spaces",
                      "https://example.com/spreadsheets/d/ABC123/edit",
                      "https://docs.google.com/spreadsheets/d/not%20an%20id/edit"])
    func rejectsGarbage(input: String) {
        #expect(GoogleSheet.spreadsheetID(from: input) == nil)
    }

    @Test("A time off the slot boundary has no address")
    func offGrid() {
        #expect(SheetGrid.slotIndex(of: TimeOfDay(hour: 10, minute: 7)) == nil)
        #expect(SheetGrid.slotIndex(of: TimeOfDay(hour: 7, minute: 45)) == nil)
        #expect(SheetGrid.slotIndex(of: TimeOfDay(hour: 20, minute: 15)) == nil)
        // 20:00 is where the day ends, not a slot to start a booking in.
        #expect(SheetGrid.slotIndex(of: TimeOfDay(hour: 20)) == nil)
    }

    @Test("The grid is 48 slots tiling 8:00 up to 20:00")
    func gridShape() {
        #expect(SheetGrid.slots.count == 48)
        #expect(SheetGrid.slots.first == SheetGrid.dayStart)
        #expect(SheetGrid.slots.last == TimeOfDay(hour: 19, minute: 45))
        // The slots tile the day exactly: the last one ends where the day does.
        #expect(SheetGrid.slots.last?.adding(minutes: SheetGrid.slotMinutes) == SheetGrid.dayEnd)
    }
}
