import Foundation
import AstroSchemas

struct LocalCivilDateTime: Sendable, Equatable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    init(parsing value: String) throws {
        let sections = value.split(separator: "T", omittingEmptySubsequences: false)
        guard sections.count == 2 else {
            throw NatalEngineError.malformedRequest("localDateTime must use yyyy-MM-ddTHH:mm[:ss].")
        }

        let dateParts = sections[0].split(separator: "-", omittingEmptySubsequences: false)
        let timeParts = sections[1].split(separator: ":", omittingEmptySubsequences: false)

        guard dateParts.count == 3, (timeParts.count == 2 || timeParts.count == 3) else {
            throw NatalEngineError.malformedRequest("localDateTime must use yyyy-MM-ddTHH:mm[:ss].")
        }

        guard
            let year = Int(dateParts[0]),
            let month = Int(dateParts[1]),
            let day = Int(dateParts[2]),
            let hour = Int(timeParts[0]),
            let minute = Int(timeParts[1]),
            let second = timeParts.count == 3 ? Int(timeParts[2]) : 0
        else {
            throw NatalEngineError.malformedRequest("localDateTime must use yyyy-MM-ddTHH:mm[:ss].")
        }

        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second

        guard validatedDate(in: TimeZone(secondsFromGMT: 0)!) != nil else {
            throw NatalEngineError.malformedRequest("localDateTime contains an invalid calendar date.")
        }
    }

    func matchingComponents(in timeZone: TimeZone) -> DateComponents {
        DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    }

    func validatedDate(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = matchingComponents(in: timeZone)
        guard let date = calendar.date(from: components) else {
            return nil
        }

        let roundTripped = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        guard
            roundTripped.year == year,
            roundTripped.month == month,
            roundTripped.day == day,
            roundTripped.hour == hour,
            roundTripped.minute == minute,
            roundTripped.second == second
        else {
            return nil
        }

        return date
    }

    func searchStartDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let start = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
        ) ?? .distantPast

        return start.addingTimeInterval(-86_400)
    }
}
