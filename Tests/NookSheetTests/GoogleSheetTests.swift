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

    @Test("First and last slot of the day")
    func dayEdges() throws {
        let first = try #require(SheetGrid.slotIndex(of: SheetGrid.dayStart))
        let last = try #require(SheetGrid.slotIndex(of: SheetGrid.dayEnd))
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: first) == "B5")
        #expect(last == SheetGrid.slotCount - 1)
        #expect(SheetAddress.a1(dateIndex: 0, slotIndex: last) == "B53")
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
    }

    @Test("The grid is 49 slots from 8:00 to 20:00")
    func gridShape() {
        #expect(SheetGrid.slots.count == 49)
        #expect(SheetGrid.slots.first == TimeOfDay(hour: 8))
        #expect(SheetGrid.slots.last == TimeOfDay(hour: 20))
    }
}
