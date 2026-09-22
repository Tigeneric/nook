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
}
