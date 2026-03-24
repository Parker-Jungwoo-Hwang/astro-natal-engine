import Foundation
import AstroSchemas
import AstroTime
import AstroFrames
import AstroHouses

public struct Stage5NatalChartComputer: NatalChartComputer {
    private let bodyPositionCalculator: any BodyPositionComputing
    private let houseComputer: any AngleHouseComputing
    private let timeResolver: StrictTimeResolver

    public init(
        ephemerisProvider: any EphemerisProvider,
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver()
    ) {
        self.bodyPositionCalculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: ephemerisProvider)
        self.houseComputer = houseComputer
        self.timeResolver = timeResolver
    }

    public init(
        bodyPositionCalculator: any BodyPositionComputing,
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver()
    ) {
        self.bodyPositionCalculator = bodyPositionCalculator
        self.houseComputer = houseComputer
        self.timeResolver = timeResolver
    }

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        let resolvedTime = try timeResolver.resolve(request.birth)
        let baseBodies = try bodyPositionCalculator.bodies(at: resolvedTime)
        let houseComputation = try houseComputer.compute(
            HouseContext(
                julianDayUT: resolvedTime.julianDayUTC,
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                system: .placidus
            )
        )
        let assignedBodies = HouseAssignment.assigning(baseBodies, cusps: houseComputation.houseResult.cusps)

        return NatalChartResponse(
            engineVersion: environment.engineVersion,
            dataVersions: environment.dataVersions,
            profile: request.profile,
            inputEcho: InputEcho(
                birthLocalDateTime: request.birth.localDateTime,
                timeZoneId: request.birth.timeZoneId,
                utcOffsetMinutesAtBirth: request.birth.utcOffsetMinutesAtBirth,
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                gender: request.subject.gender
            ),
            times: NatalResponseTimes(
                utc: resolvedTime.utc,
                julianDayUTC: resolvedTime.julianDayUTC,
                julianDayTT: resolvedTime.julianDayTT,
                julianDayTDB: resolvedTime.julianDayTDB,
                deltaTSeconds: resolvedTime.deltaTSeconds,
                dut1Seconds: resolvedTime.dut1Seconds
            ),
            angles: houseComputation.angles,
            houses: HousesResponse(
                system: houseComputation.houseResult.system,
                cusps: houseComputation.houseResult.cusps
            ),
            bodies: assignedBodies,
            aspects: [],
            warnings: buildWarnings(for: request, houseResult: houseComputation.houseResult)
        )
    }

    private func buildWarnings(for request: ResolvedBirthRequest, houseResult: HouseResult) -> [EngineWarning] {
        var warnings = [
            EngineWarning(
                code: .standardModeWithoutEOP,
                message: "Calculated in standardNatal mode without UT1 correction."
            )
        ]

        switch request.birth.timePrecision {
        case .day, .hour, .unknown:
            warnings.append(
                EngineWarning(
                    code: .birthTimePrecisionLow,
                    message: "Birth time precision is below minute-level accuracy; body positions may be coarse."
                )
            )
        case .minute, .second:
            break
        }

        if let year = RequestValidator.extractYear(from: request.birth.localDateTime),
           year < 1970,
           !request.birth.timeZoneId.hasPrefix("UTC") {
            warnings.append(
                EngineWarning(
                    code: .pre1970TimezoneBestEffort,
                    message: "Historical timezone resolution before 1970 may rely on best-effort system data."
                )
            )
        }

        if houseResult.fallbackApplied {
            warnings.append(
                EngineWarning(
                    code: .placidusFallbackApplied,
                    message: "Placidus houses were unavailable at this latitude or geometry; equal houses were used instead."
                )
            )
        }

        return warnings
    }
}
