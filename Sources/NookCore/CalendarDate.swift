import Foundation

/// A calendar day with no time and no time zone.
///
/// The sheet stores dates as `18/09/2026` and knows nothing about time zones.
/// A `Date` would drag midnight-in-some-zone in here, and with it a day of
/// drift on comparison — so a day is three numbers, exactly as in the source.
public struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a cell from row 3 of a space tab: `18/09/2026` (day/month/year).
    public init?(sheetLabel: String) {
        let parts = sheetLabel.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 3,
              let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]),
              Self.isValid(year: year, month: month, day: day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= daysInMonth[month - 1]
    }

    /// The day `date` falls on in the given zone. The boundary of “calendar
    /// today” is the one place where a time zone has anything to say.
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Same shape as in the source: `18/09/2026`.
    public var description: String {
        String(format: "%02d/%02d/%04d", day, month, year)
    }

    /// Days since 1 January 1970. Hinnant’s algorithm — plain arithmetic, no
    /// `Calendar` and no time zones, which is what keeps this module free of
    /// dependencies.
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                                   // [0, 399]
        let monthShifted = (month + 9) % 12                             // March is zero
        let dayOfYear = (153 * monthShifted + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public init(daysSinceEpoch: Int) {
        let z = daysSinceEpoch + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097                                // [0, 146096]
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthShifted = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthShifted + 2) / 5 + 1
        let month = monthShifted < 10 ? monthShifted + 3 : monthShifted - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: day)
    }

    public func adding(days: Int) -> CalendarDate {
        CalendarDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// 0 is Sunday … 6 is Saturday. 1 January 1970 was a Thursday.
    public var weekdayIndex: Int {
        ((daysSinceEpoch % 7) + 11) % 7
    }

    /// The nearest day with that weekday, not earlier than self.
    ///
    /// “Not earlier than self” because “Friday”, said on a Friday, means today
    /// rather than a week out. The sheet holds ten dates, so every weekday
    /// occurs twice in it; the first one wins.
    public func next(weekday: Int) -> CalendarDate {
        adding(days: ((weekday - weekdayIndex) % 7 + 7) % 7)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
