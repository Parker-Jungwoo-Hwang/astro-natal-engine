import Foundation
import AstroSchemas

public actor FileSystemDataPackStore: DataPackStore {
    public struct Options: Sendable, Equatable {
        public let eagerlyDownloadOptionalPackIDs: Set<String>
        public let allowOfflineManifestFallback: Bool
        public let verifyExistingFilesOnPrepare: Bool

        public init(
            eagerlyDownloadOptionalPackIDs: Set<String> = [],
            allowOfflineManifestFallback: Bool = true,
            verifyExistingFilesOnPrepare: Bool = true
        ) {
            self.eagerlyDownloadOptionalPackIDs = eagerlyDownloadOptionalPackIDs
            self.allowOfflineManifestFallback = allowOfflineManifestFallback
            self.verifyExistingFilesOnPrepare = verifyExistingFilesOnPrepare
        }
    }

    private let manifestURL: URL?
    private let layout: PackStorageLayout
    private let httpClient: any RuntimeHTTPClient
    private let options: Options
    private let fileManager: FileManager
    private var cachedManifest: EngineDataManifest?

    public init(
        manifestURL: URL?,
        layout: PackStorageLayout = PackStorageLayout(baseDirectory: PackStorageLayout.defaultBaseDirectory()),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        options: Options = Options(),
        fileManager: FileManager = .default
    ) {
        self.manifestURL = manifestURL
        self.layout = layout
        self.httpClient = httpClient
        self.options = options
        self.fileManager = fileManager
    }

    public func ensureReady() async throws {
        // `prepare()` depends on this method to make the runtime filesystem match the
        // manifest atomically enough that later synchronous lookups can trust local
        // files. Persisting the manifest before downloads gives Stage 9+/10+ a single
        // source of truth for both dataVersions and pack discovery.
        try createBaseDirectoriesIfNeeded()
        let manifest = try await loadPreferredManifest()
        try persistManifest(manifest)

        for descriptor in manifest.packs where shouldInstall(descriptor) {
            try await ensurePackAvailable(descriptor)
        }

        for descriptor in manifest.packs where descriptor.required {
            guard fileManager.fileExists(atPath: layout.packFileURL(for: descriptor).path) else {
                throw NatalEngineError.missingRequiredPack(descriptor.id)
            }
        }

        cachedManifest = manifest
    }

    public func installedDataVersions() async throws -> EngineDataVersions {
        if let cachedManifest {
            return cachedManifest.derivedDataVersions()
        }

        let manifest = try loadLocalManifest()
        return manifest.derivedDataVersions()
    }

    private func shouldInstall(_ descriptor: DataPackDescriptor) -> Bool {
        descriptor.required || options.eagerlyDownloadOptionalPackIDs.contains(descriptor.id)
    }

    private func createBaseDirectoriesIfNeeded() throws {
        let directories = [
            layout.baseDirectory,
            layout.packsDirectory,
            layout.cacheDirectory,
            layout.logsDirectory,
            layout.stagingDirectory
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func loadPreferredManifest() async throws -> EngineDataManifest {
        if let manifestURL {
            do {
                let response = try await httpClient.get(manifestURL)
                guard (200 ..< 300).contains(response.statusCode) else {
                    throw NatalEngineError.networkFailure("Manifest download returned HTTP \(response.statusCode).")
                }
                return try decodeManifest(response.data)
            } catch {
                if options.allowOfflineManifestFallback {
                    return try loadLocalManifest()
                }
                if let natalError = error as? NatalEngineError {
                    throw natalError
                }
                throw NatalEngineError.networkFailure(error.localizedDescription)
            }
        }

        return try loadLocalManifest()
    }

    private func loadLocalManifest() throws -> EngineDataManifest {
        guard fileManager.fileExists(atPath: layout.manifestFileURL.path) else {
            throw NatalEngineError.missingRequiredPack("manifest")
        }

        let data = try Data(contentsOf: layout.manifestFileURL)
        return try decodeManifest(data)
    }

    private func decodeManifest(_ data: Data) throws -> EngineDataManifest {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(EngineDataManifest.self, from: data)
        } catch {
            throw NatalEngineError.manifestInvalid(error.localizedDescription)
        }
    }

    private func persistManifest(_ manifest: EngineDataManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: layout.manifestFileURL, options: .atomic)
    }

    private func ensurePackAvailable(_ descriptor: DataPackDescriptor) async throws {
        let destination = layout.packFileURL(for: descriptor)

        if fileManager.fileExists(atPath: destination.path) {
            if options.verifyExistingFilesOnPrepare {
                if try verifyFile(at: destination, descriptor: descriptor) {
                    return
                }
            } else {
                return
            }
        }

        guard let remoteURL = descriptor.remoteURL else {
            throw NatalEngineError.manifestInvalid("Invalid pack URL for \(descriptor.id).")
        }

        let response: HTTPDataResponse
        do {
            response = try await httpClient.get(remoteURL)
        } catch {
            if let natalError = error as? NatalEngineError {
                throw natalError
            }
            throw NatalEngineError.networkFailure(error.localizedDescription)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw NatalEngineError.networkFailure("Pack \(descriptor.id) returned HTTP \(response.statusCode).")
        }

        let stagingURL = layout.stagingDirectory.appendingPathComponent(UUID().uuidString)
        try response.data.write(to: stagingURL, options: .atomic)

        do {
            // Size + checksum validation happens before the final move so runtime
            // locators never observe a partially downloaded kernel/EOP pack.
            guard response.data.count == Int(descriptor.bytes) else {
                throw NatalEngineError.manifestInvalid("Byte count mismatch for \(descriptor.id).")
            }

            let digest = try SHA256.hexDigest(ofFileAt: stagingURL)
            guard digest == descriptor.sha256 else {
                throw NatalEngineError.dataPackChecksumMismatch(descriptor.id)
            }

            try fileManager.createDirectory(at: layout.packDirectory(for: descriptor), withIntermediateDirectories: true)
            try replaceItem(at: destination, with: stagingURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func verifyFile(at url: URL, descriptor: DataPackDescriptor) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard bytes == descriptor.bytes else {
            return false
        }

        let digest = try SHA256.hexDigest(ofFileAt: url)
        return digest == descriptor.sha256
    }

    private func replaceItem(at destination: URL, with stagingURL: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            #if canImport(Darwin)
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagingURL)
            #else
            let backupURL = layout.stagingDirectory.appendingPathComponent(UUID().uuidString + ".bak")
            try fileManager.moveItem(at: destination, to: backupURL)
            do {
                try fileManager.moveItem(at: stagingURL, to: destination)
                try? fileManager.removeItem(at: backupURL)
            } catch {
                try? fileManager.moveItem(at: backupURL, to: destination)
                throw error
            }
            #endif
        } else {
            try fileManager.moveItem(at: stagingURL, to: destination)
        }
    }
}
