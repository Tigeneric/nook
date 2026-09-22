import Foundation

/// Editing a request with the arrow keys.
///
/// An arrow changes **the fragment the caret sits on**: on the hour it moves
/// the hour, on the minutes the minutes, on the duration the duration, on the
/// day the day, on the space the space. The rest of the line is left alone and
/// the caret stays in its fragment — exactly one token is rewritten, not the
/// whole string.
public enum QueryEdit {
    public enum Segment: String, Sendable, Equatable {
        case day, hour, minute, duration, space
    }

    public struct Edit: Equatable, Sendable {
        public let text: String
        /// Caret position in UTF-16 units, the way `NSTextView` counts it.
        public let caret: Int
        public let segment: Segment
    }

    /// `delta` is +1 (more, later, next) or −1 (less, earlier, previous). In
    /// the interface ↑ maps to +1, like a stepper.
    ///
    /// `spaces` is the ring the space cycles through: pass the ones free for
    /// this request so the arrow does not walk over taken rooms. This module
    /// does no I/O and knows nothing of schedules, so the list comes in from
    /// the outside.
    ///
    /// `dates` bounds day stepping to the dates the sheet actually holds.
    ///
    /// `nil` when there is nothing to edit, or the edit runs into an edge.
    public static func adjust(
        _ text: String,
        caret: Int,
        by delta: Int,
        today: CalendarDate,
        spaces: [Space] = Space.all,
        dates: [CalendarDate] = []
    ) -> Edit? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }

        // Under the caret is either the token it stands inside, or the one it
        // is stuck to the edge of. If neither (the caret is in whitespace or on
        // an unrecognised word), the time is edited: it is the main quantity.
        let underCaret = tokens.firstIndex { caret >= $0.start && caret <= $0.end }
        let target = underCaret.flatMap { classify(tokens, at: $0, caret: caret, today: today) }
            ?? fallback(tokens)
        guard let target else { return nil }

        guard let replacement = replacement(for: target, by: delta, today: today,
                                            spaces: spaces, dates: dates) else { return nil }

        let lower = String.Index(utf16Offset: target.start, in: text)
        let upper = String.Index(utf16Offset: target.end, in: text)
        return Edit(
            text: text.replacingCharacters(in: lower..<upper, with: replacement),
            caret: target.start + min(caretOffset(in: target, caret: caret, replacement: replacement),
                                      replacement.utf16.count),
            segment: target.segment
        )
    }

    // MARK: - What the request is still missing

    /// Which parts of the request have been typed.
    public struct Draft: Equatable, Sendable {
        public let hasDay: Bool
        public let hasTime: Bool
        public let hasDuration: Bool
        public let hasSpace: Bool
    }

    /// Splits the line into parts without filling in defaults: `parse` would
    /// report a half-hour duration and today’s date even when neither was
    /// typed, and a suggestion needs to know what a person has not said yet.
    public static func draft(_ text: String, today: CalendarDate) -> Draft {
        let tokens = tokenize(text)
        var day = false, time = false, duration = false, space = false
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            if !space, index + 1 < tokens.count,
               QueryParser.matchSpace(normalized(token.text) + normalized(tokens[index + 1].text)) != nil {
                space = true
                index += 2
                continue
            }
            if !day, QueryParser.parseDay(Substring(token.text), today: today) != nil {
                day = true
            } else if !duration, QueryParser.parseDuration(Substring(token.text)) != nil {
                duration = true
            } else if !time, QueryParser.parseTime(Substring(token.text)) != nil {
                time = true
            } else if !time, QueryParser.isNowWord(Substring(token.text)) {
                time = true
            } else if !space, QueryParser.matchSpace(normalized(token.text)) != nil {
                space = true
            }
            index += 1
        }
        return Draft(hasDay: day, hasTime: time, hasDuration: duration, hasSpace: space)
    }

    /// What to continue the request with: the time when only a day has been
    /// named, then the duration, then the space. `nil` when there is nothing
    /// left to add, or when nothing has been typed that a continuation could
    /// attach to.
    ///
    /// A named day is a beginning of a request just as `now` is: `tomorrow`
    /// gets the same treatment — the hint shows the hour it would take, and ⇥
    /// enters it. Without that, a day alone was a dead end: no hint, and the
    /// key did nothing.
    ///
    /// `spaces` are the ones free for what has been typed so far: suggesting a
    /// taken room would be suggesting a knowingly bad option.
    public static func suggestion(
        after text: String,
        today: CalendarDate,
        now: TimeOfDay,
        spaces: [Space]
    ) -> String? {
        let draft = draft(text, today: today)
        guard draft.hasTime else {
            // A day on its own is continued with an hour. A space or a stray
            // word is not a beginning: there is no telling what to add to it.
            return draft.hasDay ? SheetGrid.suggestedStart(after: now).description : nil
        }
        if !draft.hasDuration { return "\(QueryParser.defaultMinutes)m" }
        if !draft.hasSpace { return spaces.first?.id }
        return nil
    }

    // MARK: - Tokens

    private struct Token {
        let start: Int          // UTF-16
        let end: Int
        let text: String        // lowercased, the way parsing sees it
    }

    private struct Target {
        let start: Int
        let end: Int
        /// The original text of the fragment — it tells the day which style it
        /// was written in: a word or a date.
        let text: String
        let segment: Segment
        /// For a space, the already-resolved `Space.id`: a two-word name
        /// cannot be resolved again from a single token.
        let spaceID: String?

        init(start: Int, end: Int, text: String, segment: Segment, spaceID: String? = nil) {
            self.start = start
            self.end = end
            self.text = text
            self.segment = segment
            self.spaceID = spaceID
        }
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var tokenStart = 0
        var offset = 0

        for character in text.lowercased() {
            let width = String(character).utf16.count
            if character == " " || character == "," || character == "\t" {
                if !current.isEmpty {
                    tokens.append(Token(start: tokenStart, end: offset, text: current))
                    current = ""
                }
            } else {
                if current.isEmpty { tokenStart = offset }
                current.append(character)
            }
            offset += width
        }
        if !current.isEmpty {
            tokens.append(Token(start: tokenStart, end: offset, text: current))
        }
        return tokens
    }

    /// What the token under the caret is. The order of checks matches the one
    /// in parsing — otherwise an arrow would edit something other than what the
    /// answer below shows.
    private static func classify(_ tokens: [Token], at index: Int, caret: Int, today: CalendarDate) -> Target? {
        let token = tokens[index]

        // A two-word name: “meeting 1”. The caret may stand on either word.
        if index + 1 < tokens.count,
           let id = QueryParser.matchSpace(normalized(token.text) + normalized(tokens[index + 1].text)) {
            return Target(start: token.start, end: tokens[index + 1].end,
                          text: token.text, segment: .space, spaceID: id)
        }
        if index > 0,
           let id = QueryParser.matchSpace(normalized(tokens[index - 1].text) + normalized(token.text)) {
            return Target(start: tokens[index - 1].start, end: token.end,
                          text: tokens[index - 1].text, segment: .space, spaceID: id)
        }
        if QueryParser.parseDay(Substring(token.text), today: today) != nil {
            return Target(start: token.start, end: token.end, text: token.text, segment: .day)
        }
        // `1h 30m` is one duration in two words, like `meeting 1` is one name.
        // The caret may stand on either half.
        if index + 1 < tokens.count,
           QueryParser.parseDuration(Substring(token.text), Substring(tokens[index + 1].text)) != nil {
            return Target(start: token.start, end: tokens[index + 1].end,
                          text: token.text + " " + tokens[index + 1].text, segment: .duration)
        }
        if index > 0,
           QueryParser.parseDuration(Substring(tokens[index - 1].text), Substring(token.text)) != nil {
            return Target(start: tokens[index - 1].start, end: token.end,
                          text: tokens[index - 1].text + " " + token.text, segment: .duration)
        }
        if QueryParser.parseDuration(Substring(token.text)) != nil {
            return Target(start: token.start, end: token.end, text: token.text, segment: .duration)
        }
        if QueryParser.parseTime(Substring(token.text)) != nil {
            // Before the colon is the hour, after it the minutes. Without a
            // colon the whole token is the hour.
            let colon = token.text.firstIndex(of: ":").map { token.text.utf16Offset(of: $0, in: token.text) }
            let segment: Segment = colon.map { caret > token.start + $0 } == true ? .minute : .hour
            return Target(start: token.start, end: token.end, text: token.text, segment: segment)
        }
        if let id = QueryParser.matchSpace(normalized(token.text)) {
            return Target(start: token.start, end: token.end, text: token.text, segment: .space, spaceID: id)
        }
        return nil
    }

    /// The caret is not on an editable fragment — take the time, if there is one.
    private static func fallback(_ tokens: [Token]) -> Target? {
        for token in tokens where QueryParser.parseTime(Substring(token.text)) != nil
            && QueryParser.parseDuration(Substring(token.text)) == nil {
            return Target(start: token.start, end: token.end, text: token.text, segment: .minute)
        }
        return nil
    }

    // MARK: - Editing a fragment

    private static func replacement(
        for target: Target,
        by delta: Int,
        today: CalendarDate,
        spaces: [Space],
        dates: [CalendarDate]
    ) -> String? {
        switch target.segment {
        case .hour:
            return shiftedTime(target.text, byMinutes: delta * 60)
        case .minute:
            return shiftedTime(target.text, byMinutes: delta * SheetGrid.slotMinutes)
        case .duration:
            guard let minutes = duration(of: target.text) else { return nil }
            let shifted = minutes + delta * SheetGrid.slotMinutes
            guard shifted >= SheetGrid.slotMinutes,
                  shifted <= SheetGrid.slotCount * SheetGrid.slotMinutes else { return nil }
            return QueryParser.durationText(minutes: shifted)
        case .day:
            guard let date = QueryParser.parseDay(Substring(target.text), today: today),
                  let moved = stepDay(from: date, by: delta, through: dates)
            else { return nil }
            return renderDay(moved, like: target.text, today: today)
        case .space:
            guard let id = target.spaceID else { return nil }
            return stepSpace(from: id, by: delta, through: spaces)?.id
        }
    }

    /// The duration of a fragment, which is one token or two: `45m`, `1h`,
    /// `1h 30m`.
    private static func duration(of text: String) -> Int? {
        let parts = text.split(separator: " ")
        if parts.count == 2 { return QueryParser.parseDuration(parts[0], parts[1]) }
        return QueryParser.parseDuration(Substring(text))
    }

    /// The next day among those the sheet holds.
    ///
    /// Walking the calendar makes no sense here: the sheet holds ten working
    /// dates, and a step across a weekend or past the end of the period lands
    /// on a day the source does not have. At the edges of the period the arrow
    /// stops, the way time stops at the edges of the day. An empty list of
    /// dates (the schedule has not loaded yet) keeps the plain calendar step.
    private static func stepDay(from date: CalendarDate, by delta: Int, through dates: [CalendarDate]) -> CalendarDate? {
        guard !dates.isEmpty else { return date.adding(days: delta) }

        let ordered = dates.sorted()
        if let index = ordered.firstIndex(of: date) {
            let next = index + delta
            return ordered.indices.contains(next) ? ordered[next] : nil
        }
        // The named day is not in the sheet — move to the nearest one in the
        // direction of travel.
        return delta > 0 ? ordered.first { $0 > date } : ordered.last { $0 < date }
    }

    /// The next space in the cycling ring.
    ///
    /// The ring is normally the spaces free for the request; if it is empty the
    /// whole catalogue is used, otherwise the key would be dead. A space that
    /// is not in the ring (a taken one was named, say) has no place in it — in
    /// that case the nearest ring member in the direction of travel is taken,
    /// by catalogue order.
    private static func stepSpace(from id: String, by delta: Int, through spaces: [Space]) -> Space? {
        let ring = spaces.isEmpty ? Space.all : spaces
        guard !ring.isEmpty else { return nil }

        if let index = ring.firstIndex(where: { $0.id == id }) {
            return ring[(index + delta + ring.count) % ring.count]
        }
        guard let current = Space.all.firstIndex(where: { $0.id == id }) else { return ring.first }

        let order = ring.compactMap { space in
            Space.all.firstIndex(where: { $0.id == space.id }).map { (index: $0, space: space) }
        }.sorted { $0.index < $1.index }

        if delta > 0 {
            return (order.first { $0.index > current } ?? order.first)?.space
        } else {
            return (order.last { $0.index < current } ?? order.last)?.space
        }
    }

    /// Time stays inside the working day: an arrow at the edge does nothing
    /// rather than wrapping around to the other end.
    private static func shiftedTime(_ token: String, byMinutes minutes: Int) -> String? {
        guard let time = QueryParser.parseTime(Substring(token)) else { return nil }
        let shifted = time.adding(minutes: minutes)
        guard shifted >= SheetGrid.dayStart, shifted <= SheetGrid.dayEnd else { return nil }
        return shifted.description
    }

    /// The day is written back the way a person wrote it: a word as a word, a
    /// date as a date, and in the same language. A word is used only when the
    /// new day falls inside the coming week — further out, “mon” would mean a
    /// different Monday.
    private static func renderDay(_ date: CalendarDate, like original: String, today: CalendarDate) -> String {
        let parts = original.split(separator: "/")
        if parts.count >= 2, Int(parts[0]) != nil {
            return parts.count == 3 ? date.description : String(format: "%02d/%02d", date.day, date.month)
        }

        let language = QueryParser.language(ofDayWord: original) ?? .en
        return QueryParser.dayWord(for: date, today: today, language: language) ?? date.description
    }

    private static func normalized(_ text: String) -> String {
        QueryParser.normalized(Substring(text))
    }

    /// The caret stays in its own part: on the minutes it stays on the minutes,
    /// even when the hour changed length (`9:30` → `10:30`).
    private static func caretOffset(in target: Target, caret: Int, replacement: String) -> Int {
        let offset = max(0, caret - target.start)
        guard target.segment == .minute,
              let oldColon = target.text.firstIndex(of: ":"),
              let newColon = replacement.firstIndex(of: ":")
        else { return offset }

        let oldColonOffset = target.text.utf16Offset(of: oldColon, in: target.text)
        let newColonOffset = replacement.utf16Offset(of: newColon, in: replacement)
        return newColonOffset + (offset - oldColonOffset)
    }
}

private extension String {
    func utf16Offset(of index: String.Index, in string: String) -> Int {
        index.utf16Offset(in: string)
    }
}
