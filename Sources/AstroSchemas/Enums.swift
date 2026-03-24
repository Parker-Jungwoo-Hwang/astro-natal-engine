import Foundation

public enum NatalProfile: String, Codable, Sendable, CaseIterable {
    case standardNatal
    case enhancedNatal
}

public enum AmbiguityPolicy: String, Codable, Sendable, CaseIterable {
    case earlier
    case later
    case reject
}

public enum BirthTimePrecision: String, Codable, Sendable, CaseIterable {
    case day
    case hour
    case minute
    case second
    case unknown
}

public enum HouseSystem: String, Codable, Sendable, CaseIterable {
    case placidus
    case equal
}

public enum BodyID: String, Codable, Sendable, CaseIterable, Hashable {
    case sun
    case moon
    case mercury
    case venus
    case mars
    case jupiter
    case saturn
    case uranus
    case neptune
    case pluto
}

public enum AngleID: String, Codable, Sendable, CaseIterable {
    case asc
    case mc
    case ic
    case dc
}

public enum AspectType: String, Codable, Sendable, CaseIterable {
    case conjunction
    case opposition
    case trine
    case square
    case sextile
}

public enum ZodiacSign: String, Codable, Sendable, CaseIterable {
    case aries = "Aries"
    case taurus = "Taurus"
    case gemini = "Gemini"
    case cancer = "Cancer"
    case leo = "Leo"
    case virgo = "Virgo"
    case libra = "Libra"
    case scorpio = "Scorpio"
    case sagittarius = "Sagittarius"
    case capricorn = "Capricorn"
    case aquarius = "Aquarius"
    case pisces = "Pisces"
}

public enum NatalWarningCode: String, Codable, Sendable, CaseIterable {
    case pre1970TimezoneBestEffort = "pre1970_timezone_best_effort"
    case standardModeWithoutEOP = "standard_mode_without_eop"
    case placidusFallbackApplied = "placidus_fallback_applied"
    case birthTimePrecisionLow = "birth_time_precision_low"
    case hostProvidedOffsetOverrodeTZDB = "host_provided_offset_overrode_tzdb"
}
