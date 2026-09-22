import Testing
@testable import NookSheet

@Suite("Reading the roster tab")
struct RosterParserTests {
    @Test("Names come back in the tab's order, without the header")
    func names() throws {
        let csv = """
        Member Name
        Ana Petrović
        AnaPetrovic
        Marko Jurić
        """
        #expect(try RosterParser.parse(csv) == ["Ana Petrović", "AnaPetrovic", "Marko Jurić"])
    }

    /// The export pads its rows out well past the last name, and the
    /// validation range runs to row 991.
    @Test("The padding below the last name is dropped")
    func padding() throws {
        let csv = "Member Name\nAna Petrović\n\n\n   \n"
        #expect(try RosterParser.parse(csv) == ["Ana Petrović"])
    }

    @Test("Surrounding spaces are not part of a name")
    func trimmed() throws {
        #expect(try RosterParser.parse("Member Name\n  Ana Petrović  ") == ["Ana Petrović"])
    }

    @Test("Only the first column is read")
    func firstColumnOnly() throws {
        #expect(try RosterParser.parse("Member Name,Floor\nAna Petrović,1") == ["Ana Petrović"])
    }

    @Test("A tab holding only its header is an empty roster")
    func headerOnly() throws {
        #expect(try RosterParser.parse("Member Name") == [])
    }

    @Test("An empty export is an empty roster")
    func empty() throws {
        #expect(try RosterParser.parse("") == [])
    }
}
