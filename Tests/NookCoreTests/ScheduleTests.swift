import Testing
@testable import NookCore

/// A one-date schedule built from “who holds which slots”.
private func schedule(_ occupied: [String: [Int: String]]) -> Schedule {
    let date = CalendarDate(year: 2026, month: 9, day: 18)
    var cells: [String: [[String?]]] = [:]
    for space in Space.all {
        let byName = occupied[space.id] ?? [:]
        cells[space.id] = [(0..<SheetGrid.slotCount).map { byName[$0] }]
    }
    return Schedule(spaces: Space.all, dates: [date], slots: SheetGrid.slots, cells: cells)
}

private let testDate = CalendarDate(year: 2026, month: 9, day: 18)

@Suite("Merging blocks")
struct BlockTests {

    @Test("Three hours of one name is a single block")
    func mergesEqualNames() throws {
        // Marko Jurić, C3, 14:00–17:00 — slots 24…35.
        let slots = Dictionary(uniqueKeysWithValues: (24..<36).map { ($0, "Marko Jurić") })
        let schedule = schedule(["C3": slots])
        let c3 = try #require(Space.named("C3"))

        let blocks = schedule.blocks(space: c3, dateIndex: 0)
        #expect(blocks == [Schedule.Block(name: "Marko Jurić", startSlot: 24, slotCount: 12)])
    }

    @Test("Different names in a row are different blocks")
    func keepsDifferentNamesApart() throws {
        // C4 on the 18th: Acme 2…6, one slot each. Five bookings, not one.
        let slots = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0 + 16, "Acme \($0 + 2)") })
        let schedule = schedule(["C4": slots])
        let c4 = try #require(Space.named("C4"))

        let blocks = schedule.blocks(space: c4, dateIndex: 0)
        #expect(blocks.count == 5)
        #expect(blocks.allSatisfy { $0.slotCount == 1 })
        #expect(blocks.map(\.name) == ["Acme 2", "Acme 3", "Acme 4", "Acme 5", "Acme 6"])
    }

    @Test("Identical names across a gap do not merge")
    func gapBreaksBlock() throws {
        let schedule = schedule(["C1": [4: "Ana Petrović", 6: "Ana Petrović"]])
        let c1 = try #require(Space.named("C1"))

        let blocks = schedule.blocks(space: c1, dateIndex: 0)
        #expect(blocks.count == 2)
    }

    @Test("A block running to the end of the day is closed")
    func blockAtDayEnd() throws {
        let last = SheetGrid.slotCount - 1
        let schedule = schedule(["O1": [last - 1: "Nikola Savić", last: "Nikola Savić"]])
        let o1 = try #require(Space.named("O1"))

        #expect(schedule.blocks(space: o1, dateIndex: 0)
            == [Schedule.Block(name: "Nikola Savić", startSlot: last - 1, slotCount: 2)])
    }
}

@Suite("Finding free spaces")
struct AvailabilityTests {

    @Test("A taken space is not a candidate")
    func excludesOccupied() throws {
        // C1 is taken from 14:00 (slot 24) for an hour.
        let slots = Dictionary(uniqueKeysWithValues: (24..<28).map { ($0, "Ana Petrović") })
        let schedule = schedule(["C1": slots])

        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 45)
        let free = Availability.fits(query, in: schedule)

        #expect(!free.contains { $0.id == "C1" })
        #expect(free.count == Space.all.count - 1)
    }

    @Test("An overlap at the tail counts as taken too")
    func excludesOverlapAtTail() throws {
        let slots = Dictionary(uniqueKeysWithValues: (24..<28).map { ($0, "Ana Petrović") })
        let schedule = schedule(["C1": slots])

        // 13:30 plus an hour: the last half overlaps the booking.
        let query = Query(date: testDate, start: TimeOfDay(hour: 13, minute: 30), minutes: 60)
        #expect(!Availability.fits(query, in: schedule).contains { $0.id == "C1" })
    }

    @Test("A request running past the end of the day fits nowhere")
    func pastDayEnd() {
        let query = Query(date: testDate, start: TimeOfDay(hour: 19, minute: 45), minutes: 60)
        #expect(Availability.fits(query, in: .init(spaces: Space.all, dates: [testDate],
                                                   slots: SheetGrid.slots, cells: [:])).isEmpty)
    }

    @Test("The date is not in the sheet — no candidates")
    func unknownDate() {
        let query = Query(date: CalendarDate(year: 2030, month: 1, day: 1),
                          start: TimeOfDay(hour: 14), minutes: 30)
        #expect(Availability.fits(query, in: schedule([:])).isEmpty)
    }

    @Test("Missing source data is unavailable, not free")
    func missingCellsAreUnavailable() {
        let incomplete = Schedule(
            spaces: Space.all,
            dates: [testDate],
            slots: SheetGrid.slots,
            cells: [:]
        )
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 30)

        #expect(Availability.fits(query, in: incomplete).isEmpty)
    }

    @Test("A named space is the only candidate")
    func honoursNamedSpace() {
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 45, spaceID: "C2")
        #expect(Availability.fits(query, in: schedule([:])).map(\.id) == ["C2"])
    }

    @Test("The named space is taken — no candidates, though others are free")
    func namedSpaceBusy() {
        let slots = Dictionary(uniqueKeysWithValues: (24..<28).map { ($0, "Nikola Savić") })
        let schedule = schedule(["C2": slots])
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 45, spaceID: "C2")

        #expect(Availability.fits(query, in: schedule).isEmpty)
        #expect(Availability.fits(query.anySpace, in: schedule).count == Space.all.count - 1)
    }

    @Test("Who holds the named space")
    func occupantsOfNamedSpace() throws {
        let schedule = schedule(["C4": [24: "Acme 2", 25: "Acme 3", 26: "Acme 3"]])
        let c4 = try #require(Space.named("C4"))
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 45, spaceID: "C4")

        #expect(Availability.occupants(of: c4, during: query, in: schedule) == ["Acme 2", "Acme 3"])
    }

    @Test("A free space is held by nobody")
    func occupantsOfFreeSpace() throws {
        let o1 = try #require(Space.named("O1"))
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 45)
        #expect(Availability.occupants(of: o1, during: query, in: schedule([:])).isEmpty)
    }

    @Test("The window around a request is the bounds of the free run")
    func freeWindow() throws {
        // C2 is taken 13:00–14:30 (slots 20…25) and 15:00–16:00 (slots 28…31),
        // with a 14:30–15:00 gap between them.
        var slots = Dictionary(uniqueKeysWithValues: (20..<26).map { ($0, "Nikola Savić") })
        for slot in 28..<32 { slots[slot] = "PetarNikolic" }
        let schedule = schedule(["C2": slots])
        let c2 = try #require(Space.named("C2"))

        let tight = Query(date: testDate, start: TimeOfDay(hour: 14, minute: 30), minutes: 30)
        let window = try #require(Availability.freeWindow(for: tight, in: c2, of: schedule))
        #expect(window.start == TimeOfDay(hour: 14, minute: 30))
        #expect(window.end == TimeOfDay(hour: 15))
        #expect(window.isTightBefore(tight))
        #expect(window.isTightAfter(tight))
    }

    @Test("The two edges differ: a booking on the left, open until evening on the right")
    func windowEdgesDiffer() throws {
        // C4 is taken 13:00–14:30 (slots 20…25), then empty until the end of the day.
        let slots = Dictionary(uniqueKeysWithValues: (20..<26).map { ($0, "Marko Jurić") })
        let schedule = schedule(["C4": slots])
        let c4 = try #require(Space.named("C4"))

        let query = Query(date: testDate, start: TimeOfDay(hour: 14, minute: 30), minutes: 30)
        let window = try #require(Availability.freeWindow(for: query, in: c4, of: schedule))

        #expect(window.start == TimeOfDay(hour: 14, minute: 30))
        #expect(window.startsAtBooking)          // a booking on the left
        #expect(!window.endsAtBooking)           // the end of the day on the right
        #expect(window.isTightBefore(query))
        #expect(!window.isTightAfter(query))
    }

    @Test("A request in the middle of a roomy window is flush against nothing")
    func windowWithSlack() throws {
        let slots = Dictionary(uniqueKeysWithValues: (20..<26).map { ($0, "Marko Jurić") })
        let schedule = schedule(["C4": slots])
        let c4 = try #require(Space.named("C4"))

        // 16:00 — an hour and a half after the booking ends.
        let query = Query(date: testDate, start: TimeOfDay(hour: 16), minutes: 30)
        let window = try #require(Availability.freeWindow(for: query, in: c4, of: schedule))

        #expect(window.startsAtBooking)
        #expect(!window.isTightBefore(query))    // a booking, but not flush
        #expect(!window.isTightAfter(query))
    }

    @Test("An empty space gives a window spanning the whole day")
    func freeWindowWholeDay() throws {
        let o1 = try #require(Space.named("O1"))
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 30)
        let window = try #require(Availability.freeWindow(for: query, in: o1, of: schedule([:])))

        // The whole day is 8:00–20:00 and stops there: the sheet's 20:00 row is
        // the end of the day, not a slot, so the window does not run to 20:15.
        #expect(window.start == SheetGrid.dayStart)
        #expect(window.end == SheetGrid.dayEnd)
    }

    @Test("A taken space has no window")
    func noWindowWhenBusy() throws {
        let slots = Dictionary(uniqueKeysWithValues: (24..<28).map { ($0, "Ana Petrović") })
        let c1 = try #require(Space.named("C1"))
        let query = Query(date: testDate, start: TimeOfDay(hour: 14), minutes: 45)

        #expect(Availability.freeWindow(for: query, in: c1, of: schedule(["C1": slots])) == nil)
    }

    @Test("Free runs are cut by a booking")
    func freeWindows() throws {
        let slots = Dictionary(uniqueKeysWithValues: (24..<28).map { ($0, "Ana Petrović") })
        let schedule = schedule(["C1": slots])
        let c1 = try #require(Space.named("C1"))

        let windows = Availability.freeWindows(space: c1, dateIndex: 0, in: schedule)
        #expect(windows == [0..<24, 28..<SheetGrid.slotCount])
    }
}

@Suite("The space catalogue")
struct SpaceCatalogTests {

    @Test("Eight spaces, in the column order of the design")
    func order() {
        #expect(Space.all.map(\.id) == ["C1", "C2", "C3", "C4", "MR1", "O1", "O2", "MR2"])
    }

    @Test("The source keys are unique")
    func uniqueSourceKeys() {
        #expect(Set(Space.all.map(\.sourceKey)).count == Space.all.count)
    }

    @Test("Floors and kinds")
    func floorsAndKinds() {
        #expect(Space.all.filter { $0.floor == 1 }.map(\.id) == ["C1", "C2", "C3", "C4", "MR1"])
        #expect(Space.all.filter { $0.kind == .room }.map(\.id) == ["MR1", "MR2"])
    }
}

@Suite("Calendar date")
struct CalendarDateTests {

    @Test("Parsing the sheet’s format")
    func parsesSheetLabel() throws {
        let date = try #require(CalendarDate(sheetLabel: "18/09/2026"))
        #expect((date.year, date.month, date.day) == (2026, 9, 18))
        #expect(date.description == "18/09/2026")
    }

    @Test("Garbage does not become a date", arguments: [
        "", "18.09.2026", "2026-09-18", "18/13/2026", "31/02/2026", "29/02/2026",
    ])
    func rejectsGarbage(text: String) {
        #expect(CalendarDate(sheetLabel: text) == nil)
    }

    @Test("Weekdays match the sheet")
    func weekdays() throws {
        // Row 4 of the tab: 18/09/2026 is FRIDAY, 21/09/2026 is MONDAY.
        #expect(try #require(CalendarDate(sheetLabel: "18/09/2026")).weekdayIndex == 5)
        #expect(try #require(CalendarDate(sheetLabel: "21/09/2026")).weekdayIndex == 1)
    }

    @Test("Days since the epoch, and back")
    func epochRoundTrip() {
        #expect(CalendarDate(year: 1970, month: 1, day: 1).daysSinceEpoch == 0)
        #expect(CalendarDate(daysSinceEpoch: 0) == CalendarDate(year: 1970, month: 1, day: 1))
        for shift in [-800, -1, 0, 1, 365, 20_718] {
            let date = CalendarDate(daysSinceEpoch: shift)
            #expect(date.daysSinceEpoch == shift)
        }
    }

    @Test("Adding days crosses month, year and leap-February boundaries")
    func addingDays() {
        #expect(CalendarDate(year: 2026, month: 9, day: 30).adding(days: 1)
            == CalendarDate(year: 2026, month: 10, day: 1))
        #expect(CalendarDate(year: 2026, month: 12, day: 31).adding(days: 1)
            == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(CalendarDate(year: 2028, month: 2, day: 28).adding(days: 1)
            == CalendarDate(year: 2028, month: 2, day: 29))
        #expect(CalendarDate(year: 2026, month: 9, day: 21).adding(days: -3)
            == CalendarDate(year: 2026, month: 9, day: 18))
    }

    @Test("The nearest weekday")
    func nextWeekday() {
        let monday = CalendarDate(year: 2026, month: 9, day: 21)
        #expect(monday.next(weekday: 1) == monday)                                   // Monday itself
        #expect(monday.next(weekday: 5) == CalendarDate(year: 2026, month: 9, day: 25))
        #expect(monday.next(weekday: 0) == CalendarDate(year: 2026, month: 9, day: 27))
    }
}
