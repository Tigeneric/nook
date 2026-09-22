import Foundation

/// One booking held by a named person: a run of cells carrying that name.
///
/// Unlike `Schedule.Block` this one knows where it sits — space and date — so
/// it can be shown on its own, out of the grid.
public struct Booking: Equatable, Sendable {
    public let space: Space
    public let date: CalendarDate
    public let start: TimeOfDay
    public let end: TimeOfDay
    /// The name exactly as the sheet spells it, suffixes and all.
    public let name: String

    public init(space: Space, date: CalendarDate, start: TimeOfDay, end: TimeOfDay, name: String) {
        self.space = space
        self.date = date
        self.start = start
        self.end = end
        self.name = name
    }
}

/// A person’s own bookings, nearest first — what the overlay shows before
/// anything has been typed.
public enum Agenda {
    /// Bookings whose name matches `name`, from `now` onwards.
    ///
    /// A booking already under way is included: at 14:20 “C2 until 14:45” is
    /// the most relevant line on the screen, and dropping it would answer
    /// “nothing today” to someone sitting in the booth.
    ///
    /// Days beyond today are taken from the sheet in its own order — there is
    /// no arithmetic on dates here, because the sheet’s period is what exists.
    public static func upcoming(
        for name: String,
        in schedule: Schedule,
        spaces: [Space],
        today: CalendarDate,
        now: TimeOfDay,
        limit: Int = 3
    ) -> [Booking] {
        guard limit > 0 else { return [] }
        let ahead = all(for: name, in: schedule, spaces: spaces).filter { booking in
            // Today the past is cut away; on later days the whole day counts.
            booking.date > today || (booking.date == today && booking.end > now)
        }
        return Array(ahead.prefix(limit))
    }

    /// Every booking of this person the sheet holds, over its whole period, in
    /// date and time order.
    ///
    /// Answers “is this name in the sheet at all”, which is what settings need
    /// while the name is being typed: a misspelling matches nothing, and
    /// without this it looks exactly like an empty week.
    public static func all(for name: String, in schedule: Schedule, spaces: [Space]) -> [Booking] {
        guard !normalize(name).isEmpty else { return [] }

        // Catalogue order decides ties within one minute, so a space needs its
        // position: two bookings can start at the same time in two rooms.
        let order = Dictionary(uniqueKeysWithValues: spaces.enumerated().map { ($0.element.id, $0.offset) })
        var found: [Booking] = []

        for (dateIndex, date) in zip(schedule.dates.indices, schedule.dates) {
            for space in spaces {
                for block in schedule.blocks(space: space, dateIndex: dateIndex) {
                    guard matches(block.name, name: name),
                          let booking = booking(block, space: space, date: date, in: schedule)
                    else { continue }
                    found.append(booking)
                }
            }
        }

        found.sort {
            ($0.date, $0.start.minutes, order[$0.space.id] ?? 0)
                < ($1.date, $1.start.minutes, order[$1.space.id] ?? 0)
        }
        return found
    }

    private static func booking(
        _ block: Schedule.Block,
        space: Space,
        date: CalendarDate,
        in schedule: Schedule
    ) -> Booking? {
        guard schedule.slots.indices.contains(block.startSlot),
              schedule.slots.indices.contains(block.endSlot - 1)
        else { return nil }
        return Booking(
            space: space,
            date: date,
            start: schedule.slots[block.startSlot],
            end: schedule.slots[block.endSlot - 1].adding(minutes: SheetGrid.slotMinutes),
            name: block.name
        )
    }

    /// Whether a cell belongs to the person who configured `name`.
    ///
    /// **Exact equality**, with case, diacritics and whitespace disregarded —
    /// so `AnaPetrovic` and `Ana Petrović` are one name. Whether a name carries
    /// a space in it is not a fact about the person: the sheet is typed by
    /// hand, and the same member appears both ways.
    ///
    /// Nothing looser than that. A first name on its own does **not** match a
    /// fuller name in the cell: it would collect a namesake’s day as readily as
    /// your own, and a booking list that shows someone else’s meeting is worse
    /// than one that shows nothing.
    ///
    /// The price is the numbered form a company writes — `Acme`, `Acme 2`,
    /// `Acme 3`, one per slot (see `Schedule.blocks`). Those are four different
    /// names here, and `Acme` finds none of them.
    public static func matches(_ cellName: String, name: String) -> Bool {
        let cell = joined(cellName)
        let mine = joined(name)
        guard !cell.isEmpty, !mine.isEmpty else { return false }
        return cell == mine
    }

    /// How the sheet spells this name, when it is the same name spelled
    /// otherwise. `nil` when the roster has nothing to add.
    ///
    /// A booking cell is a dropdown over the roster, and the rule behind it
    /// compares **literally**: `Ana Petrović` is refused where the roster
    /// holds `AnaPetrovic`. Reading folds that apart on purpose — whether a
    /// name carries a space is not a fact about the person — so a name can
    /// find every booking of its owner and still be turned away on the way in.
    /// The fold is what closes that gap: the substitution is the roster’s
    /// spelling of the same name, differing only in what the fold has already
    /// declared insignificant.
    ///
    /// **Nothing looser than the fold.** `closestName` answers “did you mean”,
    /// and its tolerance is right for a question and wrong for an answer: a
    /// near-miss written into a document the whole coworking shares puts
    /// somebody else’s name on the booking, and the booking is then theirs.
    ///
    /// Two entries folding alike leave no spelling to choose, and guessing
    /// between two living people is worse than pasting what was typed.
    public static func canonicalName(for name: String, in schedule: Schedule) -> String? {
        let mine = joined(name)
        guard !mine.isEmpty else { return nil }

        var found: String?
        for candidate in schedule.roster where joined(candidate) == mine {
            guard found == nil else { return nil }
            found = candidate
        }
        return found == name ? nil : found
    }

    /// Where an arrow moves the focus over the shown list.
    ///
    /// `nil` is **the query line itself**, which sits above the list — so the
    /// whole thing reads as one column: line, then rows. ↓ from the line enters
    /// at the first row, ↑ from the first row goes back up to the line, ↑ in
    /// the line does nothing because there is nothing above it, and ↓ on the
    /// last row stays there because there is nothing below.
    ///
    /// Reading is spatial, which is the reverse of the stepper the arrows are
    /// everywhere else in this field — `delta` arrives with the stepper’s sign,
    /// `+1` for up. The two never collide: the arrows reach the list only while
    /// the line is empty, and the first character typed hands them back.
    ///
    /// Nothing wraps round. The list is on screen in full, so there is nowhere
    /// to wrap to — the same rule as time at the edges of the day and days at
    /// the edges of the sheet’s period.
    public static func selection(from current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0, delta != 0 else { return current }
        let up = delta > 0
        guard let current else { return up ? nil : 0 }
        if up { return current == 0 ? nil : current - 1 }
        return min(current + 1, count - 1)
    }

    /// A name the sheet already carries that is close enough to `name` to be
    /// the same person, misspelled. `nil` when nothing is close.
    ///
    /// This answers what a count cannot. A name matching nothing is either a
    /// typo or somebody who has never booked, and those two deserve opposite
    /// answers: one is “check the spelling”, the other is “that is normal”.
    /// A near-miss sitting in the sheet is the evidence that tells them apart.
    ///
    /// Whitespace is dropped before comparing, for the same reason
    /// `matches(_:name:)` drops it: a space inside a name is not a difference
    /// worth keeping while looking for near-misses.
    public static func closestName(to name: String, in schedule: Schedule) -> String? {
        let mine = joined(name)
        guard mine.count > 2 else { return nil }

        var best: (name: String, distance: Int)?
        for byDate in schedule.cells.values {
            for row in byDate {
                for case let cell? in row {
                    // An exact holder needs no suggestion — it is already found.
                    guard !matches(cell, name: name) else { return nil }
                    let candidate = joined(cell)
                    guard !candidate.isEmpty else { continue }
                    let distance = editDistance(mine, candidate)
                    // Up to a fifth of the longer name may differ: one slip in
                    // a short name, two or three in a long one. Wider than that
                    // starts proposing strangers.
                    guard distance * 5 <= max(mine.count, candidate.count) else { continue }
                    if best == nil || distance < best!.distance {
                        best = (cell, distance)
                    }
                }
            }
        }
        return best?.name
    }

    /// Normalised and stripped of spaces: the sheet is written by hand, and
    /// whether a name carries a space in it is not a difference worth keeping
    /// while looking for near-misses.
    private static func joined(_ text: String) -> String {
        words(of: text).joined()
    }

    /// Levenshtein distance, two rows at a time. The strings are names, so the
    /// sizes are tiny and the plain algorithm is the right one.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Case and diacritics are dropped: the sheet is typed by hand, and `ANNA`,
    /// `Anna` and `Аnna` are the same person. Cyrillic folds too — `ё` and `е`
    /// are written interchangeably.
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(of text: String) -> [String] {
        normalize(text).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
