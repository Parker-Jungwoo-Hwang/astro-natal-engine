import Foundation

public enum NatalEngineError: Error, Sendable, Equatable {
    case engineNotPrepared
    case missingRequiredPack(String)
    case kernelOutOfRange
    case timezoneUnresolved
    case ambiguousLocalTime
    case invalidCoordinates
    case unsupportedProfile
    case dataPackChecksumMismatch(String)
    case invalidSchemaVersion(expected: String, actual: String)
    case invalidBirthDateRange
    case invalidUTCOffset
    case malformedRequest(String)
    case featureNotImplemented(String)
    case networkFailure(String)
    case fileSystemFailure(String)
    case manifestInvalid(String)
}

extension NatalEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .engineNotPrepared:
            return "NatalChartEngine.prepare() must complete before generate() is called."
        case let .missingRequiredPack(packID):
            return "Missing required data pack: \(packID)."
        case .kernelOutOfRange:
            return "The requested birth date is outside the supported kernel range."
        case .timezoneUnresolved:
            return "The birth time could not be resolved to a stable UTC offset."
        case .ambiguousLocalTime:
            return "The local birth time is ambiguous and requires an explicit ambiguity policy."
        case .invalidCoordinates:
            return "Latitude or longitude is out of range."
        case .unsupportedProfile:
            return "The requested natal profile is not supported."
        case let .dataPackChecksumMismatch(packID):
            return "Checksum verification failed for data pack \(packID)."
        case let .invalidSchemaVersion(expected, actual):
            return "Invalid schema version. Expected \(expected), got \(actual)."
        case .invalidBirthDateRange:
            return "Birth date must be between 1900-01-01 and 2150-12-31."
        case .invalidUTCOffset:
            return "UTC offset is outside the valid range."
        case let .malformedRequest(message):
            return "Malformed request: \(message)"
        case let .featureNotImplemented(feature):
            return "Feature not implemented yet: \(feature)."
        case let .networkFailure(message):
            return "Network failure: \(message)"
        case let .fileSystemFailure(message):
            return "File system failure: \(message)"
        case let .manifestInvalid(message):
            return "Manifest is invalid: \(message)"
        }
    }
}
