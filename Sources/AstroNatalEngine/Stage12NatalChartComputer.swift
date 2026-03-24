import Foundation
import AstroSchemas
import AstroTime
import AstroFrames
import AstroHouses
import AstroNatal
import AstroRuntimeData
import AstroEphemeris

public struct Stage12NatalChartComputer: NatalChartComputer {
    public typealias EphemerisProviderLoader = @Sendable (URL) throws -> any EphemerisProvider

    private let providerCache: RuntimeHighAccuracyEphemerisProviderCache
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
        self.providerCache = RuntimeHighAccuracyEphemerisProviderCache(
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
        // Stage 12 is intentionally narrow: it keeps Stage 10's runtime ephemeris and
        // Stage 7's UT1-aware orchestration, but swaps the frame calculator to the
        // higher-accuracy apparent reduction path.
        let ephemerisProvider = try await providerCache.provider()
        let delegated = Stage7NatalChartComputer(
            bodyPositionCalculator: TropicalGeocentricBodyPositionCalculator(
                ephemerisProvider: ephemerisProvider,
                reductionMode: .highAccuracyApparentOfDate
            ),
            houseComputer: houseComputer,
            timeResolver: timeResolver,
            earthOrientationProvider: earthOrientationProvider,
            aspectCalculator: aspectCalculator
        )
        return try await delegated.generate(request: request, environment: environment)
    }
}

private actor RuntimeHighAccuracyEphemerisProviderCache {
    private let locator: RuntimeInstalledDataLocator
    private let loader: Stage12NatalChartComputer.EphemerisProviderLoader
    private var cachedProvider: (any EphemerisProvider)?

    init(
        locator: RuntimeInstalledDataLocator,
        loader: @escaping Stage12NatalChartComputer.EphemerisProviderLoader
    ) {
        self.locator = locator
        self.loader = loader
    }

    func provider() throws -> any EphemerisProvider {
        if let cachedProvider {
            return cachedProvider
        }

        let packURL = try locator.requiredInstalledPackURL(namedPrefix: "ephemeris")
        let provider = try loader(packURL)
        cachedProvider = provider
        return provider
    }
}
