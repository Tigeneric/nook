import Foundation
import NookCore

/// A made-up day, so the app can be looked at — and photographed — without a
/// sheet behind it.
///
/// The pictures in the README cannot be taken against the real sheet. It is
/// read without authorisation, so a picture of it publishes the name of
/// everybody who booked a room that week; and a PNG is the one thing the
/// pre-commit hook cannot read, so here the rule has to hold by construction
/// rather than by checking. Every name below is invented.
///
/// Times are built from the clock rather than written down, so “now” and
/// “in 20 min” read correctly whenever the picture is taken.
enum Demo {
    /// Whose bookings the list shows. Invented, like the rest.
    static let bookingName = "Ana Petrović"

    /// The settings validator wants ASCII letters, digits, dash or underscore —
    /// nothing more. The demo source never looks at it.
    static let spreadsheetID = "demo"

    /// Settings of their own, in their own defaults domain, so a demo run
    /// cannot touch what a person has configured for the real sheet.
    @MainActor
    static func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier ?? "nook").demo") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.setSpreadsheet(spreadsheetID)
        preferences.setBookingName(bookingName)
        preferences.floor = 1
        return preferences
    }
}

/// The schedule `--demo` reads instead of the sheet.
struct DemoSource: ScheduleSource {
    /// Ten dates from today, the way the sheet holds a sliding period.
    private static func dates(from today: CalendarDate) -> [CalendarDate] {
        (0..<10).map { today.adding(days: $0) }
    }

    func load(spaces: [Space]) async throws -> Schedule {
        let today = CalendarDate(Date())
        let dates = Self.dates(from: today)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = TimeOfDay(hour: parts.hour ?? 12, minute: parts.minute ?? 0)

        var cells: [String: [[String?]]] = [:]
        for space in spaces {
            cells[space.id] = dates.map { _ in [String?](repeating: nil, count: SheetGrid.slotCount) }
        }

        func fill(_ spaceID: String, _ dateIndex: Int, _ from: TimeOfDay, _ to: TimeOfDay, _ name: String) {
            guard var byDate = cells[spaceID], byDate.indices.contains(dateIndex),
                  let start = SheetGrid.slotIndex(atOrBefore: from),
                  let end = SheetGrid.slotIndex(atOrBefore: to)
            else { return }
            for slot in start..<max(start + 1, end) where byDate[dateIndex].indices.contains(slot) {
                byDate[dateIndex][slot] = name
            }
            cells[spaceID] = byDate
        }

        // Somebody else’s day, so a request has something to bump into.
        fill("C1", 0, TimeOfDay(hour: 9), TimeOfDay(hour: 10, minute: 30), "Marko Jurić")
        fill("C1", 0, TimeOfDay(hour: 13), TimeOfDay(hour: 14, minute: 30), "Nikola Savić")
        fill("C3", 0, TimeOfDay(hour: 11), TimeOfDay(hour: 13), "Jelena Marković")
        fill("C3", 0, TimeOfDay(hour: 14), TimeOfDay(hour: 15), "Jelena Marković")
        fill("C4", 0, TimeOfDay(hour: 16), TimeOfDay(hour: 17, minute: 30), "Petar Nikolić")
        // One cell per slot, numbered — the shape a company books in.
        fill("C4", 0, TimeOfDay(hour: 9, minute: 30), TimeOfDay(hour: 9, minute: 45), "Acme Studio 2")
        fill("C4", 0, TimeOfDay(hour: 9, minute: 45), TimeOfDay(hour: 10), "Acme Studio 3")
        fill("MR1", 0, TimeOfDay(hour: 10), TimeOfDay(hour: 11, minute: 30), "Jelena Marković")

        // Mine: one running right now, one later today, one on another day.
        let runningSlot = SheetGrid.slotIndex(atOrBefore: now) ?? 24
        let running = SheetGrid.slots[runningSlot]
        fill("C2", 0, running, running.adding(minutes: 45), Demo.bookingName)
        fill("MR1", 0, TimeOfDay(hour: 16, minute: 30), TimeOfDay(hour: 17, minute: 30), Demo.bookingName)
        fill("C1", 2, TimeOfDay(hour: 10), TimeOfDay(hour: 11), Demo.bookingName)

        return Schedule(spaces: spaces, dates: dates, slots: SheetGrid.slots, cells: cells)
    }

    /// There is nowhere to send anybody: the sheet behind this does not exist.
    func bookingLink(for space: Space, date: CalendarDate, start: TimeOfDay, in schedule: Schedule) -> URL? {
        nil
    }
}
