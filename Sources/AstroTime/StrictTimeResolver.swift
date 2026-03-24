import Foundation
import AstroSchemas

public protocol BirthTimeResolving: Sendable {
    func resolve(_ birth: RawBirth) throws -> ResolvedTime
}

public struct StrictTimeResolver: BirthTimeResolving {
    public init() {}

    public func resolve(_ birth: ResolvedBirth) throws -> ResolvedTime {
        try resolve(
            RawBirth(
                localDateTime: birth.localDateTime,
                timeZoneId: birth.timeZoneId,
                utcOffsetMinutesAtBirth: birth.utcOffsetMinutesAtBirth,
                ambiguityPolicy: birth.ambiguityPolicy,
                timePrecision: birth.timePrecision
            )
        )
    }

    public func resolve(_ birth: RawBirth) throws -> ResolvedTime {
        try RequestValidator.validateSupportedYear(from: birth.localDateTime)
        if let offset = birth.utcOffsetMinutesAtBirth {
            try RequestValidator.validateUTCOffset(offset)
        }

        let localDateTime = try LocalCivilDateTime(parsing: birth.localDateTime)
        let ambiguityPolicy = birth.ambiguityPolicy ?? .earlier
        let timePrecision = birth.timePrecision ?? .minute

        // A supplied numeric offset wins over zone rules on purpose: downstream
        // stages need a stable UTC instant more than a historically "correct"
        // timezone label, and tests rely on callers being able to override tzdb.
        if let offset = birth.utcOffsetMinutesAtBirth {
            return try resolveWithUTCOffset(
                localDateTime,
                offsetMinutes: offset,
                timeZoneId: birth.timeZoneId,
                ambiguityPolicy: ambiguityPolicy,
                timePrecision: timePrecision,
                originalLocalDateTime: birth.localDateTime
            )
        }

        if let timeZoneId = birth.timeZoneId {
            return try resolveWithTimeZoneID(
                localDateTime,
                timeZoneId: timeZoneId,
                ambiguityPolicy: ambiguityPolicy,
                timePrecision: timePrecision,
                originalLocalDateTime: birth.localDateTime
            )
        }

        throw NatalEngineError.timezoneUnresolved
    }

    private func resolveWithUTCOffset(
        _ localDateTime: LocalCivilDateTime,
        offsetMinutes: Int,
        timeZoneId: String?,
        ambiguityPolicy: AmbiguityPolicy,
        timePrecision: BirthTimePrecision,
        originalLocalDateTime: String
    ) throws -> ResolvedTime {
        guard let timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) else {
            throw NatalEngineError.invalidUTCOffset
        }

        guard let date = localDateTime.validatedDate(in: timeZone) else {
            throw NatalEngineError.malformedRequest("localDateTime contains an invalid calendar date.")
        }

        return makeResolvedTime(
            originalLocalDateTime: originalLocalDateTime,
            date: date,
            timeZoneId: timeZoneId ?? Self.syntheticTimeZoneID(offsetMinutes: offsetMinutes),
            utcOffsetMinutesAtBirth: offsetMinutes,
            ambiguityPolicy: ambiguityPolicy,
            timePrecision: timePrecision
        )
    }

    private func resolveWithTimeZoneID(
        _ localDateTime: LocalCivilDateTime,
        timeZoneId: String,
        ambiguityPolicy: AmbiguityPolicy,
        timePrecision: BirthTimePrecision,
        originalLocalDateTime: String
    ) throws -> ResolvedTime {
        guard let timeZone = TimeZone(identifier: timeZoneId) else {
            throw NatalEngineError.timezoneUnresolved
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let matchingComponents = localDateTime.matchingComponents(in: timeZone)
        let searchStartDate = localDateTime.searchStartDate()

        let earlierMatch = calendar.nextDate(
            after: searchStartDate,
            matching: matchingComponents,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        )
        let laterMatch = calendar.nextDate(
            after: searchStartDate,
            matching: matchingComponents,
            matchingPolicy: .strict,
            repeatedTimePolicy: .last,
            direction: .forward
        )

        // The engine preserves DST fold/gap behavior at the schema boundary so every
        // later module receives a single UTC instant plus the policy that produced
        // it, instead of trying to reinterpret ambiguous wall-clock input again.
        guard earlierMatch != nil || laterMatch != nil else {
            throw NatalEngineError.malformedRequest("localDateTime falls in a daylight-saving gap.")
        }

        let resolvedDate: Date
        if let earlierMatch, let laterMatch, earlierMatch != laterMatch {
            switch ambiguityPolicy {
            case .earlier:
                resolvedDate = earlierMatch
            case .later:
                resolvedDate = laterMatch
            case .reject:
                throw NatalEngineError.ambiguousLocalTime
            }
        } else if let earlierMatch {
            resolvedDate = earlierMatch
        } else if let laterMatch {
            resolvedDate = laterMatch
        } else {
            throw NatalEngineError.timezoneUnresolved
        }

        let offsetSeconds = timeZone.secondsFromGMT(for: resolvedDate)
        guard offsetSeconds % 60 == 0 else {
            throw NatalEngineError.malformedRequest("timeZoneId resolves to a sub-minute historical offset that is unsupported.")
        }

        return makeResolvedTime(
            originalLocalDateTime: originalLocalDateTime,
            date: resolvedDate,
            timeZoneId: timeZoneId,
            utcOffsetMinutesAtBirth: offsetSeconds / 60,
            ambiguityPolicy: ambiguityPolicy,
            timePrecision: timePrecision
        )
    }

    private func makeResolvedTime(
        originalLocalDateTime: String,
        date: Date,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        ambiguityPolicy: AmbiguityPolicy,
        timePrecision: BirthTimePrecision
    ) -> ResolvedTime {
        let julianDayUTC = Self.julianDayUTC(for: date)
        let deltaTSeconds = DeltaT.seconds(forUTCDate: date)
        let julianDayTT = julianDayUTC + deltaTSeconds / 86_400.0
        let julianDayTDB = julianDayTT + Self.tdbOffsetSeconds(fromTTJulianDay: julianDayTT) / 86_400.0

        // Every chart stage consumes this same UTC -> TT -> TDB chain. If the time
        // model changes, body positions, house timing, warnings, and regression
        // baselines all move together.
        return ResolvedTime(
            localDateTime: originalLocalDateTime,
            timeZoneId: timeZoneId,
            utcOffsetMinutesAtBirth: utcOffsetMinutesAtBirth,
            ambiguityPolicy: ambiguityPolicy,
            timePrecision: timePrecision,
            utc: Self.utcString(from: date),
            julianDayUTC: julianDayUTC,
            julianDayTT: julianDayTT,
            julianDayTDB: julianDayTDB,
            deltaTSeconds: deltaTSeconds
        )
    }

    private static func julianDayUTC(for date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }

    private static func tdbOffsetSeconds(fromTTJulianDay julianDayTT: Double) -> Double {
        let centuriesSinceJ2000 = (julianDayTT - 2_451_545.0) / 36_525.0
        let meanAnomalyDegrees = 357.53 + 35_999.05034 * centuriesSinceJ2000
        let meanAnomalyRadians = meanAnomalyDegrees * .pi / 180.0
        return 0.001657 * sin(meanAnomalyRadians) + 0.00001385 * sin(2.0 * meanAnomalyRadians)
    }

    private static func utcString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func syntheticTimeZoneID(offsetMinutes: Int) -> String {
        let sign = offsetMinutes >= 0 ? "+" : "-"
        let absolute = abs(offsetMinutes)
        let hours = absolute / 60
        let minutes = absolute % 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }
}
