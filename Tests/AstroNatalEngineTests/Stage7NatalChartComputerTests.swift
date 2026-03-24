import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class Stage7NatalChartComputerTests: XCTestCase {
    func testStage7InjectsDUT1AndSuppressesStandardWarning() async throws {
        let computer = Stage7NatalChartComputer(
            bodyPositionCalculator: Stage7MockBodyPositionCalculator(),
            houseComputer: Stage7MockHouseComputer(),
            earthOrientationProvider: FixedEarthOrientationProvider(dut1Seconds: 0.42)
        )
        let environment = NatalEngineEnvironment(
            engineVersion: "0.7.0-stage7",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a", eop: "2026.03.0")
        )

        let response = try await computer.generate(
            request: makeRequest(),
            environment: environment
        )

        XCTAssertEqual(response.times.dut1Seconds!, 0.42, accuracy: 0.0001)
        XCTAssertFalse(response.warnings.contains(where: { $0.code == .standardModeWithoutEOP }))
        XCTAssertTrue(response.aspects.contains(where: { $0.type == .sextile }))
    }

    func testStage7KeepsStandardWarningWithoutEOP() async throws {
        let computer = Stage7NatalChartComputer(
            bodyPositionCalculator: Stage7MockBodyPositionCalculator(),
            houseComputer: Stage7MockHouseComputer(),
            earthOrientationProvider: FixedEarthOrientationProvider(dut1Seconds: nil)
        )
        let environment = NatalEngineEnvironment(
            engineVersion: "0.7.0-stage7",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
        )

        let response = try await computer.generate(
            request: makeRequest(),
            environment: environment
        )

        XCTAssertNil(response.times.dut1Seconds)
        XCTAssertTrue(response.warnings.contains(where: { $0.code == .standardModeWithoutEOP }))
    }

    private func makeRequest() -> ResolvedBirthRequest {
        ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: nil),
            profile: .standardNatal
        )
    }
}

private struct FixedEarthOrientationProvider: EarthOrientationProviding {
    let dut1Seconds: Double?

    func dut1Seconds(forJulianDayUTC julianDayUTC: Double) throws -> Double? {
        _ = julianDayUTC
        return dut1Seconds
    }
}

private struct Stage7MockBodyPositionCalculator: BodyPositionComputing {
    func bodyPosition(for body: BodyID, at resolvedTime: ResolvedTime) throws -> BodyPosition {
        try bodies(at: resolvedTime)[body]!
    }

    func bodies(at resolvedTime: ResolvedTime) throws -> BodiesResponse {
        _ = resolvedTime
        return BodiesResponse(
            sun: makePosition(20),
            moon: makePosition(80)
        )
    }

    private func makePosition(_ longitude: Double) -> BodyPosition {
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

private struct Stage7MockHouseComputer: AngleHouseComputing {
    func compute(_ context: HouseContext) throws -> HouseComputation {
        let offset = (context.dut1Seconds ?? 0) / 10.0
        return HouseComputation(
            angles: AnglesResponse(
                asc: 15 + offset,
                mc: 105 + offset,
                ic: 285 + offset,
                dc: 195 + offset
            ),
            houseResult: HouseResult(
                system: .placidus,
                cusps: [15.0, 45.0, 75.0, 105.0, 135.0, 165.0, 195.0, 225.0, 255.0, 285.0, 315.0, 345.0].map { $0 + offset },
                fallbackApplied: false,
                iterations: 16
            )
        )
    }
}
