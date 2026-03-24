import Foundation

public struct BirthLocation: Codable, Sendable, Equatable {
    public let city: String?
    public let latitude: Double
    public let longitude: Double

    public init(city: String?, latitude: Double, longitude: Double) {
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct BirthSubject: Codable, Sendable, Equatable {
    public let gender: String?

    public init(gender: String?) {
        self.gender = gender
    }
}

public struct RawBirth: Codable, Sendable, Equatable {
    public let localDateTime: String
    public let timeZoneId: String?
    public let utcOffsetMinutesAtBirth: Int?
    public let ambiguityPolicy: AmbiguityPolicy?
    public let timePrecision: BirthTimePrecision?

    public init(
        localDateTime: String,
        timeZoneId: String? = nil,
        utcOffsetMinutesAtBirth: Int? = nil,
        ambiguityPolicy: AmbiguityPolicy? = nil,
        timePrecision: BirthTimePrecision? = nil
    ) {
        self.localDateTime = localDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.ambiguityPolicy = ambiguityPolicy
        self.timePrecision = timePrecision
    }
}

public struct ResolvedBirth: Codable, Sendable, Equatable {
    public let localDateTime: String
    public let timeZoneId: String
    public let utcOffsetMinutesAtBirth: Int
    public let ambiguityPolicy: AmbiguityPolicy
    public let timePrecision: BirthTimePrecision

    public init(
        localDateTime: String,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        ambiguityPolicy: AmbiguityPolicy,
        timePrecision: BirthTimePrecision
    ) {
        self.localDateTime = localDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.ambiguityPolicy = ambiguityPolicy
        self.timePrecision = timePrecision
    }
}

public struct RawBirthRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let birth: RawBirth
    public let location: BirthLocation
    public let subject: BirthSubject
    public let profile: NatalProfile

    public init(
        schemaVersion: String = SchemaVersion.rawRequest,
        birth: RawBirth,
        location: BirthLocation,
        subject: BirthSubject,
        profile: NatalProfile
    ) {
        self.schemaVersion = schemaVersion
        self.birth = birth
        self.location = location
        self.subject = subject
        self.profile = profile
    }
}

public struct ResolvedBirthRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let birth: ResolvedBirth
    public let location: BirthLocation
    public let subject: BirthSubject
    public let profile: NatalProfile

    public init(
        schemaVersion: String = SchemaVersion.resolvedRequest,
        birth: ResolvedBirth,
        location: BirthLocation,
        subject: BirthSubject,
        profile: NatalProfile
    ) {
        self.schemaVersion = schemaVersion
        self.birth = birth
        self.location = location
        self.subject = subject
        self.profile = profile
    }
}
