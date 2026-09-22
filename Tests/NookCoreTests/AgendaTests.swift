import Testing
@testable import NookCore

/// A two-date schedule built from “who holds which slots”, keyed by date index.
private func schedule(_ occupied: [String: [Int: [Int: String]]]) -> Schedule {
    var cells: [String: [[String?]]] = [:]
    for space in Space.all {
        let byDate = occupied[space.id] ?? [:]
        cells[space.id] = dates.indices.map { dateIndex in
            let bySlot = byDate[dateIndex] ?? [:]
            return (0..<SheetGrid.slotCount).map { bySlot[$0] }
        }
    }
    return Schedule(spaces: Space.all, dates: dates, slots: SheetGrid.slots, cells: cells)
}

private let dates = [
    CalendarDate(year: 2026, month: 9, day: 18),
    CalendarDate(year: 2026, month: 9, day: 21),
]
private let today = dates[0]
private let tomorrow = dates[1]

/// Slots 24…27 are 14:00–15:00.
private func run(_ range: Range<Int>, _ name: String) -> [Int: String] {
    Dictionary(uniqueKeysWithValues: range.map { ($0, name) })
}

@Suite("My own bookings")
struct AgendaTests {

    @Test("The nearest booking of the day comes first")
    func nearestFirst() {
        let schedule = schedule([
            "C1": [0: run(24..<28, "Ana Petrović")],      // 14:00–15:00
            "C3": [0: run(12..<14, "Ana Petrović")],      // 11:00–11:30
        ])

        let mine = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                   today: today, now: TimeOfDay(hour: 9))

        #expect(mine.map(\.space.id) == ["C3", "C1"])
        #expect(mine.first?.start == TimeOfDay(hour: 11))
        #expect(mine.first?.end == TimeOfDay(hour: 11, minute: 30))
    }

    @Test("A booking already over is not upcoming")
    func dropsThePast() {
        let schedule = schedule(["C1": [0: run(12..<14, "Ana Petrović")]])   // 11:00–11:30

        #expect(Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                today: today, now: TimeOfDay(hour: 12)).isEmpty)
    }

    @Test("A booking under way is still shown")
    func keepsTheCurrentOne() {
        let schedule = schedule(["C1": [0: run(24..<28, "Ana Petrović")]])   // 14:00–15:00

        let mine = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                   today: today, now: TimeOfDay(hour: 14, minute: 20))
        #expect(mine.map(\.space.id) == ["C1"])
    }

    @Test("Days after today follow, in the sheet’s order")
    func laterDays() {
        let schedule = schedule([
            "C2": [1: run(8..<12, "Ana Petrović")],       // the 21st, 10:00–11:00
            "C1": [0: run(40..<44, "Ana Petrović")],      // today, 18:00–19:00
        ])

        let mine = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                   today: today, now: TimeOfDay(hour: 9))
        #expect(mine.map(\.date) == [today, tomorrow])
    }

    @Test("Someone else’s bookings are not mine")
    func ignoresOthers() {
        let schedule = schedule([
            "C1": [0: run(24..<28, "Marko Jurić")],
            "C2": [0: run(24..<28, "Ana Petrović")],
        ])

        let mine = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                   today: today, now: TimeOfDay(hour: 9))
        #expect(mine.map(\.space.id) == ["C2"])
    }

    @Test("Only the chosen floor")
    func honoursFloor() {
        let schedule = schedule([
            "O1": [0: run(20..<24, "Ana Petrović")],      // second floor, earlier
            "C2": [0: run(24..<28, "Ana Petrović")],
        ])
        let firstFloor = Space.all.filter { $0.floor == 1 }

        let mine = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: firstFloor,
                                   today: today, now: TimeOfDay(hour: 9))
        #expect(mine.map(\.space.id) == ["C2"])
    }

    @Test("The list is capped")
    func respectsLimit() {
        let schedule = schedule([
            "C1": [0: run(12..<14, "Ana Petrović")],
            "C2": [0: run(16..<18, "Ana Petrović")],
            "C3": [0: run(20..<22, "Ana Petrović")],
            "C4": [0: run(24..<26, "Ana Petrović")],
        ])

        let mine = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                   today: today, now: TimeOfDay(hour: 9), limit: 2)
        #expect(mine.map(\.space.id) == ["C1", "C2"])
    }

    @Test("A numbered cell is a name of its own, and only it is found")
    func numberedCellsAreTheirOwnNames() {
        // The sheet’s own shape: one cell per slot, `Acme 2`, `Acme 3`, …
        let schedule = schedule(["C4": [0: [24: "Acme 2", 25: "Acme 3", 26: "Acme 4"]]])
        let nine = TimeOfDay(hour: 9)

        // Matching is exact, so the bare company name gathers none of them.
        #expect(Agenda.upcoming(for: "Acme", in: schedule, spaces: Space.all,
                                today: today, now: nine).isEmpty)

        let one = Agenda.upcoming(for: "Acme 3", in: schedule, spaces: Space.all,
                                  today: today, now: nine, limit: 5)
        #expect(one.map(\.start) == [TimeOfDay(hour: 14, minute: 15)])
    }

    @Test("The whole period, past included — the answer to “is this name in the sheet”")
    func allOverThePeriod() {
        let schedule = schedule([
            "C1": [0: run(12..<14, "Ana Petrović")],      // the 18th, morning
            "C2": [1: run(24..<28, "Ana Petrović")],      // the 21st, afternoon
        ])

        // Late on the second day: nothing lies ahead any more…
        let ahead = Agenda.upcoming(for: "Ana Petrović", in: schedule, spaces: Space.all,
                                    today: tomorrow, now: TimeOfDay(hour: 19))
        #expect(ahead.isEmpty)
        // …and yet the name is in the sheet, twice.
        let everything = Agenda.all(for: "Ana Petrović", in: schedule, spaces: Space.all)
        #expect(everything.map(\.date) == [today, tomorrow])
    }

    @Test("A misspelled name is in the sheet nowhere")
    func allFindsNothingForATypo() {
        let schedule = schedule(["C1": [0: run(12..<14, "Ana Petrović")]])
        #expect(Agenda.all(for: "Ana Petrovick", in: schedule, spaces: Space.all).isEmpty)
    }

    @Test("Nothing is mine without a name")
    func emptyNameMatchesNothing() {
        let schedule = schedule(["C1": [0: run(24..<28, "Ana Petrović")]])

        #expect(Agenda.upcoming(for: "", in: schedule, spaces: Space.all,
                                today: today, now: TimeOfDay(hour: 9)).isEmpty)
        #expect(Agenda.upcoming(for: "   ", in: schedule, spaces: Space.all,
                                today: today, now: TimeOfDay(hour: 9)).isEmpty)
    }
}

@Suite("Recognising my name in a cell")
struct NameMatchTests {

    @Test("Case, diacritics and spaces do not matter", arguments: [
        "Ana Petrović", "ana petrović", "ANA PETROVIC", " Ana  Petrovic ",
        "AnaPetrovic", "anapetrović",
    ])
    func folds(cell: String) {
        #expect(Agenda.matches(cell, name: "Ana Petrović"))
    }

    @Test("The space is not a fact about the person: written either way, one name")
    func spacesAreNotADifference() {
        #expect(Agenda.matches("Ana Petrović", name: "AnaPetrovic"))
        #expect(Agenda.matches("AnaPetrovic", name: "Ana Petrović"))
    }

    @Test("A first name alone is not the same name — a namesake is not me")
    func firstNameIsNotEnough() {
        #expect(!Agenda.matches("Ana Petrović", name: "Ana"))
        #expect(!Agenda.matches("Ana", name: "Ana Petrović"))
    }

    @Test("A numbered cell is a name of its own", arguments: [
        "Acme 2", "Acme 17",
    ])
    func numberedSuffixIsADifferentName(cell: String) {
        #expect(!Agenda.matches(cell, name: "Acme"))
        #expect(Agenda.matches(cell, name: cell))
    }

    @Test("Different names do not match", arguments: [
        "Marko Jurić", "Anastasia", "Ana Jurić", "Acme Corp", "Ana Petrovica",
    ])
    func rejectsOthers(cell: String) {
        #expect(!Agenda.matches(cell, name: "Ana Petrović"))
    }

    @Test("Cyrillic ё folds to е")
    func cyrillicFolding() {
        #expect(Agenda.matches("Пётр", name: "Петр"))
    }

    @Test("An empty side never matches")
    func emptySides() {
        #expect(!Agenda.matches("", name: ""))
        #expect(!Agenda.matches("", name: "Ana"))
        #expect(!Agenda.matches("Ana", name: ""))
    }
}

/// One column: the query line, then the rows. `nil` is the line.
@Suite("Walking the list with the arrows")
struct AgendaSelectionTests {
    /// `+1` is ↑, the sign the query field’s stepper uses.
    private let up = 1
    private let down = -1

    @Test("Down from the line enters the list at the first row")
    func entersFromTheLine() {
        #expect(Agenda.selection(from: nil, by: down, count: 3) == 0)
    }

    @Test("Up in the line does nothing — there is nothing above it")
    func nothingAboveTheLine() {
        #expect(Agenda.selection(from: nil, by: up, count: 3) == nil)
    }

    @Test("Down goes down the list, up goes up it")
    func spatialDirection() {
        #expect(Agenda.selection(from: 0, by: down, count: 3) == 1)
        #expect(Agenda.selection(from: 2, by: up, count: 3) == 1)
    }

    @Test("Up from the first row goes back to the line")
    func upReturnsToTheLine() {
        #expect(Agenda.selection(from: 0, by: up, count: 3) == nil)
    }

    @Test("Down on the last row stays there rather than wrapping")
    func downStopsAtTheBottom() {
        #expect(Agenda.selection(from: 2, by: down, count: 3) == 2)
    }

    @Test("An empty list has nothing to enter")
    func emptyList() {
        #expect(Agenda.selection(from: nil, by: down, count: 0) == nil)
        #expect(Agenda.selection(from: nil, by: up, count: 0) == nil)
    }

    @Test("One booking: down lands on it, up comes back")
    func singleBooking() {
        #expect(Agenda.selection(from: nil, by: down, count: 1) == 0)
        #expect(Agenda.selection(from: 0, by: down, count: 1) == 0)
        #expect(Agenda.selection(from: 0, by: up, count: 1) == nil)
    }
}

/// Telling a misspelling from a person who has simply never booked. Both match
/// nothing; only the first has a near-miss sitting in the sheet.
@Suite("Suggesting the name the sheet already carries")
struct ClosestNameTests {
    private func sheet(_ names: [String]) -> Schedule {
        var cells: [String: [[String?]]] = [:]
        for (index, space) in Space.all.enumerated() {
            var slots = [String?](repeating: nil, count: SheetGrid.slotCount)
            if index < names.count {
                slots[24] = names[index]
            }
            cells[space.id] = [slots]
        }
        return Schedule(spaces: Space.all, dates: [today], slots: SheetGrid.slots, cells: cells)
    }

    @Test("A name written without its space is already a match, not a suggestion")
    func spacesNeedNoSuggestion() {
        #expect(Agenda.closestName(to: "AnaPetrovic", in: sheet(["Ana Petrović"])) == nil)
    }

    @Test("One slip in a long name is still the same person")
    func oneTypo() {
        #expect(Agenda.closestName(to: "Ana Petrovich", in: sheet(["Ana Petrović"])) == "Ana Petrović")
    }

    @Test("A name already in the sheet needs no suggestion")
    func exactHolder() {
        #expect(Agenda.closestName(to: "Ana Petrović", in: sheet(["Ana Petrović"])) == nil)
    }

    @Test("Nothing close — the person has simply never booked")
    func noNeighbour() {
        #expect(Agenda.closestName(to: "Nikola Savić", in: sheet(["Ana Petrović", "Marko Jurić"])) == nil)
    }

    @Test("Two letters propose nobody: too short to tell a slip from a name")
    func tooShort() {
        #expect(Agenda.closestName(to: "An", in: sheet(["Ana Petrović"])) == nil)
    }

    @Test("An empty sheet proposes nobody")
    func emptySheet() {
        #expect(Agenda.closestName(to: "Ana Petrović", in: sheet([])) == nil)
    }
}
