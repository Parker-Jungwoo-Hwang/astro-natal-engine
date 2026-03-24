import XCTest
@testable import AstroNatalEngine
@testable import AstroEphemeris
@testable import AstroRuntimeData
@testable import AstroSchemas

final class Stage10RealKernelRegressionTests: XCTestCase {
    func testStage10EndToEndWithRealKernelWhenAvailable() async throws {
        guard let kernelURL = DE442KernelLocator.locateKernelURL() else {
            throw XCTSkip("Set ASTRO_DE442_PATH or install de442.bsp in the runtime packs directory to run the real-kernel regression.")
        }

        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let ephemerisDescriptor = DataPackDescriptor(
            id: "ephemeris-de442",
            required: true,
            url: "https://cdn.example.com/astro/de442.bsp",
            sha256: String(repeating: "0", count: 64),
            bytes: 0
        )
        let eopDescriptor = DataPackDescriptor(
            id: "eop-2000.01",
            required: false,
            url: "https://cdn.example.com/astro/eop-2000.01.json",
            sha256: String(repeating: "0", count: 64),
            bytes: 0
        )
        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [ephemerisDescriptor, eopDescriptor]
        )

        try writeManifest(manifest, to: layout.manifestFileURL)
        try FileManager.default.createDirectory(at: layout.packDirectory(for: ephemerisDescriptor), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: layout.packFileURL(for: ephemerisDescriptor),
            withDestinationURL: kernelURL
        )
        try writePack(
            EarthOrientationPack(
                version: "2000.01.0",
                entries: [
                    EarthOrientationSample(julianDayUTC: 2_451_544.0, dut1Seconds: 0.30),
                    EarthOrientationSample(julianDayUTC: 2_451_545.0, dut1Seconds: 0.35),
                    EarthOrientationSample(julianDayUTC: 2_451_546.0, dut1Seconds: 0.40)
                ]
            ),
            to: layout.packFileURL(for: eopDescriptor)
        )

        let configuration = NatalEngineConfiguration.stage10(
            manifestURL: nil,
            baseDirectory: tempDirectory,
            runtimeDataOptions: .init(verifyExistingFilesOnPrepare: false)
        )
        let engine = NatalChartEngine(configuration: configuration)
        try await engine.prepare()

        let response = try await engine.generate(
            ResolvedBirthRequest(
                birth: ResolvedBirth(
                    localDateTime: "2000-01-01T12:00:00",
                    timeZoneId: "UTC",
                    utcOffsetMinutesAtBirth: 0,
                    ambiguityPolicy: .earlier,
                    timePrecision: .second
                ),
                location: BirthLocation(city: "Greenwich", latitude: 51.4779, longitude: 0.0),
                subject: BirthSubject(gender: nil),
                profile: .standardNatal
            )
        )

        XCTAssertEqual(response.dataVersions.ephemeris, "de442.bsp")
        XCTAssertNotNil(response.times.dut1Seconds)
        XCTAssertFalse(response.warnings.contains(where: { $0.code == .standardModeWithoutEOP }))
        XCTAssertEqual(response.houses.system, .placidus)
        XCTAssertEqual(response.houses.cusps.count, 12)
        XCTAssertTrue((1...12).contains(response.bodies.sun!.house))
        XCTAssertTrue((0.0..<360.0).contains(response.bodies.sun!.longitude))
        XCTAssertEqual(response.bodies.sun!.sign, .capricorn)
        XCTAssertGreaterThan(response.bodies.sun!.longitude, 279.0)
        XCTAssertLessThan(response.bodies.sun!.longitude, 281.5)
        XCTAssertGreaterThan(response.bodies.sun!.speedLongitude, 0.8)
        XCTAssertLessThan(response.bodies.sun!.speedLongitude, 1.2)
        XCTAssertFalse(response.aspects.isEmpty)
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
