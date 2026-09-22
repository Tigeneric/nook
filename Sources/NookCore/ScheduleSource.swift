import Foundation

/// Where the schedule comes from.
///
/// The core knows nothing about who keeps the bookings — a spreadsheet, a
/// calendar, a service of one’s own. It asks for a `Schedule` and, when a
/// person wants to write a booking in, for somewhere to send them.
///
/// Everything vendor-specific lives behind this: the address of the document,
/// the shape of its tabs, the way a cell is named. Swapping the source means
/// writing one conformance, and the logic above stays untouched.
public protocol ScheduleSource: Sendable {
    /// Reads the whole period the source covers.
    func load(spaces: [Space]) async throws -> Schedule

    /// Where a person goes to write the booking in by hand.
    ///
    /// `nil` when the source has no such place — then the app simply offers
    /// nothing to open. The first version of Nook does not write anywhere
    /// itself, so this link is the whole of the write path.
    func bookingLink(for space: Space, date: CalendarDate, start: TimeOfDay, in schedule: Schedule) -> URL?
}

public extension ScheduleSource {
    func load() async throws -> Schedule {
        try await load(spaces: Space.all)
    }
}
