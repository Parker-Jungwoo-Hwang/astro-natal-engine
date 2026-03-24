import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class Stage4NatalChartComputerTests: XCTestCase {
    func testStage4ComputerPopulatesBodiesAndTimes() async throws {
        let computer = Stage4NatalChartComputer(ephemerisProvider: Stage4MockEphemerisProvider())
        let environment = NatalEngineEnvironment(
            engineVersion: "0.4.0-stage4",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
        )

        let response = try await computer.generate(
            request: ResolvedBirthRequest(
                birth: ResolvedBirth(
                    localDateTime: "1994-11-03T14:25:00",
                    timeZoneId: "Asia/Seoul",
                    utcOffsetMinutesAtBirth: 540,
                    ambiguityPolicy: .earlier,
                    timePrecision: .minute
                ),
                location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
                subject: BirthSubject(gender: "female"),
                profile: .standardNatal
            ),
            environment: environment
        )

        XCTAssertNotNil(response.bodies.sun)
        XCTAssertNotNil(response.bodies.moon)
        XCTAssertNotNil(response.bodies.pluto)
        XCTAssertEqual(response.bodies.sun?.sign, .aries)
        XCTAssertEqual(response.bodies.moon?.sign, .taurus)
        XCTAssertEqual(response.houses.cusps, Array(repeating: 0, count: 12))
        XCTAssertEqual(response.angles, .zero)
        XCTAssertEqual(response.times.utc, "1994-11-03T05:25:00Z")
        XCTAssertNotNil(response.times.julianDayTDB)
        XCTAssertTrue(response.warnings.contains(where: { $0.code == .standardModeWithoutEOP }))
    }

    func testStage4ComputerAddsPrecisionAndPre1970Warnings() async throws {
        let computer = Stage4NatalChartComputer(ephemerisProvider: Stage4MockEphemerisProvider())
        let environment = NatalEngineEnvironment(
            engineVersion: "0.4.0-stage4",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
        )

        let response = try await computer.generate(
            request: ResolvedBirthRequest(
                birth: ResolvedBirth(
                    localDateTime: "1935-05-01T08:00:00",
                    timeZoneId: "America/New_York",
                    utcOffsetMinutesAtBirth: -300,
                    ambiguityPolicy: .earlier,
                    timePrecision: .hour
                ),
                location: BirthLocation(city: "New York", latitude: 40.7128, longitude: -74.0060),
                subject: BirthSubject(gender: nil),
                profile: .standardNatal
            ),
            environment: environment
        )

        XCTAssertTrue(response.warnings.contains(where: { $0.code == .birthTimePrecisionLow }))
        XCTAssertTrue(response.warnings.contains(where: { $0.code == .pre1970TimezoneBestEffort }))
    }
}

private struct Stage4MockEphemerisProvider: EphemerisProvider {
    func stateVector(for body: BodyID, tdbJulianDay: Double) throws -> StateVector {
        _ = tdbJulianDay
        let longitude: Double
        switch body {
        case .sun: longitude = 15
        case .moon: longitude = 45
        case .mercury: longitude = 75
        case .venus: longitude = 105
        case .mars: longitude = 135
        case .jupiter: longitude = 165
        case .saturn: longitude = 195
        case .uranus: longitude = 225
        case .neptune: longitude = 255
        case .pluto: longitude = 285
        }

        return makeEquatorialState(
            longitude: longitude,
            latitude: body == .moon ? 5 : 0,
            speedLongitude: body == .saturn ? -0.1 : 1.0
        )
    }

    func earthStateVector(tdbJulianDay: Double) throws -> StateVector {
        _ = tdbJulianDay
        return .zero
    }
}

private extension StateVector {
    static let zero = StateVector(
        positionX: 0,
        positionY: 0,
        positionZ: 0,
        velocityX: 0,
        velocityY: 0,
        velocityZ: 0
    )
}

private func makeEquatorialState(
    longitude: Double,
    latitude: Double,
    speedLongitude: Double,
    radius: Double = 100_000_000.0
) -> StateVector {
    let lambda = longitude * .pi / 180.0
    let beta = latitude * .pi / 180.0
    let lambdaDot = speedLongitude * .pi / 180.0 / 86_400.0
    let epsilon = 84_381.448 / 3_600.0 * .pi / 180.0

    let eclipticPosition = (
        x: radius * cos(beta) * cos(lambda),
        y: radius * cos(beta) * sin(lambda),
        z: radius * sin(beta)
    )
    let eclipticVelocity = (
        x: -radius * cos(beta) * sin(lambda) * lambdaDot,
        y: radius * cos(beta) * cos(lambda) * lambdaDot,
        z: 0.0
    )

    return StateVector(
        positionX: eclipticPosition.x,
        positionY: cos(epsilon) * eclipticPosition.y - sin(epsilon) * eclipticPosition.z,
        positionZ: sin(epsilon) * eclipticPosition.y + cos(epsilon) * eclipticPosition.z,
        velocityX: eclipticVelocity.x,
        velocityY: cos(epsilon) * eclipticVelocity.y - sin(epsilon) * eclipticVelocity.z,
        velocityZ: sin(epsilon) * eclipticVelocity.y + cos(epsilon) * eclipticVelocity.z
    )
}
