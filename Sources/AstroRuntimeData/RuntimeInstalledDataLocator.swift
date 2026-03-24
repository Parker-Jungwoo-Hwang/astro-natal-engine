import Foundation
import AstroSchemas

public struct RuntimeInstalledDataLocator: Sendable {
    private let layout: PackStorageLayout

    public init(
        layout: PackStorageLayout = PackStorageLayout(baseDirectory: PackStorageLayout.defaultBaseDirectory())
    ) {
        self.layout = layout
    }

    public func installedPackURL(namedPrefix prefix: String) throws -> URL? {
        // Prefix lookup is intentionally manifest-driven rather than directory-driven:
        // Stage 10/12 need the pack the current manifest named, not just any file
        // under `packs/` that happens to look similar.
        guard let manifest = try loadLocalManifestIfPresent() else {
            return nil
        }

        guard let descriptor = manifest.pack(namedPrefix: prefix) else {
            return nil
        }

        let packURL = layout.packFileURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: packURL.path) else {
            return nil
        }

        return packURL
    }

    public func requiredInstalledPackURL(namedPrefix prefix: String) throws -> URL {
        if let url = try installedPackURL(namedPrefix: prefix) {
            return url
        }
        throw NatalEngineError.missingRequiredPack(prefix)
    }

    private func loadLocalManifestIfPresent() throws -> EngineDataManifest? {
        guard FileManager.default.fileExists(atPath: layout.manifestFileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: layout.manifestFileURL)
        } catch {
            throw NatalEngineError.fileSystemFailure(error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(EngineDataManifest.self, from: data)
        } catch {
            throw NatalEngineError.manifestInvalid(error.localizedDescription)
        }
    }
}
