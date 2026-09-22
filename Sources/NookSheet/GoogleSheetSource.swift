import Foundation
import NookCore

/// Why the sheet could not be read.
///
/// The cases are kept apart rather than flattened into a string, because a
/// person needs to be told about them differently — and because **a URL must
/// never reach the message**: it carries the sheet identifier, which is the
/// key to every booking name. The system `NSError` from `URLSession` prints
/// the full address, so it does not travel outwards: only the kind of failure
/// survives here.
public enum SheetLoadError: Error, Sendable {
    /// There is no network at all.
    case offline
    /// There is a network, but no answer came in time.
    case timedOut
    /// Another networking failure — the code is kept for reporting, the address dropped.
    case network(code: Int)
    case http(space: String, status: Int)
    case notText(space: String)
    case parse(space: String, reason: String)
    case datesDisagree(space: String)
}

/// A `ScheduleSource` backed by a Google Sheet: one CSV-export request per
/// space tab, all of them in parallel.
///
/// The summary tab is not used — its addressing is tied to “today” and shifts
/// every day, whereas space tabs address stably.
public struct GoogleSheetSource: ScheduleSource {
    private let spreadsheetID: String
    private let session: URLSession

    public init(spreadsheetID: String, session: URLSession = .shared) {
        self.spreadsheetID = spreadsheetID
        self.session = session
    }

    public func load(spaces: [Space]) async throws -> Schedule {
        let tabs = try await withThrowingTaskGroup(of: (String, RoomTab).self) { group in
            for space in spaces {
                group.addTask { (space.id, try await self.loadTab(space)) }
            }
            var result: [String: RoomTab] = [:]
            for try await (id, tab) in group {
                result[id] = tab
            }
            return result
        }

        // The period is shared by all tabs; take it from the first and check
        // the rest against it, so a mismatch does not turn into a silent
        // column shift.
        guard let first = spaces.first, let reference = tabs[first.id] else {
            return Schedule(spaces: spaces, dates: [], slots: SheetGrid.slots, cells: [:])
        }
        for space in spaces.dropFirst() {
            guard tabs[space.id]?.dates == reference.dates else {
                throw SheetLoadError.datesDisagree(space: space.id)
            }
        }

        return Schedule(
            spaces: spaces,
            dates: reference.dates,
            slots: reference.slots,
            cells: tabs.mapValues(\.cells)
        )
    }

    /// Where a person goes to type the name in. The first version writes
    /// nothing itself, so this link is the whole write path.
    public func bookingLink(
        for space: Space,
        date: CalendarDate,
        start: TimeOfDay,
        in schedule: Schedule
    ) -> URL? {
        guard let dateIndex = schedule.dateIndex(of: date),
              let slotIndex = SheetGrid.slotIndex(of: start)
        else { return nil }

        return SheetAddress.deepLink(
            spreadsheetID: spreadsheetID,
            space: space,
            dateIndex: dateIndex,
            slotIndex: slotIndex
        )
    }

    private func loadTab(_ space: Space) async throws -> RoomTab {
        let url = GoogleSheet.csvExportURL(spreadsheetID: spreadsheetID, gid: space.sourceKey)
        // No caching: the schedule is re-read on every showing of the overlay,
        // because the sheet is edited during the day — measured, not assumed.
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // The error is rebuilt here: the system one carries the full URL,
            // that is the sheet identifier, and it leaks everywhere it is printed.
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
                throw SheetLoadError.offline
            case .timedOut:
                throw SheetLoadError.timedOut
            default:
                throw SheetLoadError.network(code: error.errorCode)
            }
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SheetLoadError.http(space: space.id, status: http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SheetLoadError.notText(space: space.id)
        }
        do {
            return try RoomTabParser.parse(text)
        } catch let error as RoomTabParseError {
            throw SheetLoadError.parse(space: space.id, reason: error.description)
        }
    }
}
