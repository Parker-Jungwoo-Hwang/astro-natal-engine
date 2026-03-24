import Foundation
import AstroSchemas
import AstroTime
import AstroFrames
import AstroHouses
import AstroNatal

public struct Stage9NatalChartComputer: NatalChartComputer {
    private let baseComputer: any NatalChartComputer

    public init(
        ephemerisProvider: any EphemerisProvider,
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: any EarthOrientationProviding,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) {
        self.baseComputer = Stage8NatalChartComputer(
            ephemerisProvider: ephemerisProvider,
            houseComputer: houseComputer,
            timeResolver: timeResolver,
            earthOrientationProvider: earthOrientationProvider,
            aspectCalculator: aspectCalculator
        )
    }

    public init(baseComputer: any NatalChartComputer) {
        self.baseComputer = baseComputer
    }

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        try await baseComputer.generate(request: request, environment: environment)
    }
}
