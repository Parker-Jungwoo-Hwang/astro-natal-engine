import Foundation

enum DE442KernelLocator {
    static func locateKernelURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let environmentPath = environment["ASTRO_DE442_PATH"], !environmentPath.isEmpty {
            let url = URL(fileURLWithPath: environmentPath)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let packsDirectory = applicationSupport
            .appendingPathComponent("AstroNatalEngine", isDirectory: true)
            .appendingPathComponent("packs", isDirectory: true)

        if let enumerator = fileManager.enumerator(
            at: packsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator where url.lastPathComponent == "de442.bsp" {
                return url
            }
        }
        #endif

        return nil
    }
}
