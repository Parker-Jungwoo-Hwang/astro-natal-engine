import Foundation

enum DeltaT {
    static func seconds(forUTCDate date: Date) -> Double {
        let year = decimalYear(forUTCDate: date)

        switch year {
        case 1900..<1920:
            let t = year - 1900.0
            return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * t * t * t - 0.000197 * t * t * t * t
        case 1920..<1941:
            let t = year - 1920.0
            return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * t * t * t
        case 1941..<1961:
            let t = year - 1950.0
            return 29.07 + 0.407 * t - (t * t) / 233.0 + (t * t * t) / 2547.0
        case 1961..<1986:
            let t = year - 1975.0
            return 45.45 + 1.067 * t - (t * t) / 260.0 - (t * t * t) / 718.0
        case 1986..<2005:
            let t = year - 2000.0
            return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t + 0.000651814 * t * t * t * t + 0.00002373599 * t * t * t * t * t
        case 2005..<2050:
            let t = year - 2000.0
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        case 2050...2150:
            let u = (year - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u - 0.5628 * (2150.0 - year)
        default:
            let u = (year - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u
        }
    }

    private static func decimalYear(forUTCDate date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let year = calendar.component(.year, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: date)

        let secondsIntoDay =
            Double(timeOfDay.hour ?? 0) * 3_600 +
            Double(timeOfDay.minute ?? 0) * 60 +
            Double(timeOfDay.second ?? 0)

        let fractionalDay = secondsIntoDay / 86_400.0
        return Double(year) + (Double(dayOfYear - 1) + fractionalDay) / Double(daysInYear)
    }
}
