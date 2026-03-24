import Foundation
import AstroSchemas
import AstroTime
import AstroFrames
import AstroHouses
import AstroNatal
import AstroRuntimeData
import AstroEphemeris

public struct Stage10NatalChartComputer: NatalChartComputer {
    public typealias EphemerisProviderLoader = @Sendable (URL) throws -> any EphemerisProvider

    private let providerCache: RuntimeEphemerisProviderCache
    private let houseComputer: any AngleHouseComputing
    private let timeResolver: StrictTimeResolver
    private let earthOrientationProvider: any EarthOrientationProviding
    private let aspectCalculator: any AspectCalculating

    public init(
        layout: PackStorageLayout = PackStorageLayout(baseDirectory: PackStorageLayout.defaultBaseDirectory()),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: any EarthOrientationProviding,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator(),
        ephemerisProviderLoader: @escaping EphemerisProviderLoader = { url in
            try JPLEphemerisProvider(kernelURL: url)
        }
    ) {
        self.providerCache = RuntimeEphemerisProviderCache(
            locator: RuntimeInstalledDataLocator(layout: layout),
            loader: ephemerisProviderLoader
        )
        self.houseComputer = houseComputer
        self.timeResolver = timeResolver
        self.earthOrientationProvider = earthOrientationProvider
        self.aspectCalculator = aspectCalculator
    }

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        // Stage 10 does not alter house/aspect logic; it swaps the ephemeris source
        // from caller-injected memory to the manifest-installed runtime pack, then
        // drops back into the already-tested Stage 9 pipeline.
        let ephemerisProvider = try await providerCache.provider()
        let delegated = Stage9NatalChartComputer(
            ephemerisProvider: ephemerisProvider,
            houseComputer: houseComputer,
            timeResolver: timeResolver,
            earthOrientationProvider: earthOrientationProvider,
            aspectCalculator: aspectCalculator
        )
        return try await delegated.generate(request: request, environment: environment)
    }
}

private actor RuntimeEphemerisProviderCache {
    private let locator: RuntimeInstalledDataLocator
    private let loader: Stage10NatalChartComputer.EphemerisProviderLoader
    private var cachedProvider: (any EphemerisProvider)?

    init(
        locator: RuntimeInstalledDataLocator,
        loader: @escaping Stage10NatalChartComputer.EphemerisProviderLoader
    ) {
        self.locator = locator
        self.loader = loader
    }

    func provider() throws -> any EphemerisProvider {
        if let cachedProvider {
            return cachedProvider
        }

        // Loader caching keeps repeated chart requests from reparsing a large kernel,
        // while the manifest-backed locator ensures the cache tracks whatever prepare()
        // most recently installed under the shared runtime layout.
        let packURL = try locator.requiredInstalledPackURL(namedPrefix: "ephemeris")
        let provider = try loader(packURL)
        cachedProvider = provider
        return provider
    }
}
