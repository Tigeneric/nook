import Foundation

/// Serbian is digraphic: both scripts are in live use, and people type in
/// whichever one their system is set to. For parsing that is two vocabularies;
/// for a person it is one language.
public enum QueryLanguage: String, Sendable, CaseIterable {
    case en, ru
    case srLatin = "sr-Latn"
    case srCyrillic = "sr-Cyrl"

    /// The language the app speaks when it writes a request itself — a hint
    /// in the empty field, a day put back by an arrow. Taken from the
    /// interface’s preferred localisations.
    ///
    /// Parsing accepts all four whatever the interface is, because a person
    /// may type `fri` in a Russian window. A hint is the other direction: the
    /// app talking, and it talks in the language the rest of the window is in.
    ///
    /// Serbian arrives as `sr-Latn` or as a bare `sr`, and the scripts are
    /// not interchangeable inside one line, so the Latin one is matched before
    /// the bare prefix rather than after it.
    public static func interface(_ localizations: [String]) -> QueryLanguage {
        for identifier in localizations {
            let code = identifier.lowercased()
            if code.hasPrefix("ru") { return .ru }
            if code.hasPrefix("sr-latn") { return .srLatin }
            if code.hasPrefix("sr") { return .srCyrillic }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// The words of one language. Weekdays run from Sunday, as in
/// `CalendarDate.weekdayIndex`.
struct QueryVocabulary {
    let language: QueryLanguage
    let shortWeekdays: [String]
    let fullWeekdays: [String]
    let today: String
    let tomorrow: String
    let dayAfterTomorrow: String
    let now: [String]

    /// Parsing does not ask the system what language it is in: a person may
    /// type `fri` in a Russian interface, and that has to work.
    static let all: [QueryVocabulary] = [
        QueryVocabulary(
            language: .en,
            shortWeekdays: ["sun", "mon", "tue", "wed", "thu", "fri", "sat"],
            fullWeekdays: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
            today: "today",
            tomorrow: "tomorrow",
            dayAfterTomorrow: "overmorrow",
            now: ["now"]
        ),
        QueryVocabulary(
            language: .ru,
            shortWeekdays: ["вс", "пн", "вт", "ср", "чт", "пт", "сб"],
            fullWeekdays: ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"],
            today: "сегодня",
            tomorrow: "завтра",
            dayAfterTomorrow: "послезавтра",
            now: ["сейчас"]
        ),
        // Serbian in Latin script: the one used in business, IT and online.
        // Forms without diacritics (`cet`) are accepted alongside `čet` —
        // they are typed more often.
        QueryVocabulary(
            language: .srLatin,
            shortWeekdays: ["ned", "pon", "uto", "sre", "čet", "pet", "sub"],
            fullWeekdays: ["nedelja", "ponedeljak", "utorak", "sreda", "četvrtak", "petak", "subota"],
            today: "danas",
            tomorrow: "sutra",
            dayAfterTomorrow: "prekosutra",
            now: ["sad", "sada"]
        ),
        // Serbian in Cyrillic: the official script, and what a system set to
        // Serbian uses by default.
        QueryVocabulary(
            language: .srCyrillic,
            shortWeekdays: ["нед", "пон", "уто", "сре", "чет", "пет", "суб"],
            fullWeekdays: ["недеља", "понедељак", "уторак", "среда", "четвртак", "петак", "субота"],
            today: "данас",
            tomorrow: "сутра",
            dayAfterTomorrow: "прекосутра",
            now: ["сад", "сада"]
        ),
    ]

    /// Words with diacritics stripped — Serbian `čet` is also typed as `cet`.
    var plainShortWeekdays: [String] {
        shortWeekdays.map { $0.folding(options: .diacriticInsensitive, locale: nil) }
    }

    var plainFullWeekdays: [String] {
        fullWeekdays.map { $0.folding(options: .diacriticInsensitive, locale: nil) }
    }

    /// Every word of the language except weekdays — used to tell which
    /// language a token came from.
    var dayWords: [String] {
        [today, tomorrow, dayAfterTomorrow]
    }
}
