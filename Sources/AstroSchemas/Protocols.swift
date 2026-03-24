import Foundation

public struct StateVector: Codable, Sendable, Equatable {
    public let positionX: Double
    public let positionY: Double
    public let positionZ: Double
    public let velocityX: Double
    public let velocityY: Double
    public let velocityZ: Double

    public init(
        positionX: Double,
        positionY: Double,
        positionZ: Double,
        velocityX: Double,
        velocityY: Double,
        velocityZ: Double
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.velocityZ = velocityZ
    }
}

public struct HouseContext: Codable, Sendable, Equatable {
    public let julianDayUT: Double
    public let dut1Seconds: Double?
    public let latitude: Double
    public let longitude: Double
    public let system: HouseSystem

    public init(
        julianDayUT: Double,
        dut1Seconds: Double? = nil,
        latitude: Double,
        longitude: Double,
        system: HouseSystem
    ) {
        self.julianDayUT = julianDayUT
        self.dut1Seconds = dut1Seconds
        self.latitude = latitude
        self.longitude = longitude
        self.system = system
    }
}

public struct HouseResult: Codable, Sendable, Equatable {
    public let system: HouseSystem
    public let cusps: [Double]
    public let fallbackApplied: Bool
    public let iterations: Int

    public init(system: HouseSystem, cusps: [Double], fallbackApplied: Bool, iterations: Int) {
        self.system = system
        self.cusps = cusps
        self.fallbackApplied = fallbackApplied
        self.iterations = iterations
    }
}

public protocol BirthResolver: Sendable {
    func resolve(_ raw: RawBirthRequest) async throws -> ResolvedBirthRequest
}

public protocol EphemerisProvider: Sendable {
    func stateVector(for body: BodyID, tdbJulianDay: Double) throws -> StateVector
    func earthStateVector(tdbJulianDay: Double) throws -> StateVector
}

public protocol HouseSolver: Sendable {
    func solve(_ context: HouseContext) throws -> HouseResult
}

public protocol EarthOrientationProviding: Sendable {
    func dut1Seconds(forJulianDayUTC julianDayUTC: Double) throws -> Double?
}

public protocol DataPackStore: Sendable {
    func ensureReady() async throws
    func installedDataVersions() async throws -> EngineDataVersions
}
