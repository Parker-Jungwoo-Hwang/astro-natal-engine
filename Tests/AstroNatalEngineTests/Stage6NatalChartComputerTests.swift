import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class Stage6NatalChartComputerTests: XCTestCase {
    func testStage6ComputerAddsAspectsToStage5Payload() async throws {
        let computer = Stage6NatalChartComputer(baseComputer: Stage6MockBaseComputer())

        let response = try await computer.generate(
            request: makeRequest(profile: .standardNatal),
            environment: NatalEngineEnvironment(
                engineVersion: "0.6.0-stage6",
                dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
            )
        )

        XCTAssertEqual(response.angles.asc, 15.0)
        XCTAssertEqual(response.houses.system, .placidus)
        XCTAssertEqual(response.bodies.sun?.house, 1)
        XCTAssertTrue(response.aspects.contains(where: { $0.a == .sun && $0.b == .moon && $0.type == .sextile }))
        XCTAssertTrue(response.aspects.contains(where: { $0.a == .sun && $0.b == .mars && $0.type == .opposition }))
    }

    func testStage6ComputerUsesEnhancedProfileOrbs() async throws {
        let computer = Stage6NatalChartComputer(baseComputer: Stage6EnhancedMockBaseComputer())

        let response = try await computer.generate(
            request: makeRequest(profile: .enhancedNatal),
            environment: NatalEngineEnvironment(
                engineVersion: "0.6.0-stage6",
                dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
            )
        )

        XCTAssertEqual(response.aspects.count, 1)
        XCTAssertEqual(response.aspects.first?.type, .sextile)
        XCTAssertEqual(response.aspects.first!.orb, 5.0, accuracy: 0.0001)
    }

    private func makeRequest(profile: NatalProfile) -> ResolvedBirthRequest {
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
            profile: profile
        )
    }
}

private struct Stage6MockBaseComputer: NatalChartComputer {
    func generate(request: ResolvedBirthRequest, environment: NatalEngineEnvironment) async throws -> NatalChartResponse {
        NatalChartResponse(
            engineVersion: environment.engineVersion,
            dataVersions: environment.dataVersions,
            profile: request.profile,
            inputEcho: InputEcho(
                birthLocalDateTime: request.birth.localDateTime,
                timeZoneId: request.birth.timeZoneId,
                utcOffsetMinutesAtBirth: request.birth.utcOffsetMinutesAtBirth,
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                gender: request.subject.gender
            ),
            times: NatalResponseTimes(
                utc: "1994-11-03T05:25:00Z",
                julianDayUTC: 2_449_660.725694,
                julianDayTT: 2_449_660.726438,
                julianDayTDB: 2_449_660.726439,
                deltaTSeconds: 60.2
            ),
            angles: AnglesResponse(asc: 15, mc: 105, ic: 285, dc: 195),
            houses: HousesResponse(system: .placidus, cusps: [15, 45, 75, 105, 135, 165, 195, 225, 255, 285, 315, 345]),
            bodies: BodiesResponse(
                sun: makePosition(20, house: 1),
                moon: makePosition(80, house: 2),
                mars: makePosition(200, house: 7)
            ),
            aspects: [],
            warnings: []
        )
    }

    private func makePosition(_ longitude: Double, house: Int) -> BodyPosition {
        BodyPosition(
            longitude: longitude,
            latitude: 0,
            speedLongitude: 1,
            retrograde: false,
            sign: ZodiacSign.allCases[min(Int(longitude / 30.0), 11)],
            house: house
        )
    }
}

private struct Stage6EnhancedMockBaseComputer: NatalChartComputer {
    func generate(request: ResolvedBirthRequest, environment: NatalEngineEnvironment) async throws -> NatalChartResponse {
        NatalChartResponse(
            engineVersion: environment.engineVersion,
            dataVersions: environment.dataVersions,
            profile: request.profile,
            inputEcho: InputEcho(
                birthLocalDateTime: request.birth.localDateTime,
                timeZoneId: request.birth.timeZoneId,
                utcOffsetMinutesAtBirth: request.birth.utcOffsetMinutesAtBirth,
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                gender: request.subject.gender
            ),
            times: NatalResponseTimes(
                utc: "1994-11-03T05:25:00Z",
                julianDayUTC: 2_449_660.725694,
                julianDayTT: 2_449_660.726438,
                julianDayTDB: 2_449_660.726439,
                deltaTSeconds: 60.2
            ),
            angles: AnglesResponse(asc: 15, mc: 105, ic: 285, dc: 195),
            houses: HousesResponse(system: .placidus, cusps: [15, 45, 75, 105, 135, 165, 195, 225, 255, 285, 315, 345]),
            bodies: BodiesResponse(
                sun: makePosition(0, house: 1),
                moon: makePosition(65, house: 3)
            ),
            aspects: [],
            warnings: []
        )
    }

    private func makePosition(_ longitude: Double, house: Int) -> BodyPosition {
        BodyPosition(
            longitude: longitude,
            latitude: 0,
            speedLongitude: 1,
            retrograde: false,
            sign: ZodiacSign.allCases[min(Int(longitude / 30.0), 11)],
            house: house
        )
    }
}
