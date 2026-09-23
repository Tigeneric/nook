import Foundation

/// Finding the spaces a request fits into.
public enum Availability {
    /// Spaces free for the whole requested interval, in catalogue order.
    /// When the request names a space, only that one is checked.
    ///
    /// Candidates are not ranked against each other — no criterion for “better”
    /// has been chosen, and the question is deliberately left open.
    public static func fits(_ query: Query, in schedule: Schedule) -> [Space] {
        guard let dateIndex = schedule.dateIndex(of: query.date),
              let startSlot = SheetGrid.slotIndex(of: query.start)
        else { return [] }

        let endSlot = startSlot + query.slotCount
        guard endSlot <= schedule.slots.count else { return [] }

        let searched = query.spaceID.map { id in schedule.spaces.filter { $0.id == id } } ?? schedule.spaces
        return searched.filter { space in
            (startSlot..<endSlot).allSatisfy {
                schedule.isFree(space: space, dateIndex: dateIndex, slotIndex: $0)
            }
        }
    }

    /// Who holds the space during the requested interval — in slot order,
    /// without repeats. Empty when the space is free, or when the request does
    /// not land on the grid.
    public static func occupants(of space: Space, during query: Query, in schedule: Schedule) -> [String] {
        guard let dateIndex = schedule.dateIndex(of: query.date),
              let startSlot = SheetGrid.slotIndex(of: query.start)
        else { return [] }

        let endSlot = min(startSlot + query.slotCount, schedule.slots.count)
        var names: [String] = []
        for slotIndex in startSlot..<endSlot {
            guard let name = schedule.occupant(space: space, dateIndex: dateIndex, slotIndex: slotIndex),
                  !names.contains(name)
            else { continue }
            names.append(name)
        }
        return names
    }

    /// The free run a request falls inside.
    public struct FreeWindow: Equatable, Sendable {
        public let start: TimeOfDay
        public let end: TimeOfDay
        /// On the left the run ends at someone else’s booking, not at the start of the day.
        public let startsAtBooking: Bool
        /// On the right, likewise: a booking rather than the end of the day.
        public let endsAtBooking: Bool

        /// The request is flush against a booking on the left.
        public func isTightBefore(_ query: Query) -> Bool {
            startsAtBooking && start == query.start
        }

        /// The request is flush against a booking on the right.
        public func isTightAfter(_ query: Query) -> Bool {
            endsAtBooking && end == query.end
        }
    }

    /// How much room there is around a request: the bounds of the continuous
    /// free run it landed in.
    ///
    /// “Free” on its own does not answer how much room there is: a half-hour
    /// gap wedged between two bookings and a day that is empty until evening
    /// look exactly the same. `nil` when the request does not fit the space.
    public static func freeWindow(for query: Query, in space: Space, of schedule: Schedule) -> FreeWindow? {
        guard let dateIndex = schedule.dateIndex(of: query.date),
              let startSlot = SheetGrid.slotIndex(of: query.start)
        else { return nil }

        let endSlot = startSlot + query.slotCount
        guard endSlot <= schedule.slots.count,
              (startSlot..<endSlot).allSatisfy({
                  schedule.isFree(space: space, dateIndex: dateIndex, slotIndex: $0)
              })
        else { return nil }

        var from = startSlot
        while from > 0, schedule.isFree(space: space, dateIndex: dateIndex, slotIndex: from - 1) {
            from -= 1
        }
        var to = endSlot
        while to < schedule.slots.count, schedule.isFree(space: space, dateIndex: dateIndex, slotIndex: to) {
            to += 1
        }

        // The loops above stopped either at the edge of the day or on a taken
        // slot — which is how the bounds of the run are known.
        return FreeWindow(
            start: schedule.slots[from],
            end: schedule.slots[to - 1].adding(minutes: SheetGrid.slotMinutes),
            startsAtBooking: from > 0,
            endsAtBooking: to < schedule.slots.count
        )
    }

    /// Free runs of a space on a date — for hints and for future ranking.
    public static func freeWindows(space: Space, dateIndex: Int, in schedule: Schedule) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?

        for slotIndex in schedule.slots.indices {
            let free = schedule.isFree(space: space, dateIndex: dateIndex, slotIndex: slotIndex)
            if free, start == nil {
                start = slotIndex
            } else if !free, let from = start {
                result.append(from..<slotIndex)
                start = nil
            }
        }
        if let from = start {
            result.append(from..<schedule.slots.count)
        }
        return result
    }

    /// A continuous free run of a space on a calendar date.
    public struct FreeRun: Equatable, Sendable {
        public let date: CalendarDate
        public let start: TimeOfDay
        public let end: TimeOfDay
        public let isOpenNow: Bool
        public var minutes: Int { end.minutes - start.minutes }

        public init(date: CalendarDate, start: TimeOfDay, end: TimeOfDay, isOpenNow: Bool = false) {
            self.date = date
            self.start = start
            self.end = end
            self.isOpenNow = isOpenNow
        }
    }

    /// Free runs of a space on the day being asked about — **that day alone**.
    ///
    /// The question behind this is «when is MR1 free», and it is asked about a
    /// day: the named one, or today when none was named. So the answer does not
    /// spill into the dates that follow while the day itself still has
    /// something to offer — a list of four rows drawn from four different days
    /// reads as a calendar, not as an answer.
    ///
    /// It moves on to the next sheet date only when the day has nothing left:
    /// the evening past 19:45, a day booked solid, or a date the sheet does not
    /// hold at all — a weekend. That is the same promise the ghost makes, and
    /// for the same reason: `MR1` at 19:50 offers `чт 8:00`, not a morning that
    /// is twelve hours gone.
    ///
    /// Truncated on the left by `now` on the day asked about, and filtered by
    /// `minMinutes` — which is what makes «nothing left» a question about the
    /// duration requested rather than about bare emptiness.
    public static func freeWindows(
        space: Space,
        in schedule: Schedule,
        from date: CalendarDate,
        after now: TimeOfDay?,
        minMinutes: Int = 0
    ) -> [FreeRun] {
        guard let startIndex = schedule.dates.firstIndex(where: { $0 >= date }) else { return [] }

        for dateIndex in startIndex..<schedule.dates.count {
            let isDayAsked = (dateIndex == startIndex) && (schedule.dates[dateIndex] == date)
            let runs = freeRuns(
                space: space,
                dateIndex: dateIndex,
                in: schedule,
                after: isDayAsked ? now : nil,
                minMinutes: minMinutes
            )
            // The first date that has anything to say is the whole answer.
            if !runs.isEmpty { return runs }
        }
        return []
    }

    /// Free runs of one date of the sheet, as rows rather than slot ranges.
    ///
    /// `now` truncates on the left and is what `isOpenNow` is decided against;
    /// `nil` means the whole day, which is how a named day is counted — it is
    /// not «today». Empty when the evening has run out of grid.
    private static func freeRuns(
        space: Space,
        dateIndex: Int,
        in schedule: Schedule,
        after now: TimeOfDay?,
        minMinutes: Int
    ) -> [FreeRun] {
        let date = schedule.dates[dateIndex]
        let minSlot: Int
        if let now {
            guard let slot = SheetGrid.slotIndex(atOrAfter: now) else { return [] }
            minSlot = slot
        } else {
            minSlot = 0
        }

        var runs: [FreeRun] = []
        for range in freeWindows(space: space, dateIndex: dateIndex, in: schedule) {
            let effectiveStart = max(range.lowerBound, minSlot)
            guard effectiveStart < range.upperBound else { continue }
            let start = schedule.slots[effectiveStart]
            let end = schedule.slots[range.upperBound - 1].adding(minutes: SheetGrid.slotMinutes)
            guard end.minutes - start.minutes >= minMinutes else { continue }
            let isOpenNow: Bool
            if let now, let currentSlot = SheetGrid.slotIndex(atOrBefore: now) {
                isOpenNow = range.contains(currentSlot)
            } else {
                isOpenNow = false
            }
            runs.append(FreeRun(date: date, start: start, end: end, isOpenNow: isOpenNow))
        }
        return runs
    }

    /// One row of the answer to «when is this space free».
    ///
    /// A day with nothing to offer is a row of its own rather than a silent
    /// skip: «no free window today» is an answer, whereas jumping straight to
    /// Friday leaves the person to work out what happened to Wednesday and
    /// Thursday.
    public enum WindowRow: Equatable, Sendable {
        case window(FreeRun)
        case unavailable(CalendarDate)
    }

    /// The rows the overlay shows, and how many windows the ceiling cut off.
    public struct WindowAnswer: Equatable, Sendable {
        public let rows: [WindowRow]
        /// Windows of the listed day that did not fit. Rows of days with
        /// nothing are never dropped silently — the walk stops instead.
        public let more: Int

        public init(rows: [WindowRow], more: Int) {
            self.rows = rows
            self.more = more
        }
    }

    /// «When is MR1 free», answered in at most `rowLimit` rows.
    ///
    /// Dates are walked from the one asked about, and each contributes either
    /// its free runs or a single row saying it has none. The walk stops at the
    /// first date with windows — that day is the answer, and the days before it
    /// are there to explain the gap, so the rows never read as a calendar.
    ///
    /// The ceiling is shared by both kinds of row, which is what makes the
    /// answer a fixed height: a booked today and a following day with five
    /// windows come out as one row of explanation and two windows, not as six
    /// rows. Windows beyond it are counted in `more`; days beyond it are not
    /// walked at all, so three days booked solid end the answer and the fourth
    /// is left to the ghost in the query line.
    ///
    /// `withinDay` keeps the answer inside the day named: a request for a
    /// Thursday is not answered with a Friday. Empty `rows` mean the sheet
    /// holds no date from the one asked about onwards — «not in the sheet»
    /// rather than «nothing free».
    public static func windowAnswer(
        space: Space,
        in schedule: Schedule,
        from date: CalendarDate,
        after now: TimeOfDay?,
        minMinutes: Int = 0,
        withinDay: Bool,
        rowLimit: Int
    ) -> WindowAnswer {
        guard rowLimit > 0,
              let startIndex = schedule.dates.firstIndex(where: { $0 >= date }),
              !withinDay || schedule.dates[startIndex] == date
        else { return WindowAnswer(rows: [], more: 0) }

        var rows: [WindowRow] = []
        for dateIndex in startIndex..<schedule.dates.count {
            let isDayAsked = (dateIndex == startIndex) && (schedule.dates[dateIndex] == date)
            let runs = freeRuns(
                space: space,
                dateIndex: dateIndex,
                in: schedule,
                after: isDayAsked ? now : nil,
                minMinutes: minMinutes
            )
            if runs.isEmpty {
                rows.append(.unavailable(schedule.dates[dateIndex]))
                if withinDay || rows.count == rowLimit { break }
                continue
            }
            let room = rowLimit - rows.count
            rows.append(contentsOf: runs.prefix(room).map(WindowRow.window))
            return WindowAnswer(rows: rows, more: max(0, runs.count - room))
        }
        return WindowAnswer(rows: rows, more: 0)
    }

    /// Ближайшее свободное окно помещения, начиная с `date`/`now`.
    /// `now == nil` — считать от начала дня (названный день — не «сегодня»).
    /// Пересекает даты таблицы: вечером ответ уезжает на следующую.
    public static func nextWindow(
        space: Space,
        in schedule: Schedule,
        from date: CalendarDate,
        after now: TimeOfDay?,
        minMinutes: Int = 0
    ) -> (date: CalendarDate, start: TimeOfDay, end: TimeOfDay)? {
        freeWindows(space: space, in: schedule, from: date, after: now, minMinutes: minMinutes)
            .first
            .map { ($0.date, $0.start, $0.end) }
    }
}
