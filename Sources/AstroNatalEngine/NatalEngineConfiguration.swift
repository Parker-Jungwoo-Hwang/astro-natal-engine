import Foundation
import AstroSchemas
import AstroFrames
import AstroHouses
import AstroNatal
import AstroRuntimeData
import AstroEphemeris

public struct NatalEngineConfiguration: Sendable {
    public let engineVersion: String
    public let birthResolver: any BirthResolver
    public let dataPackStore: any DataPackStore
    public let chartComputer: any NatalChartComputer

    public init(
        engineVersion: String = "0.2.0-stage2",
        birthResolver: any BirthResolver,
        dataPackStore: any DataPackStore,
        chartComputer: any NatalChartComputer = StubNatalChartComputer()
    ) {
        self.engineVersion = engineVersion
        self.birthResolver = birthResolver
        self.dataPackStore = dataPackStore
        self.chartComputer = chartComputer
    }
}

public extension NatalEngineConfiguration {
    // The stage factories are intentionally additive: later stages reuse the same
    // data-pack store and only swap in the next computation boundary that became
    // available at that milestone.
    static func stage2(
        engineVersion: String = "0.2.0-stage2",
        manifestURL: URL?,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        chartComputer: any NatalChartComputer = StubNatalChartComputer()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: chartComputer
        )
    }

    static func stage4(
        engineVersion: String = "0.4.0-stage4",
        manifestURL: URL?,
        ephemerisProvider: any EphemerisProvider,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage4NatalChartComputer(
                ephemerisProvider: ephemerisProvider,
                timeResolver: timeResolver
            )
        )
    }

    static func stage1(
        engineVersion: String = "0.1.0-stage1",
        manifestURL: URL?,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        chartComputer: any NatalChartComputer = StubNatalChartComputer()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: chartComputer
        )
    }

    static func stage5(
        engineVersion: String = "0.5.0-stage5",
        manifestURL: URL?,
        ephemerisProvider: any EphemerisProvider,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage5NatalChartComputer(
                ephemerisProvider: ephemerisProvider,
                houseComputer: houseComputer,
                timeResolver: timeResolver
            )
        )
    }

    static func stage6(
        engineVersion: String = "0.6.0-stage6",
        manifestURL: URL?,
        ephemerisProvider: any EphemerisProvider,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage6NatalChartComputer(
                ephemerisProvider: ephemerisProvider,
                houseComputer: houseComputer,
                timeResolver: timeResolver,
                aspectCalculator: aspectCalculator
            )
        )
    }

    static func stage7(
        engineVersion: String = "0.7.0-stage7",
        manifestURL: URL?,
        ephemerisProvider: any EphemerisProvider,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage7NatalChartComputer(
                ephemerisProvider: ephemerisProvider,
                houseComputer: houseComputer,
                timeResolver: timeResolver,
                earthOrientationProvider: earthOrientationProvider,
                aspectCalculator: aspectCalculator
            )
        )
    }

    static func stage8(
        engineVersion: String = "0.8.0-stage8",
        manifestURL: URL?,
        ephemerisProvider: any EphemerisProvider,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage8NatalChartComputer(
                ephemerisProvider: ephemerisProvider,
                houseComputer: houseComputer,
                timeResolver: timeResolver,
                earthOrientationProvider: earthOrientationProvider,
                aspectCalculator: aspectCalculator
            )
        )
    }

    static func stage9(
        engineVersion: String = "0.9.0-stage9",
        manifestURL: URL?,
        ephemerisProvider: any EphemerisProvider,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) -> NatalEngineConfiguration {
        let layout = PackStorageLayout(baseDirectory: baseDirectory)
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: layout,
            httpClient: httpClient,
            options: runtimeDataOptions
        )
        // Stage 9 is the first configuration that expects runtime EOP files to live
        // beside the manifest-managed packs, so the same layout must be shared by
        // the store and the default provider to keep warnings/dataVersions aligned.
        let resolvedEarthOrientationProvider = earthOrientationProvider ?? RuntimeDataEarthOrientationProvider(layout: layout)

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage9NatalChartComputer(
                ephemerisProvider: ephemerisProvider,
                houseComputer: houseComputer,
                timeResolver: timeResolver,
                earthOrientationProvider: resolvedEarthOrientationProvider,
                aspectCalculator: aspectCalculator
            )
        )
    }

    static func stage10(
        engineVersion: String = "0.10.0-stage10",
        manifestURL: URL?,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator(),
        ephemerisProviderLoader: @escaping Stage10NatalChartComputer.EphemerisProviderLoader = { url in
            try JPLEphemerisProvider(kernelURL: url)
        }
    ) -> NatalEngineConfiguration {
        let layout = PackStorageLayout(baseDirectory: baseDirectory)
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: layout,
            httpClient: httpClient,
            options: runtimeDataOptions
        )
        // Stage 10 keeps Stage 9's house/aspect pipeline but moves ephemeris lookup
        // behind the runtime manifest. Reusing the layout here is what lets prepare()
        // install packs that the chart computer can later discover lazily.
        let resolvedEarthOrientationProvider = earthOrientationProvider ?? RuntimeDataEarthOrientationProvider(layout: layout)

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage10NatalChartComputer(
                layout: layout,
                houseComputer: houseComputer,
                timeResolver: timeResolver,
                earthOrientationProvider: resolvedEarthOrientationProvider,
                aspectCalculator: aspectCalculator,
                ephemerisProviderLoader: ephemerisProviderLoader
            )
        )
    }

    static func stage12(
        engineVersion: String = "0.12.0-stage12",
        manifestURL: URL?,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator(),
        ephemerisProviderLoader: @escaping Stage12NatalChartComputer.EphemerisProviderLoader = { url in
            try JPLEphemerisProvider(kernelURL: url)
        }
    ) -> NatalEngineConfiguration {
        let layout = PackStorageLayout(baseDirectory: baseDirectory)
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: layout,
            httpClient: httpClient,
            options: runtimeDataOptions
        )
        // Stage 12 still consumes the same runtime packs as Stage 10; the upgrade is
        // purely in the frame-reduction path, not in how manifests or providers are
        // located.
        let resolvedEarthOrientationProvider = earthOrientationProvider ?? RuntimeDataEarthOrientationProvider(layout: layout)

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: Stage12NatalChartComputer(
                layout: layout,
                houseComputer: houseComputer,
                timeResolver: timeResolver,
                earthOrientationProvider: resolvedEarthOrientationProvider,
                aspectCalculator: aspectCalculator,
                ephemerisProviderLoader: ephemerisProviderLoader
            )
        )
    }
}
