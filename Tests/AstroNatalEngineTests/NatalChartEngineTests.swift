import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class NatalChartEngineTests: XCTestCase {
    func testGenerateThrowsBeforePrepare() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)

        let request = makeResolvedRequest()

        do {
            _ = try await engine.generate(request)
            XCTFail("Expected engineNotPrepared")
        } catch let error as NatalEngineError {
            XCTAssertEqual(error, .engineNotPrepared)
        }
    }

    func testPrepareThenGenerateReturnsChartFromComputer() async throws {
        let configuration = NatalEngineConfiguration(
            engineVersion: "1.0.0-test",
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)

        try await engine.prepare()
        let response = try await engine.generate(makeResolvedRequest())

        XCTAssertEqual(response.engineVersion, "1.0.0-test")
        XCTAssertEqual(response.dataVersions.ephemeris, "de442.bsp")
        XCTAssertEqual(response.profile, .standardNatal)
        XCTAssertEqual(response.inputEcho.timeZoneId, "Asia/Seoul")
    }

    func testGenerateRawUsesResolver() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)
        try await engine.prepare()

        let raw = RawBirthRequest(
            birth: RawBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: nil,
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: "female"),
            profile: .standardNatal
        )

        let response = try await engine.generate(raw)
        XCTAssertEqual(response.inputEcho.timeZoneId, "UTC+09:00")
    }

    func testGenerateRawResolvesTimeZoneIDWhenOffsetMissing() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)
        try await engine.prepare()

        let raw = RawBirthRequest(
            birth: RawBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: "female"),
            profile: .standardNatal
        )

        let response = try await engine.generate(raw)
        XCTAssertEqual(response.inputEcho.timeZoneId, "Asia/Seoul")
        XCTAssertEqual(response.inputEcho.utcOffsetMinutesAtBirth, 540)
    }

    func testGenerateJSONDecodesResolvedRequest() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)
        try await engine.prepare()

        let requestData = try JSONEncoder().encode(makeResolvedRequest())
        let responseData = try await engine.generateJSON(requestData)
        let decoded = try JSONDecoder().decode(NatalChartResponse.self, from: responseData)

        XCTAssertEqual(decoded.schemaVersion, SchemaVersion.response)
        XCTAssertEqual(decoded.inputEcho.birthLocalDateTime, "1994-11-03T14:25:00")
    }

    private func makeResolvedRequest() -> ResolvedBirthRequest {
        ResolvedBirthRequest(
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
        )
    }
}

private actor MockDataPackStore: DataPackStore {
    func ensureReady() async throws {}

    func installedDataVersions() async throws -> EngineDataVersions {
        EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
    }
}

private struct EchoChartComputer: NatalChartComputer {
    func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
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
                julianDayUTC: 2449660.725694,
                julianDayTT: 2449660.726438,
                deltaTSeconds: 60.2
            ),
            angles: .zero,
            houses: .empty,
            bodies: .empty,
            aspects: [],
            warnings: [
                EngineWarning(
                    code: .standardModeWithoutEOP,
                    message: "Calculated in standardNatal mode without UT1 correction."
                )
            ]
        )
    }
}
