import Foundation
import AstroSchemas
import AstroTime
import AstroFrames
import AstroHouses
import AstroNatal

public struct Stage7NatalChartComputer: NatalChartComputer {
    private let bodyPositionCalculator: any BodyPositionComputing
    private let houseComputer: any AngleHouseComputing
    private let timeResolver: StrictTimeResolver
    private let earthOrientationProvider: (any EarthOrientationProviding)?
    private let aspectCalculator: any AspectCalculating

    public init(
        ephemerisProvider: any EphemerisProvider,
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) {
        self.bodyPositionCalculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: ephemerisProvider)
        self.houseComputer = houseComputer
        self.timeResolver = timeResolver
        self.earthOrientationProvider = earthOrientationProvider
        self.aspectCalculator = aspectCalculator
    }

    public init(
        bodyPositionCalculator: any BodyPositionComputing,
        houseComputer: any AngleHouseComputing = PlacidusHouseSolver(),
        timeResolver: StrictTimeResolver = StrictTimeResolver(),
        earthOrientationProvider: (any EarthOrientationProviding)? = nil,
        aspectCalculator: any AspectCalculating = StandardAspectCalculator()
    ) {
        self.bodyPositionCalculator = bodyPositionCalculator
        self.houseComputer = houseComputer
        self.timeResolver = timeResolver
        self.earthOrientationProvider = earthOrientationProvider
        self.aspectCalculator = aspectCalculator
    }

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        let resolvedTime = try timeResolver.resolve(request.birth)
        // Stage 7 is the first point where UT1-sensitive data can change the chart
        // payload without changing the birth instant itself: dUT1 only feeds the
        // sidereal-time house calculation and the presence/absence of the warning.
        let dut1Seconds = try earthOrientationProvider?.dut1Seconds(forJulianDayUTC: resolvedTime.julianDayUTC)
        let baseBodies = try bodyPositionCalculator.bodies(at: resolvedTime)
        let houseComputation = try houseComputer.compute(
            HouseContext(
                julianDayUT: resolvedTime.julianDayUTC,
                dut1Seconds: dut1Seconds,
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                system: .placidus
            )
        )
        let assignedBodies = HouseAssignment.assigning(baseBodies, cusps: houseComputation.houseResult.cusps)
        let aspects = try aspectCalculator.aspects(from: assignedBodies, profile: request.profile)

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
                dut1Seconds: dut1Seconds
            ),
            angles: houseComputation.angles,
            houses: HousesResponse(
                system: houseComputation.houseResult.system,
                cusps: houseComputation.houseResult.cusps
            ),
            bodies: assignedBodies,
            aspects: aspects,
            warnings: buildWarnings(
                for: request,
                houseResult: houseComputation.houseResult,
                dut1Seconds: dut1Seconds
            )
        )
    }

    private func buildWarnings(
        for request: ResolvedBirthRequest,
        houseResult: HouseResult,
        dut1Seconds: Double?
    ) -> [EngineWarning] {
        var warnings: [EngineWarning] = []

        if dut1Seconds == nil {
            warnings.append(
                EngineWarning(
                    code: .standardModeWithoutEOP,
                    message: "Calculated in standardNatal mode without UT1 correction."
                )
            )
        }

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
