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

private func multiDaySchedule(dates: [CalendarDate], occupied: [String: [[Int: String]]] = [:]) -> Schedule {
    var cells: [String: [[String?]]] = [:]
    for space in Space.all {
        let byDate = occupied[space.id] ?? []
        cells[space.id] = dates.indices.map { dateIndex in
            let bySlot = byDate.indices.contains(dateIndex) ? byDate[dateIndex] : [:]
            return (0..<SheetGrid.slotCount).map { bySlot[$0] }
        }
    }
    return Schedule(spaces: Space.all, dates: dates, slots: SheetGrid.slots, cells: cells)
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

    @Test("Empty space has a window for the whole day, 8:00–20:00")
    func emptySpaceWindow() throws {
        let s = schedule([:])
        let mr1 = try #require(Space.named("MR1"))
        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: testDate, after: nil))
        #expect(window.date == testDate)
        #expect(window.start == SheetGrid.dayStart)
        #expect(window.end == SheetGrid.dayEnd)
    }

    @Test("Window is trimmed on the left by now")
    func windowTrimmedByNow() throws {
        let s = schedule([:])
        let mr1 = try #require(Space.named("MR1"))
        let now = TimeOfDay(hour: 8, minute: 10)
        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: testDate, after: now))
        #expect(window.date == testDate)
        #expect(window.start == TimeOfDay(hour: 8, minute: 15))
        #expect(window.end == SheetGrid.dayEnd)
    }

    @Test("Booking cuts the window on the right")
    func bookingCutsWindowOnRight() throws {
        let slots = Dictionary(uniqueKeysWithValues: (8..<12).map { ($0, "Ana") })
        let s = schedule(["MR1": slots])
        let mr1 = try #require(Space.named("MR1"))
        let now = TimeOfDay(hour: 8, minute: 5)
        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: testDate, after: now))
        #expect(window.date == testDate)
        #expect(window.start == TimeOfDay(hour: 8, minute: 15))
        #expect(window.end == TimeOfDay(hour: 10, minute: 0))
    }

    @Test("When no slots remain today, window advances to the next sheet date")
    func advancesToNextSheetDate() throws {
        let date1 = CalendarDate(year: 2026, month: 9, day: 18)
        let date2 = CalendarDate(year: 2026, month: 9, day: 21)
        let s = multiDaySchedule(dates: [date1, date2], occupied: [:])
        let mr1 = try #require(Space.named("MR1"))
        let evening = TimeOfDay(hour: 19, minute: 50)
        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: date1, after: evening))
        #expect(window.date == date2)
        #expect(window.start == SheetGrid.dayStart)
        #expect(window.end == SheetGrid.dayEnd)
    }

    @Test("Named day is counted from start of day, not from now")
    func namedDayStartsAtDayStart() throws {
        let date1 = CalendarDate(year: 2026, month: 9, day: 18)
        let date2 = CalendarDate(year: 2026, month: 9, day: 21)
        let s = multiDaySchedule(dates: [date1, date2], occupied: [:])
        let mr1 = try #require(Space.named("MR1"))
        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: date2, after: nil))
        #expect(window.date == date2)
        #expect(window.start == SheetGrid.dayStart)
        #expect(window.end == SheetGrid.dayEnd)
    }

    @Test("Date not in schedule returns nil")
    func dateNotInSchedule() throws {
        let s = schedule([:])
        let mr1 = try #require(Space.named("MR1"))
        let otherDate = CalendarDate(year: 2026, month: 9, day: 30)
        #expect(Availability.nextWindow(space: mr1, in: s, from: otherDate, after: nil) == nil)
        #expect(Availability.freeWindows(space: mr1, in: s, from: otherDate, after: nil).isEmpty)
    }

    @Test("Free runs of the day asked about filter by minMinutes")
    func freeWindowsDurationFilter() throws {
        var day1: [Int: String] = [:]
        for slot in 4..<8 { day1[slot] = "User" }
        for slot in 10..<12 { day1[slot] = "User" }
        for slot in 20..<48 { day1[slot] = "User" }

        let date1 = CalendarDate(year: 2026, month: 9, day: 18)
        let date2 = CalendarDate(year: 2026, month: 9, day: 21)
        let s = multiDaySchedule(dates: [date1, date2], occupied: ["C1": [day1, [:]]])
        let c1 = try #require(Space.named("C1"))

        // 10:00–10:30 is half an hour and drops out; the two survivors are both
        // of date1, and date2 stays out of it — the day still has something.
        let runs = Availability.freeWindows(space: c1, in: s, from: date1, after: nil, minMinutes: 45)
        #expect(runs.count == 2)
        #expect(runs[0].date == date1 && runs[0].start == TimeOfDay(hour: 8) && runs[0].end == TimeOfDay(hour: 9))
        #expect(runs[1].date == date1 && runs[1].start == TimeOfDay(hour: 11) && runs[1].end == TimeOfDay(hour: 13))
        #expect(runs.allSatisfy { $0.date == date1 })
    }

    /// The defect this exists for: the list walked the sheet to its last date,
    /// so an empty space answered «when are you free» with one row per date —
    /// four days in four rows, and the six dates past the ceiling vanished
    /// without a counter. The day asked about is the answer; the next date is a
    /// fallback for a day that has nothing, not a continuation of one that has.
    @Test("A day with windows does not spill into the following dates")
    func doesNotSpillPastTheDayAsked() throws {
        let date1 = CalendarDate(year: 2026, month: 9, day: 18)
        let date2 = CalendarDate(year: 2026, month: 9, day: 21)
        let date3 = CalendarDate(year: 2026, month: 9, day: 22)
        let s = multiDaySchedule(dates: [date1, date2, date3], occupied: [:])
        let mr1 = try #require(Space.named("MR1"))

        let free = Availability.freeWindows(space: mr1, in: s, from: date1, after: nil)
        #expect(free.count == 1)
        #expect(free[0].date == date1)

        // A day booked solid is what moves the answer on — and only by one day,
        // because that next day has a window of its own.
        let solid = Dictionary(uniqueKeysWithValues: (0..<SheetGrid.slotCount).map { ($0, "User") })
        let blocked = multiDaySchedule(dates: [date1, date2, date3], occupied: ["MR1": [solid, [:], [:]]])
        let afterBlock = Availability.freeWindows(space: mr1, in: blocked, from: date1, after: nil)
        #expect(afterBlock.count == 1)
        #expect(afterBlock[0].date == date2)
    }

    @Test("Weekend query advances to Monday without truncating by Saturday time")
    func weekendAdvancesToMonday() throws {
        let monday = CalendarDate(year: 2026, month: 9, day: 21)
        let s = multiDaySchedule(dates: [monday], occupied: [:])
        let mr1 = try #require(Space.named("MR1"))
        let saturday = CalendarDate(year: 2026, month: 9, day: 19)
        let afternoon = TimeOfDay(hour: 15, minute: 30)

        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: saturday, after: afternoon))
        #expect(window.date == monday)
        #expect(window.start == SheetGrid.dayStart)
        #expect(window.end == SheetGrid.dayEnd)

        let windows = Availability.freeWindows(space: mr1, in: s, from: saturday, after: afternoon)
        #expect(windows.count == 1)
        #expect(windows[0].date == monday)
        #expect(windows[0].start == SheetGrid.dayStart)
        #expect(!windows[0].isOpenNow)
    }

    @Test("Space open at now is flagged as isOpenNow and bookable from next slot")
    func isOpenNowFlag() throws {
        let s = schedule([:])
        let mr1 = try #require(Space.named("MR1"))
        let now = TimeOfDay(hour: 14, minute: 4)

        let windows = Availability.freeWindows(space: mr1, in: s, from: testDate, after: now)
        #expect(!windows.isEmpty)
        #expect(windows[0].start == TimeOfDay(hour: 14, minute: 15))
        #expect(windows[0].isOpenNow)

        // If occupied during now, isOpenNow is false
        let occupiedSlots = Dictionary(uniqueKeysWithValues: (24..<26).map { ($0, "User") })
        let busySchedule = schedule(["MR1": occupiedSlots])
        let busyWindows = Availability.freeWindows(space: mr1, in: busySchedule, from: testDate, after: now)
        #expect(!busyWindows.isEmpty)
        #expect(busyWindows[0].start == TimeOfDay(hour: 14, minute: 30))
        #expect(!busyWindows[0].isOpenNow)
    }

    @Test("nextWindow with minMinutes skips short windows")
    func nextWindowDurationFilter() throws {
        // Free: 8:00-8:30 (30m), busy: 8:30-9:00, free: 9:00-11:00 (2h)
        let busySlots = Dictionary(uniqueKeysWithValues: (2..<4).map { ($0, "User") })
        let s = schedule(["MR1": busySlots])
        let mr1 = try #require(Space.named("MR1"))

        let window = try #require(Availability.nextWindow(space: mr1, in: s, from: testDate, after: nil, minMinutes: 60))
        #expect(window.start == TimeOfDay(hour: 9, minute: 0))
        #expect(window.end == SheetGrid.dayEnd)
    }

    @Test("Fully booked space returns nil and empty list")
    func fullyBookedSpace() throws {
        let allSlots = Dictionary(uniqueKeysWithValues: (0..<SheetGrid.slotCount).map { ($0, "User") })
        let s = schedule(["MR1": allSlots])
        let mr1 = try #require(Space.named("MR1"))

        #expect(Availability.nextWindow(space: mr1, in: s, from: testDate, after: nil) == nil)
        #expect(Availability.freeWindows(space: mr1, in: s, from: testDate, after: nil).isEmpty)
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
