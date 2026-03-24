import XCTest
@testable import AstroRuntimeData
@testable import AstroSchemas

final class RuntimeDataEarthOrientationProviderTests: XCTestCase {
    func testInterpolatesDUT1FromRuntimePack() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [
                DataPackDescriptor(
                    id: "eop-2026.03",
                    required: false,
                    url: "https://cdn.example.com/astro/eop-2026.03.json",
                    sha256: String(repeating: "0", count: 64),
                    bytes: 0
                )
            ]
        )

        try writeManifest(manifest, to: layout.manifestFileURL)
        try writePack(
            EarthOrientationPack(
                version: "2026.03.0",
                entries: [
                    EarthOrientationSample(julianDayUTC: 2_460_000.0, dut1Seconds: 0.10),
                    EarthOrientationSample(julianDayUTC: 2_460_001.0, dut1Seconds: 0.30)
                ]
            ),
            to: layout.packFileURL(for: manifest.packs[0])
        )

        let provider = RuntimeDataEarthOrientationProvider(layout: layout)
        let dut1 = try provider.dut1Seconds(forJulianDayUTC: 2_460_000.25)

        XCTAssertEqual(dut1!, 0.15, accuracy: 0.0001)
    }

    func testReturnsNilWhenNoEOPPackExists() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: []
        )

        try writeManifest(manifest, to: layout.manifestFileURL)

        let provider = RuntimeDataEarthOrientationProvider(layout: layout)
        XCTAssertNil(try provider.dut1Seconds(forJulianDayUTC: 2_460_000.0))
    }

    func testThrowsOnInvalidEOPPackJSON() throws {
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
        try FileManager.default.createDirectory(at: layout.packDirectory(for: descriptor), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: layout.packFileURL(for: descriptor), options: .atomic)

        let provider = RuntimeDataEarthOrientationProvider(layout: layout)

        XCTAssertThrowsError(try provider.dut1Seconds(forJulianDayUTC: 2_460_000.0)) { error in
            guard case let .manifestInvalid(message) = error as? NatalEngineError else {
                return XCTFail("Expected manifestInvalid, got \(error)")
            }
            XCTAssertTrue(message.contains("EOP pack is invalid"))
        }
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
