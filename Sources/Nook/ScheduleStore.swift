import Foundation
import NookCore
import NookSheet
import Observation

/// Schedule state for the span of a single showing of the overlay.
@MainActor
@Observable
final class ScheduleStore {
    enum State {
        case idle
        case notConfigured
        case loading
        case loaded(Schedule)
        case failed(SheetLoadError)
    }

    private(set) var state: State = .idle
    /// The source the current schedule came from — the booking link is asked
    /// of it, so the app layer never builds one itself.
    private(set) var source: (any ScheduleSource)?

    private let preferences: Preferences
    private let sourceFactory: (String) -> any ScheduleSource
    private var task: Task<Void, Never>?

    init(
        preferences: Preferences,
        sourceFactory: @escaping (String) -> any ScheduleSource = { GoogleSheetSource(spreadsheetID: $0) }
    ) {
        self.preferences = preferences
        self.sourceFactory = sourceFactory
    }

    var schedule: Schedule? {
        if case let .loaded(schedule) = state { return schedule }
        return nil
    }

    /// Re-reads the sheet in full. Called on **every showing** of the
    /// overlay: the sheet is edited during the day, and a cache kept between
    /// showings would present yesterday.
    func reload() {
        task?.cancel()
        guard let spreadsheetID = preferences.spreadsheetID else {
            state = .notConfigured
            return
        }

        let source = sourceFactory(spreadsheetID)
        state = .loading
        self.source = source
        task = Task {
            do {
                let schedule = try await source.load()
                guard !Task.isCancelled else { return }
                state = .loaded(schedule)
            } catch let error as SheetLoadError {
                guard !Task.isCancelled else { return }
                state = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                // The loader throws nothing but its own errors; this branch
                // is a safety net, and no address reaches it either.
                state = .failed(.network(code: (error as NSError).code))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
