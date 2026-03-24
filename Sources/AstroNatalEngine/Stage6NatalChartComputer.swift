import Foundation
import AstroSchemas
import AstroTime
import AstroFrames
import AstroHouses
import AstroNatal

public struct Stage6NatalChartComputer: NatalChartComputer {
    private let baseComputer: any NatalChartComputer
    private let aspectCalculator: any AspectCalculating

    public init(
        ephemerisProvider: any EphemerisProvider,
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) {
        self.baseComputer = Stage5NatalChartComputer(
            ephemerisProvider: ephemerisProvider,
            houseComputer: houseComputer,
            timeResolver: timeResolver
        )
        self.aspectCalculator = aspectCalculator
    }

    public init(
        baseComputer: any NatalChartComputer,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) {
        self.baseComputer = baseComputer
        self.aspectCalculator = aspectCalculator
    }

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        let baseResponse = try await baseComputer.generate(request: request, environment: environment)
        let aspects = try aspectCalculator.aspects(from: baseResponse.bodies, profile: request.profile)

        return NatalChartResponse(
            schemaVersion: baseResponse.schemaVersion,
            engineVersion: baseResponse.engineVersion,
            dataVersions: baseResponse.dataVersions,
            profile: baseResponse.profile,
            inputEcho: baseResponse.inputEcho,
            times: baseResponse.times,
            angles: baseResponse.angles,
            houses: baseResponse.houses,
            bodies: baseResponse.bodies,
            aspects: aspects,
            warnings: baseResponse.warnings
        )
    }
}
