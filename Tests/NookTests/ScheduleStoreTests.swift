import Foundation
import Testing
import NookCore
import NookSheet
@testable import Nook

private struct StoreTestSource: ScheduleSource {
    let result: Result<Schedule, SheetLoadError>
    var delay: Duration = .zero

    func load(spaces: [Space]) async throws -> Schedule {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return try result.get()
    }

    func bookingLink(
        for space: Space,
        date: CalendarDate,
        start: TimeOfDay,
        in schedule: Schedule
    ) -> URL? {
        nil
    }
}

@Suite("Schedule store", .serialized)
@MainActor
struct ScheduleStoreTests {
    @Test("Reload without a configured sheet stops immediately")
    func notConfigured() {
        let preferences = makePreferences()
        let store = ScheduleStore(preferences: preferences)

        store.reload()

        guard case .notConfigured = store.state else {
            Issue.record("Expected notConfigured")
            return
        }
    }

    @Test("A successful reload publishes the schedule")
    func loaded() async throws {
        let preferences = makePreferences(configured: true)
        let expected = Schedule(spaces: [], dates: [], slots: SheetGrid.slots, cells: [:])
        let store = ScheduleStore(preferences: preferences) { _ in
            StoreTestSource(result: .success(expected))
        }

        store.reload()
        try await waitUntil { store.schedule != nil }

        guard case .loaded = store.state else {
            Issue.record("Expected loaded")
            return
        }
    }

    @Test("Cancelling a reload prevents a late state update")
    func cancellation() async throws {
        let preferences = makePreferences(configured: true)
        let schedule = Schedule(spaces: [], dates: [], slots: SheetGrid.slots, cells: [:])
        let store = ScheduleStore(preferences: preferences) { _ in
            StoreTestSource(result: .success(schedule), delay: .milliseconds(100))
        }

        store.reload()
        store.cancel()
        try await Task.sleep(for: .milliseconds(150))

        guard case .loading = store.state else {
            Issue.record("A cancelled task changed the state")
            return
        }
    }

    private func makePreferences(configured: Bool = false) -> Preferences {
        let suite = "ScheduleStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        if configured {
            preferences.setSpreadsheet("TEST_ID")
        }
        return preferences
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for state")
    }
}
