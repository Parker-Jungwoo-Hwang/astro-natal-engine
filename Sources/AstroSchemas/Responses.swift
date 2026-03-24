import Foundation

public struct EngineDataVersions: Codable, Sendable, Equatable {
    public let ephemeris: String
    public let timeCore: String
    public let tzdb: String?
    public let eop: String?

    public init(ephemeris: String, timeCore: String, tzdb: String? = nil, eop: String? = nil) {
        self.ephemeris = ephemeris
        self.timeCore = timeCore
        self.tzdb = tzdb
        self.eop = eop
    }
}

public struct InputEcho: Codable, Sendable, Equatable {
    public let birthLocalDateTime: String
    public let timeZoneId: String
    public let utcOffsetMinutesAtBirth: Int
    public let latitude: Double
    public let longitude: Double
    public let gender: String?

    public init(
        birthLocalDateTime: String,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        latitude: Double,
        longitude: Double,
        gender: String?
    ) {
        self.birthLocalDateTime = birthLocalDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.latitude = latitude
        self.longitude = longitude
        self.gender = gender
    }
}

public struct NatalResponseTimes: Codable, Sendable, Equatable {
    public let utc: String
    public let julianDayUTC: Double
    public let julianDayTT: Double
    public let julianDayTDB: Double?
    public let deltaTSeconds: Double
    public let dut1Seconds: Double?

    public init(
        utc: String,
        julianDayUTC: Double,
        julianDayTT: Double,
        julianDayTDB: Double? = nil,
        deltaTSeconds: Double,
        dut1Seconds: Double? = nil
    ) {
        self.utc = utc
        self.julianDayUTC = julianDayUTC
        self.julianDayTT = julianDayTT
        self.julianDayTDB = julianDayTDB
        self.deltaTSeconds = deltaTSeconds
        self.dut1Seconds = dut1Seconds
    }
}

public struct AnglesResponse: Codable, Sendable, Equatable {
    public let asc: Double
    public let mc: Double
    public let ic: Double
    public let dc: Double

    public init(asc: Double, mc: Double, ic: Double, dc: Double) {
        self.asc = asc
        self.mc = mc
        self.ic = ic
        self.dc = dc
    }

    public static let zero = AnglesResponse(asc: 0, mc: 0, ic: 0, dc: 0)
}

public struct HousesResponse: Codable, Sendable, Equatable {
    public let system: HouseSystem
    public let cusps: [Double]

    public init(system: HouseSystem, cusps: [Double]) {
        self.system = system
        self.cusps = cusps
    }

    public static let empty = HousesResponse(system: .placidus, cusps: Array(repeating: 0, count: 12))
}

public struct BodyPosition: Codable, Sendable, Equatable {
    public let longitude: Double
    public let latitude: Double
    public let speedLongitude: Double
    public let retrograde: Bool
    public let sign: ZodiacSign
    public let house: Int

    public init(
        longitude: Double,
        latitude: Double,
        speedLongitude: Double,
        retrograde: Bool,
        sign: ZodiacSign,
        house: Int
    ) {
        self.longitude = longitude
        self.latitude = latitude
        self.speedLongitude = speedLongitude
        self.retrograde = retrograde
        self.sign = sign
        self.house = house
    }
}

public struct BodiesResponse: Codable, Sendable, Equatable {
    public var sun: BodyPosition?
    public var moon: BodyPosition?
    public var mercury: BodyPosition?
    public var venus: BodyPosition?
    public var mars: BodyPosition?
    public var jupiter: BodyPosition?
    public var saturn: BodyPosition?
    public var uranus: BodyPosition?
    public var neptune: BodyPosition?
    public var pluto: BodyPosition?

    public init(
        sun: BodyPosition? = nil,
        moon: BodyPosition? = nil,
        mercury: BodyPosition? = nil,
        venus: BodyPosition? = nil,
        mars: BodyPosition? = nil,
        jupiter: BodyPosition? = nil,
        saturn: BodyPosition? = nil,
        uranus: BodyPosition? = nil,
        neptune: BodyPosition? = nil,
        pluto: BodyPosition? = nil
    ) {
        self.sun = sun
        self.moon = moon
        self.mercury = mercury
        self.venus = venus
        self.mars = mars
        self.jupiter = jupiter
        self.saturn = saturn
        self.uranus = uranus
        self.neptune = neptune
        self.pluto = pluto
    }

    public static let empty = BodiesResponse()

    public subscript(body: BodyID) -> BodyPosition? {
        get {
            switch body {
            case .sun: return sun
            case .moon: return moon
            case .mercury: return mercury
            case .venus: return venus
            case .mars: return mars
            case .jupiter: return jupiter
            case .saturn: return saturn
            case .uranus: return uranus
            case .neptune: return neptune
            case .pluto: return pluto
            }
        }
        set {
            switch body {
            case .sun: sun = newValue
            case .moon: moon = newValue
            case .mercury: mercury = newValue
            case .venus: venus = newValue
            case .mars: mars = newValue
            case .jupiter: jupiter = newValue
            case .saturn: saturn = newValue
            case .uranus: uranus = newValue
            case .neptune: neptune = newValue
            case .pluto: pluto = newValue
            }
        }
    }
}

public struct AspectResponse: Codable, Sendable, Equatable {
    public let a: BodyID
    public let b: BodyID
    public let type: AspectType
    public let orb: Double

    public init(a: BodyID, b: BodyID, type: AspectType, orb: Double) {
        self.a = a
        self.b = b
        self.type = type
        self.orb = orb
    }
}

public struct EngineWarning: Codable, Sendable, Equatable {
    public let code: NatalWarningCode
    public let message: String

    public init(code: NatalWarningCode, message: String) {
        self.code = code
        self.message = message
    }
}

public struct NatalChartResponse: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let engineVersion: String
    public let dataVersions: EngineDataVersions
    public let profile: NatalProfile
    public let inputEcho: InputEcho
    public let times: NatalResponseTimes
    public let angles: AnglesResponse
    public let houses: HousesResponse
    public let bodies: BodiesResponse
    public let aspects: [AspectResponse]
    public let warnings: [EngineWarning]

    public init(
        schemaVersion: String = SchemaVersion.response,
        engineVersion: String,
        dataVersions: EngineDataVersions,
        profile: NatalProfile,
        inputEcho: InputEcho,
        times: NatalResponseTimes,
        angles: AnglesResponse,
        houses: HousesResponse,
        bodies: BodiesResponse,
        aspects: [AspectResponse],
        warnings: [EngineWarning]
    ) {
        self.schemaVersion = schemaVersion
        self.engineVersion = engineVersion
        self.dataVersions = dataVersions
        self.profile = profile
        self.inputEcho = inputEcho
        self.times = times
        self.angles = angles
        self.houses = houses
        self.bodies = bodies
        self.aspects = aspects
        self.warnings = warnings
    }
}
