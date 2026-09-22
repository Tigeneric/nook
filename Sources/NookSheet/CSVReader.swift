import Foundation

/// Parses CSV into rows of cells.
///
/// Hand-written rather than built on `split(separator:)` for two reasons:
/// names in cells may contain commas inside quotes, and the export of a space
/// tab returns 52 newlines for 53 rows of data — the last row has none.
/// Counting rows by separators would be wrong.
public enum CSVReader {
    public enum ParseError: Error, Equatable, Sendable {
        case unexpectedQuote
        case unexpectedCharacterAfterQuote
        case unclosedQuote
    }

    public static func rows(from text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var closedQuote = false
        var iterator = text.makeIterator()
        var pending: Character?
        var sawAnything = false

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            sawAnything = true

            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")     // an escaped quote
                    } else {
                        inQuotes = false
                        closedQuote = true
                        pending = next
                        }
                    } else {
                        inQuotes = false
                        closedQuote = true
                    }
                } else if character.isNewline {
                    field.append("\n")             // normalise newlines inside quotes
                } else {
                    field.append(character)
                }
                continue
            }

            if closedQuote {
                switch character {
                case ",":
                    endField()
                    closedQuote = false
                case let character where character.isNewline:
                    endRow()
                    closedQuote = false
                default:
                    throw ParseError.unexpectedCharacterAfterQuote
                }
                continue
            }

            switch character {
            case "\"":
                guard field.isEmpty else { throw ParseError.unexpectedQuote }
                inQuotes = true
            case ",":
                endField()
            // In Swift `\r\n` is a single Character, not two: comparing against
            // "\n" would miss it.
            case let character where character.isNewline:
                endRow()
            default:
                field.append(character)
            }
        }

        guard !inQuotes else { throw ParseError.unclosedQuote }

        // The last row arrives without a closing newline — close it here.
        if sawAnything, closedQuote || !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
