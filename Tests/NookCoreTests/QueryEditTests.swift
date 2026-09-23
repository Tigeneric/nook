import Testing
@testable import NookCore

/// Anchored to Monday, 21 September 2026, 11:07.
@Suite("Editing a request with the arrows")
struct QueryEditTests {
    let today = CalendarDate(year: 2026, month: 9, day: 21)
    let now = TimeOfDay(hour: 11, minute: 7)

    private func adjust(_ text: String, caret: Int, by delta: Int) -> QueryEdit.Edit? {
        QueryEdit.adjust(text, caret: caret, by: delta, today: today)
    }

    private func suggestion(after text: String, spaces: [Space]) -> String? {
        QueryEdit.suggestion(after: text, today: today, now: now, spaces: spaces)
    }

    // MARK: - Time

    @Test("Caret on the hour — the hour changes")
    func hour() throws {
        let down = try #require(adjust("14:00 45m", caret: 1, by: 1))
        #expect(down.segment == .hour)
        #expect(down.text == "15:00 45m")

        let up = try #require(adjust("14:00 45m", caret: 0, by: -1))
        #expect(up.text == "13:00 45m")
    }

    @Test("Caret on the minutes — the minutes change, by a grid step")
    func minute() throws {
        let edit = try #require(adjust("14:00 45m", caret: 4, by: 1))
        #expect(edit.segment == .minute)
        #expect(edit.text == "14:15 45m")
    }

    @Test("Minutes carry into the hour rather than wrapping inside it")
    func minuteCarriesIntoHour() throws {
        #expect(try #require(adjust("11:45 30m", caret: 4, by: 1)).text == "12:00 30m")
        #expect(try #require(adjust("11:00 30m", caret: 4, by: -1)).text == "10:45 30m")
    }

    @Test("Time stops at the edges of the day")
    func timeStopsAtDayEdges() {
        #expect(adjust("20:00 30m", caret: 1, by: 1) == nil)
        #expect(adjust("8:00 30m", caret: 0, by: -1) == nil)
        #expect(adjust("20:00 30m", caret: 4, by: 1) == nil)
        // 19:45 is the last slot: a step forward would land on 20:00, where the
        // day ends, and there is nothing to start there.
        #expect(adjust("19:45 30m", caret: 4, by: 1) == nil)
        #expect(adjust("19:00 30m", caret: 1, by: 1) == nil)
    }

    // MARK: - Duration

    @Test("Caret on the duration — it changes, the time is untouched")
    func duration() throws {
        let edit = try #require(adjust("14:00 45m", caret: 7, by: 1))
        #expect(edit.segment == .duration)
        #expect(edit.text == "14:00 1h")     // a round duration is written in hours

        #expect(try #require(adjust("14:00 45m", caret: 7, by: -1)).text == "14:00 30m")
    }

    @Test("Past an hour the duration is written in hours and minutes")
    func durationInHoursAndMinutes() throws {
        #expect(try #require(adjust("14:00 1h", caret: 7, by: 1)).text == "14:00 1h 15m")
        #expect(try #require(adjust("14:00 1h", caret: 7, by: -1)).text == "14:00 45m")

        // A whole number of hours drops the minutes rather than writing “2h 0m”.
        #expect(try #require(adjust("14:00 1h 45m", caret: 7, by: 1)).text == "14:00 2h")
    }

    @Test("An hour with minutes is one fragment, whichever half the caret is on")
    func compoundDuration() throws {
        let onHours = try #require(adjust("14:00 1h 30m", caret: 7, by: 1))
        #expect(onHours.segment == .duration)
        #expect(onHours.text == "14:00 1h 45m")

        // The caret inside the `30m` edits the same whole duration, not the
        // minutes on their own: `1h 30m` is two and a half slots of one thing.
        #expect(try #require(adjust("14:00 1h 30m", caret: 10, by: -1)).text == "14:00 1h 15m")

        // Down through the hour boundary goes back to plain minutes.
        #expect(try #require(adjust("14:00 1h 15m", caret: 10, by: -1)).text == "14:00 1h")
    }

    @Test("The duration never goes below one slot")
    func durationFloor() {
        #expect(adjust("14:00 15m", caret: 7, by: -1) == nil)
    }

    // MARK: - Day

    @Test("Caret on a weekday — the day changes and stays a word")
    func weekdayStaysAWord() throws {
        let edit = try #require(adjust("пт 14:00", caret: 1, by: 1))
        #expect(edit.segment == .day)
        #expect(edit.text == "сб 14:00")

        #expect(try #require(adjust("fri 14:00", caret: 1, by: -1)).text == "thu 14:00")
    }

    @Test("An arrow gives the day back in the script it was typed in")
    func serbianKeepsItsScript() throws {
        // Today is Monday. Friday minus a day is Thursday, four days out, so
        // it stays a weekday word.
        #expect(try #require(adjust("pet 14:00", caret: 1, by: -1)).text == "čet 14:00")
        #expect(try #require(adjust("пет 14:00", caret: 1, by: -1)).text == "чет 14:00")

        // Wednesday minus a day is tomorrow, and the word changes to
        // “tomorrow”: a near day gets the near word, each in its own script.
        #expect(try #require(adjust("sre 14:00", caret: 1, by: -1)).text == "sutra 14:00")
        #expect(try #require(adjust("сре 14:00", caret: 1, by: -1)).text == "сутра 14:00")

        #expect(try #require(adjust("uto 14:00", caret: 1, by: -1)).text == "danas 14:00")
        #expect(try #require(adjust("уто 14:00", caret: 1, by: -1)).text == "данас 14:00")
    }

    @Test("Days next to today are named “today” and “tomorrow”")
    func todayAndTomorrow() throws {
        // Today is Monday, so “вт” is tomorrow and “ср” the day after.
        #expect(try #require(adjust("ср 14:00", caret: 0, by: -1)).text == "завтра 14:00")
        #expect(try #require(adjust("вт 14:00", caret: 0, by: -1)).text == "сегодня 14:00")
        #expect(try #require(adjust("завтра 14:00", caret: 0, by: -1)).text == "сегодня 14:00")
        #expect(try #require(adjust("tomorrow 14:00", caret: 0, by: -1)).text == "today 14:00")
    }

    @Test("Beyond a week a word would lie — a date is written instead")
    func beyondAWeekBecomesDate() throws {
        // The nearest Sunday is 27/09, +1 is 28/09, and “mon” would parse
        // back as the 21st. Hence a date.
        #expect(try #require(adjust("вс 14:00", caret: 0, by: 1)).text == "28/09/2026 14:00")
    }

    @Test("Caret on a date — the date changes, the format is kept")
    func dateKeepsItsShape() throws {
        #expect(try #require(adjust("23/09 14:00", caret: 1, by: 1)).text == "24/09 14:00")
        #expect(try #require(adjust("23/09/2026 14:00", caret: 1, by: -1)).text == "22/09/2026 14:00")
        #expect(try #require(adjust("30/09 14:00", caret: 1, by: 1)).text == "01/10 14:00")
    }

    /// The sheet’s period: the working days of two weeks, as in the source.
    private var sheetDates: [CalendarDate] {
        [18, 21, 22, 23, 24, 25, 28, 29, 30].map { CalendarDate(year: 2026, month: 9, day: $0) }
            + [CalendarDate(year: 2026, month: 10, day: 1)]
    }

    @Test("Day stepping follows the sheet’s dates and skips weekends")
    func dayStepsThroughSheetDates() throws {
        // Friday 25/09 → Monday 28/09; Saturday and Sunday are skipped.
        let forward = try #require(
            QueryEdit.adjust("25/09 14:00", caret: 1, by: 1, today: today, dates: sheetDates)
        )
        #expect(forward.text == "28/09 14:00")

        let back = try #require(
            QueryEdit.adjust("28/09 14:00", caret: 1, by: -1, today: today, dates: sheetDates)
        )
        #expect(back.text == "25/09 14:00")
    }

    @Test("At the edges of the period day stepping stops")
    func dayStopsAtSheetEdges() {
        #expect(QueryEdit.adjust("01/10 14:00", caret: 1, by: 1, today: today, dates: sheetDates) == nil)
        #expect(QueryEdit.adjust("18/09 14:00", caret: 1, by: -1, today: today, dates: sheetDates) == nil)
    }

    @Test("A day outside the sheet returns to its nearest date")
    func dayReturnsIntoSheet() throws {
        #expect(try #require(
            QueryEdit.adjust("10/11/2026 14:00", caret: 1, by: -1, today: today, dates: sheetDates)
        ).text == "01/10/2026 14:00")
    }

    @Test("Without a loaded schedule day stepping stays calendar-based")
    func dayStepsByCalendarWithoutSchedule() throws {
        #expect(try #require(adjust("23/09 14:00", caret: 1, by: 1)).text == "24/09 14:00")
    }

    // MARK: - Space

    @Test("Caret on a space — cycling through the catalogue")
    func space() throws {
        let edit = try #require(adjust("14:00 45m c2", caret: 11, by: 1))
        #expect(edit.segment == .space)
        #expect(edit.text == "14:00 45m C3")

        #expect(try #require(adjust("14:00 45m c2", caret: 11, by: -1)).text == "14:00 45m C1")
    }

    @Test("Space cycling wraps around")
    func spaceWrapsAround() throws {
        #expect(try #require(adjust("14:00 c1", caret: 6, by: -1)).text == "14:00 MR2")
        #expect(try #require(adjust("14:00 mr2", caret: 6, by: 1)).text == "14:00 C1")
    }

    @Test("Cycling runs over the ring of free spaces, taken ones are skipped")
    func spaceStepsThroughFreeOnly() throws {
        let free = ["C1", "C4", "MR1"].compactMap(Space.named)
        let edit = try #require(
            QueryEdit.adjust("14:00 c1", caret: 6, by: 1, today: today, spaces: free)
        )
        #expect(edit.text == "14:00 C4")
    }

    @Test("A taken space was named — jump to the nearest free one in the direction of travel")
    func jumpsFromBusySpace() throws {
        let free = ["C1", "C4", "MR1"].compactMap(Space.named)
        // C2 is not in the ring: up goes to the next free one by catalogue
        // order (C4), down to the previous one (C1).
        #expect(try #require(
            QueryEdit.adjust("14:00 c2", caret: 6, by: 1, today: today, spaces: free)
        ).text == "14:00 C4")
        #expect(try #require(
            QueryEdit.adjust("14:00 c2", caret: 6, by: -1, today: today, spaces: free)
        ).text == "14:00 C1")
    }

    @Test("A ring of one space leads nowhere")
    func singleFreeSpace() throws {
        let free = [Space.named("O2")].compactMap { $0 }
        #expect(try #require(
            QueryEdit.adjust("14:00 o2", caret: 6, by: 1, today: today, spaces: free)
        ).text == "14:00 O2")
    }

    @Test("Nothing is free — the arrow walks the whole catalogue")
    func emptyRingFallsBackToCatalog() throws {
        #expect(try #require(
            QueryEdit.adjust("14:00 c1", caret: 6, by: 1, today: today, spaces: [])
        ).text == "14:00 C2")
    }

    @Test("A two-word name is edited as a whole")
    func twoWordSpaceName() throws {
        #expect(try #require(adjust("14:00 meeting 1", caret: 7, by: 1)).text == "14:00 O1")
        #expect(try #require(adjust("14:00 meeting 1", caret: 14, by: 1)).text == "14:00 O1")
    }

    // MARK: - Caret

    @Test("The caret stays in its own fragment")
    func caretStaysPut() throws {
        // Minutes: the hour changed length, the caret is still in the minutes.
        let edit = try #require(adjust("9:30 45m", caret: 3, by: 1))
        #expect(edit.text == "9:45 45m")
        #expect(edit.caret == 3)

        let carried = try #require(adjust("9:45 45m", caret: 3, by: 1))
        #expect(carried.text == "10:00 45m")
        #expect(carried.caret == 4)      // after the colon, as before
    }

    @Test("Caret in empty space — the time is edited")
    func fallsBackToTime() throws {
        // A caret in the trailing space is not on any fragment.
        let edit = try #require(adjust("14:00 45m c2 ", caret: 13, by: 1))
        #expect(edit.segment == .minute)
        #expect(edit.text == "14:15 45m c2 ")   // the rest, trailing space included, is untouched
    }

    // MARK: - Completion with ⇥

    @Test("Splitting into parts fills in no defaults")
    func draft() {
        let bare = QueryEdit.draft("14:00", today: today)
        #expect(bare.hasTime)
        #expect(!bare.hasDuration)      // parse would fill in 30m, but nobody typed it
        #expect(!bare.hasSpace)
        #expect(!bare.hasDay)

        let full = QueryEdit.draft("пт 14:00 45m meeting 1", today: today)
        #expect(full.hasDay && full.hasTime && full.hasDuration && full.hasSpace)
    }

    @Test("“now” counts as a time too", arguments: ["сейчас", "now", "sad"])
    func nowCountsAsTime(word: String) {
        #expect(QueryEdit.draft(word, today: today).hasTime)
    }

    @Test("The next part: duration first, then the space")
    func suggestionOrder() {
        let free = ["C4", "O1"].compactMap(Space.named)
        #expect(suggestion(after: "now", spaces: free) == "30m")
        #expect(suggestion(after: "now 30m", spaces: free) == "C4")
        #expect(suggestion(after: "now 30m C4", spaces: free) == nil)
    }

    @Test("The suggested space is a free one, not just the first")
    func suggestsFreeSpace() {
        let free = ["MR1"].compactMap(Space.named)
        #expect(suggestion(after: "14:00 45m", spaces: free) == "MR1")
        #expect(suggestion(after: "14:00 45m", spaces: []) == nil)
    }

    @Test("A named day is continued with an hour, the way “now” is with a duration",
          arguments: ["today", "tomorrow", "завтра", "sutra", "wed", "пт", "23/09"])
    func suggestionAfterDayWord(text: String) {
        // The hour offered is the one an empty field offers: the nearest slot
        // no earlier than now.
        #expect(suggestion(after: text, spaces: Space.all) == "11:15")
    }

    @Test("Once the working day is over the offered hour is next morning’s")
    func suggestionAfterHours() {
        #expect(QueryEdit.suggestion(after: "tomorrow", today: today,
                                     now: TimeOfDay(hour: 21), spaces: Space.all) == "8:00")
    }

    @Test("A day and an hour are then continued as any other request is")
    func suggestionAfterDayAndTime() {
        #expect(suggestion(after: "tomorrow 11:15", spaces: Space.all) == "30m")
        #expect(suggestion(after: "tomorrow 11:15 30m", spaces: Space.all) == "C1")
    }

    @Test("Neither a time nor a day — nothing to suggest",
          arguments: ["", "meeting room", "c2", "45m"])
    func noSuggestionWithoutAnything(text: String) {
        #expect(suggestion(after: text, spaces: Space.all) == nil)
    }

    @Test("A day in the request does not throw the suggestion off")
    func suggestionAfterDay() {
        #expect(suggestion(after: "пт 14:00", spaces: Space.all) == "30m")
    }

    @Test("Nothing to edit — the arrow does nothing")
    func nothingToAdjust() {
        #expect(adjust("", caret: 0, by: 1) == nil)
        #expect(adjust("meeting room", caret: 3, by: 1) == nil)
    }

    @Test("An edit preserves the rest of the line")
    func leavesTheRestAlone() throws {
        let edit = try #require(adjust("пт 14:00 45m meeting 1", caret: 4, by: 1))
        #expect(edit.text == "пт 15:00 45m meeting 1")
    }
}
