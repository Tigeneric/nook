import Foundation

/// Every space over the whole period the sheet covers.
///
/// A booking is not an entity here, because it is not one in the source
/// either — there is only a name in a cell. Adjacent cells are merged later,
/// at draw time (`blocks(space:dateIndex:)`), and only when the names match.
public struct Schedule: Sendable {
    public let spaces: [Space]
    public let dates: [CalendarDate]
    public let slots: [TimeOfDay]
    /// Who holds the cell, or `nil`. Indexing: `cells[space.id]![dateIndex][slotIndex]`.
    public let cells: [String: [[String?]]]

    public init(spaces: [Space], dates: [CalendarDate], slots: [TimeOfDay], cells: [String: [[String?]]]) {
        self.spaces = spaces
        self.dates = dates
        self.slots = slots
        self.cells = cells
    }

    public func dateIndex(of date: CalendarDate) -> Int? {
        dates.firstIndex(of: date)
    }

    public func occupant(space: Space, dateIndex: Int, slotIndex: Int) -> String? {
        guard let byDate = cells[space.id],
              byDate.indices.contains(dateIndex),
              byDate[dateIndex].indices.contains(slotIndex)
        else { return nil }
        return byDate[dateIndex][slotIndex]
    }

    public func isFree(space: Space, dateIndex: Int, slotIndex: Int) -> Bool {
        guard let byDate = cells[space.id],
              byDate.indices.contains(dateIndex),
              byDate[dateIndex].indices.contains(slotIndex)
        else { return false }
        return byDate[dateIndex][slotIndex] == nil
    }

    /// A run of adjacent cells holding the same name — the unit of drawing.
    public struct Block: Hashable, Sendable {
        public let name: String
        public let startSlot: Int
        public let slotCount: Int

        public var endSlot: Int { startSlot + slotCount }
    }

    /// Occupied blocks of a space on a date.
    ///
    /// **Only identical** adjacent names merge. Different names in a row are
    /// different bookings: a company booking five consecutive slots writes
    /// `Acme 2`, `Acme 3`, … one per slot, and that is five bookings rather
    /// than one long one. Merging them would misstate the duration.
    public func blocks(space: Space, dateIndex: Int) -> [Block] {
        var result: [Block] = []
        var current: (name: String, start: Int)?

        for slotIndex in slots.indices {
            let name = occupant(space: space, dateIndex: dateIndex, slotIndex: slotIndex)
            switch (current, name) {
            case let (run?, name?) where run.name == name:
                continue
            case let (run?, _):
                result.append(Block(name: run.name, startSlot: run.start, slotCount: slotIndex - run.start))
                current = name.map { (name: $0, start: slotIndex) }
            case let (nil, name?):
                current = (name: name, start: slotIndex)
            case (nil, nil):
                continue
            }
        }
        if let run = current {
            result.append(Block(name: run.name, startSlot: run.start, slotCount: slots.count - run.start))
        }
        return result
    }
}
