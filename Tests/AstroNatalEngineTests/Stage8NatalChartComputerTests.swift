import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class Stage8NatalChartComputerTests: XCTestCase {
    func testStage8ComputerUsesApparentFramePath() async throws {
        let apparentResponse = NatalChartResponse(
            engineVersion: "0.8.0-stage8",
            dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a", eop: "2026.03.0"),
            profile: .standardNatal,
            inputEcho: InputEcho(
                birthLocalDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                utcOffsetMinutesAtBirth: 540,
                latitude: 37.5665,
                longitude: 126.9780,
                gender: nil
            ),
            times: NatalResponseTimes(
                utc: "1994-11-03T05:25:00Z",
                julianDayUTC: 2_449_660.725694,
                julianDayTT: 2_449_660.726438,
                julianDayTDB: 2_449_660.726439,
                deltaTSeconds: 60.2,
                dut1Seconds: 0.2
            ),
            angles: AnglesResponse(asc: 15.1, mc: 105.1, ic: 285.1, dc: 195.1),
            houses: HousesResponse(system: .placidus, cusps: [15.1, 45.1, 75.1, 105.1, 135.1, 165.1, 195.1, 225.1, 255.1, 285.1, 315.1, 345.1]),
            bodies: BodiesResponse(
                sun: BodyPosition(longitude: 20.3, latitude: 0.1, speedLongitude: 0.98, retrograde: false, sign: .aries, house: 1),
                moon: BodyPosition(longitude: 80.1, latitude: 5.0, speedLongitude: 13.0, retrograde: false, sign: .gemini, house: 2)
            ),
            aspects: [AspectResponse(a: .sun, b: .moon, type: .sextile, orb: 0.2)],
            warnings: []
        )
        let computer = Stage8NatalChartComputer(baseComputer: FixedResponseChartComputer(response: apparentResponse))

        let response = try await computer.generate(
            request: makeRequest(),
            environment: NatalEngineEnvironment(
                engineVersion: "0.8.0-stage8",
                dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a", eop: "2026.03.0")
            )
        )

        XCTAssertEqual(response.times.dut1Seconds!, 0.2, accuracy: 0.0001)
        XCTAssertEqual(response.bodies.sun!.longitude, 20.3, accuracy: 0.0001)
        XCTAssertEqual(response.aspects.first?.type, .sextile)
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

private struct FixedResponseChartComputer: NatalChartComputer {
    let response: NatalChartResponse

    func generate(request: ResolvedBirthRequest, environment: NatalEngineEnvironment) async throws -> NatalChartResponse {
        _ = request
        _ = environment
        return response
    }
}
