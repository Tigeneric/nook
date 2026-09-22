import Foundation

public enum SpaceKind: String, Hashable, Sendable {
    case booth
    case room
}

/// A space in the coworking.
public struct Space: Identifiable, Hashable, Sendable {
    /// Stable key used by the app (`C1`, `MR1`), not the tab title.
    public let id: String
    /// What a person sees in the column header.
    public let title: String
    public let kind: SpaceKind
    public let floor: Int
    /// How the source names this space — a tab id, a calendar id, a row key.
    /// Opaque here on purpose: the core must not know what kind of source is
    /// on the other side.
    public let sourceKey: String

    public init(id: String, title: String, kind: SpaceKind, floor: Int, sourceKey: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.floor = floor
        self.sourceKey = sourceKey
    }
}

extension Space {
    /// The catalogue in grid-column order: first floor first, second floor after.
    ///
    /// Spaces are identified **by `sourceKey`**, never by their title. In the
    /// sheet this project grew from, three tab titles end in a trailing space,
    /// one carries a typo, and the word order differs between views
    /// (`C1 Phone Booth` in one place, `Phone Booth C1` in another) — matching
    /// on text would break on three tabs out of eight.
    ///
    /// The keys below belong to one specific coworking. Point Nook at another
    /// one and this is the list to edit.
    public static let all: [Space] = [
        Space(id: "C1",  title: "C1",        kind: .booth, floor: 1, sourceKey: "1248761150"),
        Space(id: "C2",  title: "C2",        kind: .booth, floor: 1, sourceKey: "1843715115"),
        Space(id: "C3",  title: "C3",        kind: .booth, floor: 1, sourceKey: "1961476476"),
        Space(id: "C4",  title: "C4",        kind: .booth, floor: 1, sourceKey: "629732264"),
        Space(id: "MR1", title: "Meeting 1", kind: .room,  floor: 1, sourceKey: "1088751692"),
        Space(id: "O1",  title: "O1",        kind: .booth, floor: 2, sourceKey: "846893928"),
        Space(id: "O2",  title: "O2",        kind: .booth, floor: 2, sourceKey: "931704638"),
        Space(id: "MR2", title: "Meeting 2", kind: .room,  floor: 2, sourceKey: "1437227910"),
    ]

    public static func named(_ id: String) -> Space? {
        all.first { $0.id == id }
    }
}
