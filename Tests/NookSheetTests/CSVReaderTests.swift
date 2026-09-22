import Testing
@testable import NookSheet

@Suite("CSV parsing")
struct CSVReaderTests {

    @Test("A last line without a newline is not lost")
    func trailingLineWithoutNewline() throws {
        // The tab export returns 52 newlines for 53 rows of data.
        let rows = try CSVReader.rows(from: "a,b\nc,d\ne,f")
        #expect(rows.count == 3)
        #expect(rows.last == ["e", "f"])
    }

    @Test("A trailing newline does not create an extra row")
    func trailingNewline() throws {
        #expect(try CSVReader.rows(from: "a,b\nc,d\n").count == 2)
    }

    @Test("A comma inside quotes is part of the name")
    func quotedComma() throws {
        let rows = try CSVReader.rows(from: "8:00,\"Orion Project Inc., Ltd\",\n")
        #expect(rows == [["8:00", "Orion Project Inc., Ltd", ""]])
    }

    @Test("A doubled quote inside a field")
    func escapedQuote() throws {
        #expect(try CSVReader.rows(from: "\"a\"\"b\"") == [["a\"b"]])
    }

    @Test("CRLF leaves no debris at the end of a field")
    func crlf() throws {
        #expect(try CSVReader.rows(from: "a,b\r\nc,d\r\n") == [["a", "b"], ["c", "d"]])
    }

    @Test("Empty cells keep their position")
    func emptyFields() throws {
        #expect(try CSVReader.rows(from: "8:00,,Ana,\n") == [["8:00", "", "Ana", ""]])
    }

    @Test("Empty text means zero rows")
    func empty() throws {
        #expect(try CSVReader.rows(from: "").isEmpty)
    }

    @Test("A quoted empty field is still a row")
    func quotedEmptyField() throws {
        #expect(try CSVReader.rows(from: "\"\"") == [[""]])
    }

    @Test("Malformed quoting is rejected", arguments: ["\"unclosed", "prefix\"quoted\"", "\"closed\"tail"])
    func malformedQuoting(text: String) {
        #expect(throws: CSVReader.ParseError.self) {
            try CSVReader.rows(from: text)
        }
    }
}
