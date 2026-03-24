import Foundation

public enum RequestValidator {
    public static func validate(_ request: RawBirthRequest) throws {
        try validateSchema(actual: request.schemaVersion, expected: SchemaVersion.rawRequest)
        try validateCoordinates(request.location)
        try validateSupportedYear(from: request.birth.localDateTime)
        if let offset = request.birth.utcOffsetMinutesAtBirth {
            try validateUTCOffset(offset)
        }
    }

    public static func validate(_ request: ResolvedBirthRequest) throws {
        try validateSchema(actual: request.schemaVersion, expected: SchemaVersion.resolvedRequest)
        try validateCoordinates(request.location)
        try validateSupportedYear(from: request.birth.localDateTime)
        try validateUTCOffset(request.birth.utcOffsetMinutesAtBirth)
    }

    public static func validateCoordinates(_ location: BirthLocation) throws {
        guard (-90.0 ... 90.0).contains(location.latitude), (-180.0 ... 180.0).contains(location.longitude) else {
            throw NatalEngineError.invalidCoordinates
        }
    }

    public static func validateSupportedYear(from localDateTime: String) throws {
        guard let year = extractYear(from: localDateTime) else {
            throw NatalEngineError.malformedRequest("localDateTime must start with yyyy-MM-ddTHH:mm[:ss].")
        }

        guard (1900 ... 2150).contains(year) else {
            throw NatalEngineError.invalidBirthDateRange
        }
    }

    public static func validateUTCOffset(_ offsetMinutes: Int) throws {
        guard (-14 * 60 ... 14 * 60).contains(offsetMinutes) else {
            throw NatalEngineError.invalidUTCOffset
        }
    }

    public static func extractYear(from localDateTime: String) -> Int? {
        guard localDateTime.count >= 4 else { return nil }
        let prefix = String(localDateTime.prefix(4))
        return Int(prefix)
    }

    private static func validateSchema(actual: String, expected: String) throws {
        guard actual == expected else {
            throw NatalEngineError.invalidSchemaVersion(expected: expected, actual: actual)
        }
    }
}
