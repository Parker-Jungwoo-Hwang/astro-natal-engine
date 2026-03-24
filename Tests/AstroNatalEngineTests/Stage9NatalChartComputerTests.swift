import XCTest
@testable import AstroNatalEngine
@testable import AstroRuntimeData
@testable import AstroSchemas

final class Stage9NatalChartComputerTests: XCTestCase {
    func testStage9ConfigurationAutoWiresRuntimeEOPData() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let descriptor = DataPackDescriptor(
            id: "eop-2026.03",
            required: false,
            url: "https://cdn.example.com/astro/eop-2026.03.json",
            sha256: String(repeating: "0", count: 64),
            bytes: 0
        )
        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [descriptor]
        )
        try writeManifest(manifest, to: layout.manifestFileURL)
        try writePack(
            EarthOrientationPack(
                version: "2026.03.0",
                entries: [
                    EarthOrientationSample(julianDayUTC: 2_449_659.0, dut1Seconds: 0.10),
                    EarthOrientationSample(julianDayUTC: 2_449_660.0, dut1Seconds: 0.50)
                ]
            ),
            to: layout.packFileURL(for: descriptor)
        )

        let directProvider = RuntimeDataEarthOrientationProvider(layout: layout)
        XCTAssertNotNil(try directProvider.dut1Seconds(forJulianDayUTC: 2_449_659.725694))

        let configuration = NatalEngineConfiguration.stage9(
            manifestURL: nil,
            ephemerisProvider: Stage9MockEphemerisProvider(),
            baseDirectory: tempDirectory
        )

        let response = try await configuration.chartComputer.generate(
            request: makeRequest(),
            environment: NatalEngineEnvironment(
                engineVersion: "0.9.0-stage9",
                dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a", eop: "2026.03")
            )
        )

        XCTAssertNotNil(response.times.dut1Seconds)
        XCTAssertFalse(response.warnings.contains(where: { $0.code == .standardModeWithoutEOP }))
    }

    func testStage9ConfigurationKeepsFallbackWarningWhenNoRuntimeEOPPack() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: []
        )
        try writeManifest(manifest, to: layout.manifestFileURL)

        let configuration = NatalEngineConfiguration.stage9(
            manifestURL: nil,
            ephemerisProvider: Stage9MockEphemerisProvider(),
            baseDirectory: tempDirectory
        )

        let response = try await configuration.chartComputer.generate(
            request: makeRequest(),
            environment: NatalEngineEnvironment(
                engineVersion: "0.9.0-stage9",
                dataVersions: EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
            )
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

    private func writeManifest(_ manifest: EngineDataManifest, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func writePack(_ pack: EarthOrientationPack, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(pack)
        try data.write(to: url, options: .atomic)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct Stage9MockEphemerisProvider: EphemerisProvider {
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
        return StateVector(
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            velocityX: 0,
            velocityY: 0,
            velocityZ: 0
        )
    }
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
