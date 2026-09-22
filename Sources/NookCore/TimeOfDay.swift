import Foundation

/// A time of day down to the minute, with no date and no time zone attached.
public struct TimeOfDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Minutes since midnight.
    public let minutes: Int

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public init(hour: Int, minute: Int = 0) {
        self.init(minutes: hour * 60 + minute)
    }

    /// Parses a cell from column A of a space tab: `8:00`, `10:15`, `08:00`.
    public init?(sheetLabel: String) {
        let parts = sheetLabel.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    public func adding(minutes delta: Int) -> TimeOfDay {
        TimeOfDay(minutes: minutes + delta)
    }

    public var description: String {
        String(format: "%d:%02d", hour, minute)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutes < rhs.minutes
    }
}

/// Geometry of the source grid: 49 slots of 15 minutes, 8:00 to 20:00 inclusive.
/// The numbers are fixed rather than derived from the data — that is how the
/// sheet is laid out.
public enum SheetGrid {
    public static let dayStart = TimeOfDay(hour: 8)
    public static let dayEnd = TimeOfDay(hour: 20)
    public static let slotMinutes = 15
    public static let slotCount = 49

    public static let slots: [TimeOfDay] = (0..<slotCount).map {
        dayStart.adding(minutes: $0 * slotMinutes)
    }

    /// Slot index, if the time falls exactly on a slot boundary within the day.
    public static func slotIndex(of time: TimeOfDay) -> Int? {
        let offset = time.minutes - dayStart.minutes
        guard offset >= 0, offset % slotMinutes == 0 else { return nil }
        let index = offset / slotMinutes
        return index < slotCount ? index : nil
    }

    /// The nearest slot no earlier than the given time — used by “now” queries.
    /// `nil` once the working day is over.
    public static func slotIndex(atOrAfter time: TimeOfDay) -> Int? {
        let offset = time.minutes - dayStart.minutes
        guard offset < slotCount * slotMinutes else { return nil }
        guard offset > 0 else { return 0 }
        let index = (offset + slotMinutes - 1) / slotMinutes
        return index < slotCount ? index : nil
    }

    /// The time a request is offered by default: the nearest slot no earlier
    /// than now, and the start of the day once the working day is over — past
    /// 20:00 there is nothing left to offer until morning.
    public static func suggestedStart(after now: TimeOfDay) -> TimeOfDay {
        slotIndex(atOrAfter: now).map { slots[$0] } ?? dayStart
    }

    /// The nearest slot no later than the given time. `nil` before the day starts.
    public static func slotIndex(atOrBefore time: TimeOfDay) -> Int? {
        let offset = time.minutes - dayStart.minutes
        guard offset >= 0 else { return nil }
        return min(offset / slotMinutes, slotCount - 1)
    }
}
