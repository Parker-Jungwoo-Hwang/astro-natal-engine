import Foundation
import AstroSchemas

public struct EngineDataManifest: Codable, Sendable, Equatable {
    public let manifestVersion: String
    public let engineDataVersion: String
    public let packs: [DataPackDescriptor]

    public init(manifestVersion: String, engineDataVersion: String, packs: [DataPackDescriptor]) {
        self.manifestVersion = manifestVersion
        self.engineDataVersion = engineDataVersion
        self.packs = packs
    }
}

public struct DataPackDescriptor: Codable, Sendable, Equatable {
    public let id: String
    public let required: Bool
    public let url: String
    public let sha256: String
    public let bytes: Int64

    public init(id: String, required: Bool, url: String, sha256: String, bytes: Int64) {
        self.id = id
        self.required = required
        self.url = url
        self.sha256 = sha256.lowercased()
        self.bytes = bytes
    }

    public var remoteURL: URL? {
        URL(string: url)
    }

    public var fileName: String {
        guard let remoteURL else { return id }
        let last = remoteURL.lastPathComponent
        return last.isEmpty ? id : last
    }
}

public struct PackStorageLayout: Sendable, Equatable {
    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public var manifestFileURL: URL {
        baseDirectory.appendingPathComponent("manifest.json")
    }

    public var packsDirectory: URL {
        baseDirectory.appendingPathComponent("packs", isDirectory: true)
    }

    public var cacheDirectory: URL {
        baseDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    public var logsDirectory: URL {
        baseDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public var stagingDirectory: URL {
        baseDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    public func packDirectory(for descriptor: DataPackDescriptor) -> URL {
        packsDirectory.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    public func packFileURL(for descriptor: DataPackDescriptor) -> URL {
        packDirectory(for: descriptor).appendingPathComponent(descriptor.fileName)
    }

    public static func defaultBaseDirectory(fileManager: FileManager = .default) -> URL {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("AstroNatalEngine", isDirectory: true)
        #else
        let home = fileManager.homeDirectoryForCurrentUser
        let localShare = home.appendingPathComponent(".local/share", isDirectory: true)
        return localShare.appendingPathComponent("AstroNatalEngine", isDirectory: true)
        #endif
    }
}

public extension EngineDataManifest {
    func derivedDataVersions() -> EngineDataVersions {
        let ephemeris = pack(namedPrefix: "ephemeris")?.fileName ?? "unknown"
        let timeCore = pack(namedPrefix: "time-core")
            .map { versionSuffix(from: $0.id, prefix: "time-core-") ?? engineDataVersion }
            ?? engineDataVersion
        let tzdb = pack(namedPrefix: "tzdb").flatMap { versionSuffix(from: $0.id, prefix: "tzdb-") }
        let eop = pack(namedPrefix: "eop").flatMap { versionSuffix(from: $0.id, prefix: "eop-") }
        return EngineDataVersions(ephemeris: ephemeris, timeCore: timeCore, tzdb: tzdb, eop: eop)
    }

    func pack(namedPrefix prefix: String) -> DataPackDescriptor? {
        packs.first(where: { $0.id.hasPrefix(prefix) })
    }

    private func versionSuffix(from id: String, prefix: String) -> String? {
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }
}
