import XCTest
@testable import AstroRuntimeData
@testable import AstroSchemas

final class RuntimeInstalledDataLocatorTests: XCTestCase {
    func testFindsInstalledPackByPrefix() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let descriptor = DataPackDescriptor(
            id: "ephemeris-de442",
            required: true,
            url: "https://cdn.example.com/astro/de442.bsp",
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
        try Data("kernel".utf8).write(to: layout.packFileURL(for: descriptor), options: .atomic)

        let locator = RuntimeInstalledDataLocator(layout: layout)
        let packURL = try locator.installedPackURL(namedPrefix: "ephemeris")

        XCTAssertEqual(packURL?.lastPathComponent, "de442.bsp")
    }

    func testRequiredPackThrowsWhenMissing() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let layout = PackStorageLayout(baseDirectory: tempDirectory)
        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: []
        )

        try writeManifest(manifest, to: layout.manifestFileURL)

        let locator = RuntimeInstalledDataLocator(layout: layout)
        XCTAssertThrowsError(try locator.requiredInstalledPackURL(namedPrefix: "ephemeris")) { error in
            XCTAssertEqual(error as? NatalEngineError, .missingRequiredPack("ephemeris"))
        }
    }

    private func writeManifest(_ manifest: EngineDataManifest, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
