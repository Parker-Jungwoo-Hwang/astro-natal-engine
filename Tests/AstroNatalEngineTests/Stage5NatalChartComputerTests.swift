import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class Stage5NatalChartComputerTests: XCTestCase {
    func testStage5ComputerAssignsHousesAndAngles() async throws {
        let computer = Stage5NatalChartComputer(
            bodyPositionCalculator: Stage5MockBodyPositionCalculator(),
            houseComputer: Stage5MockHouseComputer()
        )
        let environment = NatalEngineEnvironment(
            engineVersion: "0.5.0-stage5",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
        )

        let response = try await computer.generate(
            request: makeRequest(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                utcOffsetMinutesAtBirth: 540,
                timePrecision: .minute
            ),
            environment: environment
        )

        XCTAssertEqual(response.houses.system, .placidus)
        XCTAssertEqual(response.angles.asc, 15.0)
        XCTAssertEqual(response.angles.mc, 105.0)
        XCTAssertEqual(response.bodies.sun?.house, 1)
        XCTAssertEqual(response.bodies.moon?.house, 2)
        XCTAssertEqual(response.bodies.saturn?.house, 7)
        XCTAssertEqual(response.bodies.pluto?.house, 10)
        XCTAssertFalse(response.warnings.contains(where: { $0.code == .placidusFallbackApplied }))
    }

    func testStage5ComputerReportsFallbackWarning() async throws {
        let computer = Stage5NatalChartComputer(
            bodyPositionCalculator: Stage5MockBodyPositionCalculator(),
            houseComputer: Stage5FallbackHouseComputer()
        )
        let environment = NatalEngineEnvironment(
            engineVersion: "0.5.0-stage5",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
        )

        let response = try await computer.generate(
            request: makeRequest(
                localDateTime: "1935-05-01T08:00:00",
                timeZoneId: "America/New_York",
                utcOffsetMinutesAtBirth: -300,
                timePrecision: .hour
            ),
            environment: environment
        )

        XCTAssertEqual(response.houses.system, .equal)
        XCTAssertTrue(response.warnings.contains(where: { $0.code == .placidusFallbackApplied }))
        XCTAssertTrue(response.warnings.contains(where: { $0.code == .birthTimePrecisionLow }))
        XCTAssertTrue(response.warnings.contains(where: { $0.code == .pre1970TimezoneBestEffort }))
    }

    private func makeRequest(
        localDateTime: String,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        timePrecision: BirthTimePrecision
    ) -> ResolvedBirthRequest {
        ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: localDateTime,
                timeZoneId: timeZoneId,
                utcOffsetMinutesAtBirth: utcOffsetMinutesAtBirth,
                ambiguityPolicy: .earlier,
                timePrecision: timePrecision
            ),
            location: BirthLocation(city: "Test", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: nil),
            profile: .standardNatal
        )
    }
}

private struct Stage5MockBodyPositionCalculator: BodyPositionComputing {
    func bodyPosition(for body: BodyID, at resolvedTime: ResolvedTime) throws -> BodyPosition {
        try bodies(at: resolvedTime)[body]!
    }

    func bodies(at resolvedTime: ResolvedTime) throws -> BodiesResponse {
        _ = resolvedTime
        return BodiesResponse(
            sun: makePosition(longitude: 20),
            moon: makePosition(longitude: 55),
            mercury: makePosition(longitude: 85),
            venus: makePosition(longitude: 115),
            mars: makePosition(longitude: 145),
            jupiter: makePosition(longitude: 175),
            saturn: makePosition(longitude: 205),
            uranus: makePosition(longitude: 235),
            neptune: makePosition(longitude: 265),
            pluto: makePosition(longitude: 295)
        )
    }

    private func makePosition(longitude: Double) -> BodyPosition {
        BodyPosition(
            longitude: longitude,
            latitude: 0,
            speedLongitude: 1,
            retrograde: false,
            sign: ZodiacSign.allCases[min(Int(longitude / 30.0), 11)],
            house: 0
        )
    }
}

private struct Stage5MockHouseComputer: AngleHouseComputing {
    func compute(_ context: HouseContext) throws -> HouseComputation {
        _ = context
        return HouseComputation(
            angles: AnglesResponse(asc: 15, mc: 105, ic: 285, dc: 195),
            houseResult: HouseResult(
                system: .placidus,
                cusps: [15, 45, 75, 105, 135, 165, 195, 225, 255, 285, 315, 345],
                fallbackApplied: false,
                iterations: 12
            )
        )
    }
}

private struct Stage5FallbackHouseComputer: AngleHouseComputing {
    func compute(_ context: HouseContext) throws -> HouseComputation {
        _ = context
        return HouseComputation(
            angles: AnglesResponse(asc: 10, mc: 100, ic: 280, dc: 190),
            houseResult: HouseResult(
                system: .equal,
                cusps: [10, 40, 70, 100, 130, 160, 190, 220, 250, 280, 310, 340],
                fallbackApplied: true,
                iterations: 0
            )
        )
    }
}
