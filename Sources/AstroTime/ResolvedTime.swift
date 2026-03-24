import Foundation
import AstroSchemas

public struct ResolvedTime: Codable, Sendable, Equatable {
    public let localDateTime: String
    public let timeZoneId: String
    public let utcOffsetMinutesAtBirth: Int
    public let ambiguityPolicy: AmbiguityPolicy
    public let timePrecision: BirthTimePrecision
    public let utc: String
    public let julianDayUTC: Double
    public let julianDayTT: Double
    public let julianDayTDB: Double
    public let deltaTSeconds: Double
    public let dut1Seconds: Double?

    public init(
        localDateTime: String,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        ambiguityPolicy: AmbiguityPolicy,
        timePrecision: BirthTimePrecision,
        utc: String,
        julianDayUTC: Double,
        julianDayTT: Double,
        julianDayTDB: Double,
        deltaTSeconds: Double,
        dut1Seconds: Double? = nil
    ) {
        self.localDateTime = localDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.ambiguityPolicy = ambiguityPolicy
        self.timePrecision = timePrecision
        self.utc = utc
        self.julianDayUTC = julianDayUTC
        self.julianDayTT = julianDayTT
        self.julianDayTDB = julianDayTDB
        self.deltaTSeconds = deltaTSeconds
        self.dut1Seconds = dut1Seconds
    }
}
