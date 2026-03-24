import XCTest
@testable import AstroRuntimeData
@testable import AstroSchemas

final class FileSystemDataPackStoreTests: XCTestCase {
    func testEnsureReadyDownloadsRequiredPacksAndPersistsManifest() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifestURL = URL(string: "https://cdn.example.com/astro/manifest.json")!
        let ephemerisURL = URL(string: "https://cdn.example.com/astro/de442.bsp")!
        let timeCoreURL = URL(string: "https://cdn.example.com/astro/time-core-2026.03.json")!

        let ephemerisData = Data("ephemeris-payload".utf8)
        let timeCoreData = Data("time-core-payload".utf8)

        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [
                DataPackDescriptor(
                    id: "ephemeris-de442",
                    required: true,
                    url: ephemerisURL.absoluteString,
                    sha256: SHA256.hexDigest(of: ephemerisData),
                    bytes: Int64(ephemerisData.count)
                ),
                DataPackDescriptor(
                    id: "time-core-2026.03",
                    required: true,
                    url: timeCoreURL.absoluteString,
                    sha256: SHA256.hexDigest(of: timeCoreData),
                    bytes: Int64(timeCoreData.count)
                )
            ]
        )

        let manifestData = try JSONEncoder().encode(manifest)
        let client = MockHTTPClient(responses: [
            manifestURL: HTTPDataResponse(data: manifestData, statusCode: 200),
            ephemerisURL: HTTPDataResponse(data: ephemerisData, statusCode: 200),
            timeCoreURL: HTTPDataResponse(data: timeCoreData, statusCode: 200)
        ])

        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: tempDirectory),
            httpClient: client
        )

        try await store.ensureReady()
        let versions = try await store.installedDataVersions()

        XCTAssertEqual(versions.ephemeris, "de442.bsp")
        XCTAssertEqual(versions.timeCore, "2026.03")
        XCTAssertNil(versions.tzdb)

        let ephemerisPath = tempDirectory
            .appendingPathComponent("packs", isDirectory: true)
            .appendingPathComponent("ephemeris-de442", isDirectory: true)
            .appendingPathComponent("de442.bsp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ephemerisPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("manifest.json").path))
    }

    func testEnsureReadyThrowsOnChecksumMismatch() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifestURL = URL(string: "https://cdn.example.com/astro/manifest.json")!
        let packURL = URL(string: "https://cdn.example.com/astro/de442.bsp")!
        let packData = Data("corrupted".utf8)

        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [
                DataPackDescriptor(
                    id: "ephemeris-de442",
                    required: true,
                    url: packURL.absoluteString,
                    sha256: String(repeating: "0", count: 64),
                    bytes: Int64(packData.count)
                )
            ]
        )

        let client = MockHTTPClient(responses: [
            manifestURL: HTTPDataResponse(data: try JSONEncoder().encode(manifest), statusCode: 200),
            packURL: HTTPDataResponse(data: packData, statusCode: 200)
        ])

        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: tempDirectory),
            httpClient: client
        )

        do {
            try await store.ensureReady()
            XCTFail("Expected checksum mismatch")
        } catch let error as NatalEngineError {
            XCTAssertEqual(error, .dataPackChecksumMismatch("ephemeris-de442"))
        }
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct MockHTTPClient: RuntimeHTTPClient {
    let responses: [URL: HTTPDataResponse]

    func get(_ url: URL) async throws -> HTTPDataResponse {
        guard let response = responses[url] else {
            throw NatalEngineError.networkFailure("No mock response for \(url.absoluteString)")
        }
        return response
    }
}
