import Testing
@testable import NookCore

@Suite("Query parsing")
struct QueryParserTests {
    let today = CalendarDate(year: 2026, month: 9, day: 21)
    let now = TimeOfDay(hour: 11, minute: 7)

    private func parse(_ text: String) -> Query? {
        QueryParser.parse(text, today: today, now: now)
    }

    @Test("Time and duration")
    func timeAndDuration() throws {
        let query = try #require(parse("14:00 45m"))
        #expect(query.start == TimeOfDay(hour: 14))
        #expect(query.minutes == 45)
        #expect(query.slotCount == 3)
        #expect(query.end == TimeOfDay(hour: 14, minute: 45))
    }

    @Test("Russian units and hours", arguments: [
        ("16:30 2h", TimeOfDay(hour: 16, minute: 30), 120),
        ("16:30 2ч", TimeOfDay(hour: 16, minute: 30), 120),
        ("9:15 30мин", TimeOfDay(hour: 9, minute: 15), 30),
        ("9 1.5h", TimeOfDay(hour: 9), 90),
    ])
    func units(text: String, start: TimeOfDay, minutes: Int) throws {
        let query = try #require(parse(text))
        #expect(query.start == start)
        #expect(query.minutes == minutes)
    }

    @Test("An hour with minutes, in either script and either spelling", arguments: [
        ("14:00 1h 30m", 90),
        ("14:00 1h30m", 90),
        ("14:00 1ч 30м", 90),
        ("14:00 2h 15m", 135),
        ("14:00 1 h 30 m", 30),      // a space after the number is not a duration
    ])
    func hoursWithMinutes(text: String, minutes: Int) throws {
        #expect(try #require(parse(text)).minutes == minutes)
    }

    @Test("Only hours then minutes: anything else is not one duration", arguments: [
        ("14:00 30m 1h", 30),        // the first duration wins, as before
        ("14:00 1h 2h", 60),
        ("14:00 45mm", 30),          // unparsed, so the default stands
    ])
    func rejectsOtherPairs(text: String, minutes: Int) throws {
        #expect(try #require(parse(text)).minutes == minutes)
    }

    @Test("An hour with minutes does not eat the space that follows")
    func compoundLeavesSpaceAlone() throws {
        let query = try #require(parse("14:00 1h 30m c2"))
        #expect(query.minutes == 90)
        #expect(query.spaceID == "C2")
    }

    @Test("A duration is written back as hours and minutes", arguments: [
        (45, "45m"), (60, "1h"), (90, "1h 30m"), (135, "2h 15m"), (15, "15m"),
    ])
    func durationText(minutes: Int, text: String) {
        #expect(QueryParser.durationText(minutes: minutes) == text)
    }

    @Test("“now” rounds up to a slot boundary")
    func nowRoundsUp() throws {
        let query = try #require(parse("сейчас 30м"))
        #expect(query.start == TimeOfDay(hour: 11, minute: 15))
    }

    @Test("Without a duration it is half an hour by default")
    func defaultDuration() throws {
        let query = try #require(parse("14:00"))
        #expect(query.minutes == QueryParser.defaultMinutes)
    }

    @Test("A partial slot takes the whole slot")
    func partialSlot() throws {
        let query = try #require(parse("14:00 20m"))
        #expect(query.slotCount == 2)
    }

    @Test("Without a start time there is no request", arguments: ["", "45m", "meeting room"])
    func noStart(text: String) {
        #expect(parse(text) == nil)
    }

    @Test("A space in the request", arguments: [
        ("14:00 10m C2", "C2"),
        ("14:00 c2", "C2"),
        ("сейчас 30м o1", "O1"),
        ("14:00 mr1", "MR1"),
        ("14 meeting 1", "MR1"),
        ("16:30 2h Meeting 2", "MR2"),
    ])
    func namesSpace(text: String, id: String) throws {
        #expect(try #require(parse(text)).spaceID == id)
    }

    @Test("Serbian is understood in both scripts", arguments: [
        ("14:00 pet", CalendarDate(year: 2026, month: 9, day: 25)),
        ("14:00 пет", CalendarDate(year: 2026, month: 9, day: 25)),
        ("14:00 sre", CalendarDate(year: 2026, month: 9, day: 23)),
        ("14:00 сре", CalendarDate(year: 2026, month: 9, day: 23)),
        ("14:00 sutra", CalendarDate(year: 2026, month: 9, day: 22)),
        ("14:00 сутра", CalendarDate(year: 2026, month: 9, day: 22)),
    ])
    func serbianInBothScripts(text: String, expected: CalendarDate) throws {
        #expect(try #require(parse(text)).date == expected)
    }

    @Test("Serbian “now” in both scripts", arguments: ["sad 30m", "сад 30m", "sada 30m", "сада 30m"])
    func serbianNow(text: String) throws {
        #expect(try #require(parse(text)).start == TimeOfDay(hour: 11, minute: 15))
    }

    @Test("Cyrillic from a Russian layout names the same space", arguments: ["14:00 с2", "14:00 о1", "14:00 мр1"])
    func cyrillicHomoglyphs(text: String) throws {
        #expect(try #require(parse(text)).spaceID != nil)
    }

    @Test("No space named, none assumed")
    func noSpace() throws {
        #expect(try #require(parse("14:00 45m")).spaceID == nil)
        #expect(try #require(parse("14:00 45m kitchen")).spaceID == nil)
    }

    @Test("Time and duration are not confused with a space name")
    func spaceDoesNotEatTime() throws {
        let query = try #require(parse("c1 16:30 2h"))
        #expect(query.spaceID == "C1")
        #expect(query.start == TimeOfDay(hour: 16, minute: 30))
        #expect(query.minutes == 120)
    }

    // The tests are anchored to Monday, 21 September 2026.

    @Test("A weekday means the nearest one ahead", arguments: [
        ("14:00 fri", CalendarDate(year: 2026, month: 9, day: 25)),
        ("14:00 пт", CalendarDate(year: 2026, month: 9, day: 25)),
        ("14:00 tue", CalendarDate(year: 2026, month: 9, day: 22)),
        ("14:00 ср", CalendarDate(year: 2026, month: 9, day: 23)),
        ("14:00 thursday", CalendarDate(year: 2026, month: 9, day: 24)),
    ])
    func weekdayAhead(text: String, expected: CalendarDate) throws {
        #expect(try #require(parse(text)).date == expected)
    }

    @Test("Today’s weekday means today, not a week out")
    func weekdayToday() throws {
        #expect(try #require(parse("14:00 mon")).date == today)
        #expect(try #require(parse("14:00 пн")).date == today)
    }

    @Test("Words for the day", arguments: [
        ("14:00 сегодня", 0),
        ("14:00 завтра", 1),
        ("14:00 tomorrow", 1),
        ("14:00 послезавтра", 2),
    ])
    func dayWords(text: String, shift: Int) throws {
        #expect(try #require(parse(text)).date == today.adding(days: shift))
    }

    @Test("A date in the sheet’s format")
    func explicitDate() throws {
        #expect(try #require(parse("23/09 14:00")).date == CalendarDate(year: 2026, month: 9, day: 23))
        #expect(try #require(parse("01/10/2026 14:00")).date == CalendarDate(year: 2026, month: 10, day: 1))
    }

    @Test("Impossible dates stay unparsed", arguments: ["31/02/2026", "29/02/2026", "31/04"])
    func impossibleDate(text: String) throws {
        #expect(try #require(parse("\(text) 14:00")).date == today)
    }

    @Test("An excessive duration stays unparsed instead of trapping")
    func excessiveDuration() throws {
        let query = try #require(parse("14:00 999999999999999999999999999999999h"))
        #expect(query.minutes == QueryParser.defaultMinutes)
    }

    @Test("A date without a year, long past, means next year")
    func dateRollsOver() throws {
        #expect(try #require(parse("05/01 14:00")).date == CalendarDate(year: 2027, month: 1, day: 5))
    }

    @Test("A leap day is not rolled into a non-leap year")
    func leapDayDoesNotBecomeInvalid() throws {
        let leapYearToday = CalendarDate(year: 2024, month: 9, day: 21)
        let query = try #require(QueryParser.parse(
            "29/02 14:00",
            today: leapYearToday,
            now: now
        ))

        #expect(query.date == leapYearToday)
    }

    @Test("A recently passed day stays in this year")
    func recentPastStaysThisYear() throws {
        // 18/09 is the first date of the sheet’s period and today is the 21st.
        // A year later it would be a different day.
        #expect(try #require(parse("18/09 14:00")).date == CalendarDate(year: 2026, month: 9, day: 18))
    }

    @Test("No day named means today")
    func defaultsToToday() throws {
        #expect(try #require(parse("14:00 45m C2")).date == today)
    }

    @Test("Day, time, duration and space on one line")
    func everythingAtOnce() throws {
        let query = try #require(parse("пт 14:00 45m meeting 1"))
        #expect(query.date == CalendarDate(year: 2026, month: 9, day: 25))
        #expect(query.start == TimeOfDay(hour: 14))
        #expect(query.minutes == 45)
        #expect(query.spaceID == "MR1")
    }

    @Test("Shifting by one slot along the grid")
    func shiftBySlot() throws {
        let query = try #require(parse("14:00 45m c2"))
        let later = try #require(query.shifted(bySlots: 1))
        let earlier = try #require(query.shifted(bySlots: -1))

        #expect(later.start == TimeOfDay(hour: 14, minute: 15))
        #expect(earlier.start == TimeOfDay(hour: 13, minute: 45))
        // The shift leaves everything else alone.
        #expect(later.minutes == 45)
        #expect(later.spaceID == "C2")
        #expect(later.date == query.date)
    }

    @Test("At the edges of the day the shift stops rather than wraps")
    func shiftStopsAtDayEdges() throws {
        let first = try #require(parse("8:00 30m"))
        #expect(first.shifted(bySlots: -1) == nil)
        #expect(first.shifted(bySlots: 1)?.start == TimeOfDay(hour: 8, minute: 15))

        let last = try #require(parse("20:00 30m"))
        #expect(last.shifted(bySlots: 1) == nil)
        #expect(last.shifted(bySlots: -1)?.start == TimeOfDay(hour: 19, minute: 45))
    }

    @Test("A time off the slot boundary snaps onto the grid first")
    func shiftSnapsOffGridTime() throws {
        let query = try #require(parse("14:07 30m"))
        #expect(query.shifted(bySlots: -1)?.start == TimeOfDay(hour: 14))
        #expect(query.shifted(bySlots: 1)?.start == TimeOfDay(hour: 14, minute: 15))
    }

    @Test("A request survives the round trip through text", arguments: [
        "14:00 45m", "9:30 30m c2", "пт 14:00 45m meeting 1", "23/09 11:00 60m o1",
        "14:00 1h 30m", "14:00 1ч 30м c2", "9:15 2h",
    ])
    func roundTrip(text: String) throws {
        let query = try #require(parse(text))
        let rendered = QueryParser.text(for: query, today: today)
        #expect(parse(rendered) == query)
    }

    @Test("Today is not written into the text, another day is")
    func rendersDateOnlyWhenNeeded() throws {
        let todayQuery = try #require(parse("14:00 45m c2"))
        #expect(QueryParser.text(for: todayQuery, today: today) == "14:00 45m C2")

        let friday = try #require(parse("пт 9:15 1h"))
        #expect(QueryParser.text(for: friday, today: today) == "25/09/2026 9:15 1h")
    }

    @Test("A date does not swallow the time: 23/09 is not 23:09")
    func dateDoesNotEatTime() throws {
        let query = try #require(parse("23/09 09:30"))
        #expect(query.date == CalendarDate(year: 2026, month: 9, day: 23))
        #expect(query.start == TimeOfDay(hour: 9, minute: 30))
    }
}

@Suite("The hint in an empty field")
struct QueryHintTests {
    /// Monday, so that “the sheet’s next day” and `today + 1` differ only when
    /// the sheet says so — and a Friday can be asked for separately.
    let today = CalendarDate(year: 2026, month: 9, day: 21)

    private func hint(at now: TimeOfDay, dates: [CalendarDate] = [], language: QueryLanguage = .en) -> String {
        QueryParser.hint(today: today, now: now, dates: dates, language: language)
    }

    @Test("Within the day the hint is the next slot, with no day in it")
    func withinTheDay() {
        #expect(hint(at: TimeOfDay(hour: 15, minute: 40)) == "15:45 45m")
    }

    @Test("A hint within the day means today")
    func withinTheDayMeansToday() throws {
        let text = hint(at: TimeOfDay(hour: 15, minute: 40))
        let query = try #require(QueryParser.parse(text, today: today, now: TimeOfDay(hour: 15, minute: 40)))
        #expect(query.date == today)
        #expect(query.start == TimeOfDay(hour: 15, minute: 45))
    }

    /// The defect this pair exists for: a bare `8:00` offered at 20:48 parses
    /// as this morning, and ⏎ on it opens a range that is over.
    @Test("Once the day is over the hint carries a day")
    func pastTheEndOfTheDay() {
        #expect(hint(at: TimeOfDay(hour: 20, minute: 48)) == "tomorrow 8:00 45m")
    }

    @Test("The hint never means a time already gone", arguments: [
        TimeOfDay(hour: 20, minute: 48), TimeOfDay(hour: 23, minute: 59),
    ])
    func neverPast(now: TimeOfDay) throws {
        let text = hint(at: now)
        let query = try #require(QueryParser.parse(text, today: today, now: now))
        #expect(query.date > today)
    }

    /// Friday evening: tomorrow is a Saturday the sheet does not hold, so the
    /// hint has to take the sheet’s own next day instead.
    @Test("The day comes from the sheet, not from today + 1")
    func takesTheSheetsNextDay() {
        let friday = CalendarDate(year: 2026, month: 9, day: 25)
        let monday = CalendarDate(year: 2026, month: 9, day: 28)
        let text = QueryParser.hint(
            today: friday,
            now: TimeOfDay(hour: 20, minute: 48),
            dates: [friday, monday],
            language: .en
        )
        #expect(text == "mon 8:00 45m")
    }

    @Test("The day is named in the language the app is speaking", arguments: [
        (QueryLanguage.ru, "завтра 8:00 45m"),
        (QueryLanguage.srLatin, "sutra 8:00 45m"),
    ])
    func speaksTheInterfaceLanguage(language: QueryLanguage, expected: String) {
        #expect(hint(at: TimeOfDay(hour: 21), language: language) == expected)
    }

    @Test("A day words cannot name is written as a date", arguments: [
        QueryLanguage.en, .ru,
    ])
    func fallsBackToADate(language: QueryLanguage) {
        let faraway = today.adding(days: 9)
        let text = QueryParser.hint(
            today: today,
            now: TimeOfDay(hour: 21),
            dates: [faraway],
            language: language
        )
        #expect(text == "30/09 8:00 45m")
    }

    @Test("Whatever the hint says, parse reads it back", arguments: [
        TimeOfDay(hour: 8), TimeOfDay(hour: 15, minute: 40), TimeOfDay(hour: 20, minute: 48),
    ])
    func alwaysParses(now: TimeOfDay) throws {
        for language in QueryLanguage.allCases {
            let text = QueryParser.hint(today: today, now: now, dates: [], language: language)
            #expect(QueryParser.parse(text, today: today, now: now) != nil, "\(language): \(text)")
        }
    }

    @Test("The interface language is read off the localisations", arguments: [
        (["ru-RU", "en"], QueryLanguage.ru),
        (["sr-Latn-RS"], .srLatin),
        (["sr-RS"], .srCyrillic),
        (["en-GB"], .en),
        (["de-DE"], .en),
        ([], .en),
    ])
    func interfaceLanguage(localizations: [String], expected: QueryLanguage) {
        #expect(QueryLanguage.interface(localizations) == expected)
    }
}
