import Foundation

/// A “when and for how long” request, parsed from the overlay’s input line.
public struct Query: Hashable, Sendable {
    public let date: CalendarDate
    public let start: TimeOfDay
    public let minutes: Int
    /// The space, when a person named one: `14:00 45m C2`.
    public let spaceID: String?

    public init(date: CalendarDate, start: TimeOfDay, minutes: Int, spaceID: String? = nil) {
        self.date = date
        self.start = start
        self.minutes = minutes
        self.spaceID = spaceID
    }

    /// The same request without the named space — used to show what else is
    /// free when the named one is taken.
    public var anySpace: Query {
        Query(date: date, start: start, minutes: minutes, spaceID: nil)
    }

    /// How many grid slots the request covers. A partial slot counts as whole.
    public var slotCount: Int {
        max(1, (minutes + SheetGrid.slotMinutes - 1) / SheetGrid.slotMinutes)
    }

    public var end: TimeOfDay {
        start.adding(minutes: slotCount * SheetGrid.slotMinutes)
    }

    /// The start shifted along the grid: `-1` one slot earlier, `+1` one later.
    ///
    /// `nil` at the edges of the day — an arrow at the edge does nothing rather
    /// than wrapping around to the other end. A time off the grid first snaps
    /// onto it in the direction of travel: `14:07` upwards is `14:00`.
    public func shifted(bySlots slots: Int) -> Query? {
        let index: Int
        if let aligned = SheetGrid.slotIndex(of: start) {
            index = aligned + slots
        } else if slots > 0, let next = SheetGrid.slotIndex(atOrAfter: start) {
            index = next
        } else if slots < 0, let previous = SheetGrid.slotIndex(atOrBefore: start) {
            index = previous
        } else {
            return nil
        }

        guard SheetGrid.slots.indices.contains(index) else { return nil }
        return Query(date: date, start: SheetGrid.slots[index], minutes: minutes, spaceID: spaceID)
    }
}

/// Parses the input line: `14:00 45m`, `now 30m`, `16:30 2h C2`, `fri 14:00`,
/// `23/09 14:00 45m meeting 1`.
///
/// The function is pure: “today” and “now” arrive as parameters rather than
/// from the clock.
public enum QueryParser {
    /// Duration used when the request does not name one.
    public static let defaultMinutes = 30

    /// `nil` when the input carries no start time. Everything else is optional:
    /// the day defaults to today, the space to any.
    public static func parse(_ text: String, today: CalendarDate, now: TimeOfDay) -> Query? {
        var date: CalendarDate?
        var start: TimeOfDay?
        var minutes: Int?
        var spaceID: String?

        let tokens = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        var index = tokens.startIndex

        while index < tokens.endIndex {
            let token = tokens[index]

            // A two-word name: “meeting 1”.
            if spaceID == nil, tokens.index(after: index) < tokens.endIndex,
               let matched = matchSpace(normalized(token) + normalized(tokens[tokens.index(after: index)])) {
                spaceID = matched
                index = tokens.index(index, offsetBy: 2)
                continue
            }
            // The day is matched on the raw token, before Cyrillic look-alikes
            // are folded: otherwise Russian “ср” would turn into “cr” and stop
            // being Wednesday.
            if date == nil, let parsed = parseDay(token, today: today) {
                date = parsed
                index = tokens.index(after: index)
                continue
            }
            if start == nil, isNowWord(token) {
                guard let slot = SheetGrid.slotIndex(atOrAfter: now) else { return nil }
                start = SheetGrid.slots[slot]
                index = tokens.index(after: index)
                continue
            }
            // `1h 30m` — hours and minutes as two tokens. Checked before the
            // single-token duration: that one would take the `1h` and leave
            // the `30m` to be read as something else, silently losing half an
            // hour of the request.
            if minutes == nil, tokens.index(after: index) < tokens.endIndex,
               let parsed = parseDuration(token, tokens[tokens.index(after: index)]) {
                minutes = parsed
                index = tokens.index(index, offsetBy: 2)
                continue
            }
            if minutes == nil, let parsed = parseDuration(token) {
                minutes = parsed
                index = tokens.index(after: index)
                continue
            }
            if start == nil, let parsed = parseTime(token) {
                start = parsed
                index = tokens.index(after: index)
                continue
            }
            if spaceID == nil, let matched = matchSpace(normalized(token)) {
                spaceID = matched
            }
            index = tokens.index(after: index)
        }

        guard let start else { return nil }
        return Query(date: date ?? today, start: start, minutes: minutes ?? defaultMinutes, spaceID: spaceID)
    }

    /// A request back into text, in the canonical form `parse` reads back as
    /// the same request. The arrows need it: they edit the input line in place,
    /// and what stands there afterwards has to match what is shown below.
    public static func text(for query: Query, today: CalendarDate) -> String {
        var parts: [String] = []
        if query.date != today {
            parts.append(query.date.description)
        }
        parts.append(query.start.description)
        parts.append(durationText(minutes: query.minutes))
        if let spaceID = query.spaceID {
            parts.append(spaceID)
        }
        return parts.joined(separator: " ")
    }

    /// The hint for an empty input line, in the canonical form `parse` reads
    /// back as the same request — ⇥ inserts it verbatim.
    ///
    /// The time is the nearest slot no earlier than `now`, not a hard-coded
    /// “14:00”: at 15:40 such a hint offered the past.
    ///
    /// **Once the grid’s day is over the hint carries a day of its own.** A
    /// bare time is bound to today, because `parse` has nothing else to bind
    /// it to, so at 20:48 “8:00” is this morning — twelve hours gone, and ⏎
    /// on it opens a range that no longer exists. The day is the sheet’s next
    /// one rather than `today + 1`, for the reason the dated example gives:
    /// on a Friday evening tomorrow is a Saturday the sheet does not hold.
    /// With no sheet loaded to ask, tomorrow is still the better guess — a day
    /// the sheet lacks is answered plainly, a request into the past is not.
    public static func hint(
        today: CalendarDate,
        now: TimeOfDay,
        dates: [CalendarDate],
        language: QueryLanguage
    ) -> String {
        let start = SheetGrid.suggestedStart(after: now)
        let duration = durationText(minutes: hintMinutes)
        guard SheetGrid.slotIndex(atOrAfter: now) == nil else {
            return "\(start) \(duration)"
        }
        let date = dates.first { $0 > today } ?? today.adding(days: 1)
        return "\(dayText(for: date, today: today, language: language)) \(start) \(duration)"
    }

    /// The duration the hint offers. Not `defaultMinutes`: that one is what a
    /// request without a duration *means*, while this is what a person is
    /// being offered to ask for, and three quarters of an hour is the
    /// commoner meeting.
    static let hintMinutes = 45

    /// A day for the input line: a word while words are honest, `dd/mm` past
    /// that. Both forms `parse` reads back.
    static func dayText(for date: CalendarDate, today: CalendarDate, language: QueryLanguage) -> String {
        dayWord(for: date, today: today, language: language)
            ?? String(format: "%02d/%02d", date.day, date.month)
    }

    /// A duration in the canonical form `parse` reads back as the same number
    /// of minutes: `45m`, `1h`, `1h 30m`.
    ///
    /// Past an hour bare minutes stop being legible — `150m` is two and a half
    /// hours, and nobody works that out in their head while looking for a room.
    public static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    static func isNowWord(_ token: Substring) -> Bool {
        QueryVocabulary.all.contains { $0.now.contains(String(token)) }
    }

    /// `today`, `завтра`, `sutra`, `fri`, `пт`, `pet`, `23/09`, `23/09/2026`.
    static func parseDay(_ token: Substring, today: CalendarDate) -> CalendarDate? {
        let word = String(token)
        for vocabulary in QueryVocabulary.all {
            switch word {
            case vocabulary.today:
                return today
            case vocabulary.tomorrow:
                return today.adding(days: 1)
            case vocabulary.dayAfterTomorrow:
                return today.adding(days: 2)
            default:
                continue
            }
        }
        if let weekday = weekdays[word] {
            return today.next(weekday: weekday)
        }
        return parseDate(token, today: today)
    }

    /// Which language the day was typed in — so an arrow gives it back in the same one.
    static func language(ofDayWord token: String) -> QueryLanguage? {
        QueryVocabulary.all.first { vocabulary in
            vocabulary.dayWords.contains(token)
                || vocabulary.shortWeekdays.contains(token)
                || vocabulary.fullWeekdays.contains(token)
                || vocabulary.plainShortWeekdays.contains(token)
                || vocabulary.plainFullWeekdays.contains(token)
        }?.language
    }

    /// How to name a day in that language: “today”, “tomorrow” or a weekday.
    /// `nil` when words cannot express it — beyond the coming week they lie.
    public static func dayWord(for date: CalendarDate, today: CalendarDate, language: QueryLanguage) -> String? {
        guard let vocabulary = QueryVocabulary.all.first(where: { $0.language == language }) else { return nil }
        switch date.daysSinceEpoch - today.daysSinceEpoch {
        case 0: return vocabulary.today
        case 1: return vocabulary.tomorrow
        case 2...6: return vocabulary.shortWeekdays[date.weekdayIndex]
        default: return nil
        }
    }

    /// A date in the sheet’s format: `23/09` or `23/09/2026`. Slashes only —
    /// `23.09` is indistinguishable from the time `23:09`.
    static func parseDate(_ token: Substring, today: CalendarDate) -> CalendarDate? {
        let parts = token.split(separator: "/")
        guard (2...3).contains(parts.count),
              let day = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }

        if parts.count == 3 {
            guard let year = Int(parts[2]) else { return nil }
            let resolvedYear = year < 100 ? 2000 + year : year
            guard CalendarDate.isValid(year: resolvedYear, month: month, day: day) else { return nil }
            return CalendarDate(year: resolvedYear, month: month, day: day)
        }
        // Without a year, take the current one. A day just past stays past: the
        // sheet’s period starts a few days before today, so “18/09” typed on the
        // 21st is its first date, not next September. A distant past, on the
        // other hand, means the year ahead: “05/01” in September is January.
        guard CalendarDate.isValid(year: today.year, month: month, day: day) else { return nil }
        let thisYear = CalendarDate(year: today.year, month: month, day: day)
        let daysBehind = today.daysSinceEpoch - thisYear.daysSinceEpoch
        guard daysBehind > recentPastDays else { return thisYear }

        let nextYear = today.year + 1
        guard CalendarDate.isValid(year: nextYear, month: month, day: day) else { return nil }
        return CalendarDate(year: nextYear, month: month, day: day)
    }

    /// How far back a date still counts as “this year”. The sheet spans two
    /// weeks, so the allowance is generous on purpose.
    static let recentPastDays = 60

    /// Word to weekday, 0 is Sunday, as in `CalendarDate.weekdayIndex`.
    /// Assembled from the vocabularies of every language at once.
    static let weekdays: [String: Int] = {
        var result: [String: Int] = [:]
        for vocabulary in QueryVocabulary.all {
            for words in [vocabulary.shortWeekdays, vocabulary.fullWeekdays,
                          vocabulary.plainShortWeekdays, vocabulary.plainFullWeekdays] {
                for (index, word) in words.enumerated() {
                    result[word] = index
                }
            }
        }
        return result
    }()

    /// Key to `Space.id`: both the short name (`c2`, `mr1`) and the title with
    /// spaces removed (`meeting1`).
    private static let spaceKeys: [String: String] = {
        var keys: [String: String] = [:]
        for space in Space.all {
            keys[space.id.lowercased()] = space.id
            keys[space.title.lowercased().replacingOccurrences(of: " ", with: "")] = space.id
        }
        return keys
    }()

    static func matchSpace(_ key: String) -> String? {
        spaceKeys[key]
    }

    /// Cyrillic look-alikes of Latin letters: on a Russian keyboard layout `C2`
    /// comes out as `С2`, and it is the same booth.
    private static let homoglyphs: [Character: Character] = [
        "с": "c", "о": "o", "м": "m", "р": "r", "е": "e", "а": "a", "т": "t", "к": "k",
    ]

    static func normalized(_ token: Substring) -> String {
        String(token.map { homoglyphs[$0] ?? $0 })
    }

    /// `14:00`, `14.00`, `14`, `9:30`.
    static func parseTime(_ token: Substring) -> TimeOfDay? {
        let parts = token.split(whereSeparator: { $0 == ":" || $0 == "." })
        guard let first = parts.first, let hour = Int(first), (0..<24).contains(hour) else { return nil }
        switch parts.count {
        case 1:
            return TimeOfDay(hour: hour)
        case 2:
            guard let minute = Int(parts[1]), (0..<60).contains(minute) else { return nil }
            return TimeOfDay(hour: hour, minute: minute)
        default:
            return nil
        }
    }

    /// Which unit a duration was written in. The hour-and-minutes form is that
    /// pair and only in that order, so the unit has to travel with the number.
    enum DurationUnit {
        case minutes, hours
    }

    /// `45m`, `45м`, `30мин`, `2h`, `2ч`, `1.5h`, and hours with the minutes
    /// stuck to them: `1h30m`.
    static func parseDuration(_ token: Substring) -> Int? {
        guard let first = durationGroup(token) else { return nil }
        guard !first.rest.isEmpty else { return first.minutes }
        // A tail is allowed only after hours and only as minutes: `1h30m` is a
        // duration, `30m1h` and `45mm` are typos and stay unparsed.
        guard first.unit == .hours,
              let second = durationGroup(first.rest),
              second.rest.isEmpty, second.unit == .minutes
        else { return nil }
        return combinedDuration(first.minutes, second.minutes)
    }

    /// The same duration written as two tokens: `1h 30m`, `1ч 30м`.
    ///
    /// Hours first, minutes second — the only order anyone writes — and both
    /// units required: `14:00 45m` must not swallow the space that follows it,
    /// and `1h 2h` is not a duration at all.
    static func parseDuration(_ first: Substring, _ second: Substring) -> Int? {
        guard let hours = durationGroup(first), hours.rest.isEmpty, hours.unit == .hours,
              let minutes = durationGroup(second), minutes.rest.isEmpty, minutes.unit == .minutes
        else { return nil }
        return combinedDuration(hours.minutes, minutes.minutes)
    }

    /// One number with its unit, plus whatever is left of the token.
    private static func durationGroup(
        _ token: Substring
    ) -> (minutes: Int, unit: DurationUnit, rest: Substring)? {
        let digits = token.prefix { $0.isNumber || $0 == "." || $0 == "," }
        let tail = token.dropFirst(digits.count)
        guard !digits.isEmpty, !tail.isEmpty,
              let amount = Double(digits.replacingOccurrences(of: ",", with: ".")),
              amount.isFinite, amount >= 0
        else { return nil }

        for unit in minuteUnits where tail.hasPrefix(unit) {
            guard let minutes = safeMinutes(amount) else { return nil }
            return (minutes, .minutes, tail.dropFirst(unit.count))
        }
        for unit in hourUnits where tail.hasPrefix(unit) {
            guard let minutes = safeMinutes(amount * 60) else { return nil }
            return (minutes, .hours, tail.dropFirst(unit.count))
        }
        return nil
    }

    private static func safeMinutes(_ value: Double) -> Int? {
        let rounded = value.rounded()
        guard rounded.isFinite, rounded <= Double(maxDurationMinutes) else { return nil }
        return Int(exactly: rounded)
    }

    private static func combinedDuration(_ first: Int, _ second: Int) -> Int? {
        let (total, overflow) = first.addingReportingOverflow(second)
        return !overflow && total <= maxDurationMinutes ? total : nil
    }

    private static let maxDurationMinutes = 24 * 60

    /// Longest first, both lists: the unit is matched as a prefix, so `м`
    /// checked before `мин` would leave `ут` dangling off `30минут`.
    private static let minuteUnits = ["минуты", "минут", "мин", "min", "m", "м"]
    private static let hourUnits = ["hours", "hour", "часов", "часа", "час", "hr", "h", "ч"]
}
