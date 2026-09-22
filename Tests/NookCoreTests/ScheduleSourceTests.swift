import Testing
import Foundation
@testable import NookCore

/// A source with no network and no vendor behind it.
///
/// Its whole point is to prove the seam holds: the logic above works against
/// `ScheduleSource`, so a coworking that keeps bookings somewhere other than a
/// Google Sheet needs one conformance and nothing else.
private struct InMemorySource: ScheduleSource {
    let schedule: Schedule
    let link: URL?

    func load(spaces: [Space]) async throws -> Schedule { schedule }

    func bookingLink(for space: Space, query: Query, in schedule: Schedule) -> URL? {
        link
    }
}

@Suite("A source other than the sheet")
struct ScheduleSourceTests {
    private let date = CalendarDate(year: 2026, month: 9, day: 18)

    private func schedule(occupied: [String: [Int: String]] = [:]) -> Schedule {
        var cells: [String: [[String?]]] = [:]
        for space in Space.all {
            let byName = occupied[space.id] ?? [:]
            cells[space.id] = [(0..<SheetGrid.slotCount).map { byName[$0] }]
        }
        return Schedule(spaces: Space.all, dates: [date], slots: SheetGrid.slots, cells: cells)
    }

    @Test("The search works over whatever the source returned")
    func searchesWhateverTheSourceGives() async throws {
        let slots = Dictionary(uniqueKeysWithValues: (24..<28).map { ($0, "Ana Petrović") })
        let source = InMemorySource(schedule: schedule(occupied: ["C1": slots]), link: nil)

        let loaded = try await source.load()
        let query = Query(date: date, start: TimeOfDay(hour: 14), minutes: 45)
        let free = Availability.fits(query, in: loaded)

        #expect(!free.contains { $0.id == "C1" })
        #expect(free.count == Space.all.count - 1)
    }

    @Test("A source without a place to write offers no link")
    func sourceWithoutAWritePlace() throws {
        let source = InMemorySource(schedule: schedule(), link: nil)
        let c1 = try #require(Space.named("C1"))
        let query = Query(date: date, start: TimeOfDay(hour: 14), minutes: 45)

        #expect(source.bookingLink(for: c1, query: query, in: source.schedule) == nil)
    }

    @Test("A link of any shape is fine — the core does not inspect it")
    func linkShapeIsUpToTheSource() throws {
        let link = try #require(URL(string: "https://booking.example/room/C1?at=2026-09-18T14:00"))
        let source = InMemorySource(schedule: schedule(), link: link)
        let c1 = try #require(Space.named("C1"))
        let query = Query(date: date, start: TimeOfDay(hour: 14), minutes: 45)

        #expect(source.bookingLink(for: c1, query: query, in: source.schedule) == link)
    }
}
