import Foundation
import AstroSchemas

public struct HouseComputation: Sendable, Equatable {
    public let angles: AnglesResponse
    public let houseResult: HouseResult

    public init(angles: AnglesResponse, houseResult: HouseResult) {
        self.angles = angles
        self.houseResult = houseResult
    }
}

public protocol AngleHouseComputing: Sendable {
    func compute(_ context: HouseContext) throws -> HouseComputation
}

public struct PlacidusHouseSolver: HouseSolver, AngleHouseComputing {
    public init() {}

    public func solve(_ context: HouseContext) throws -> HouseResult {
        try compute(context).houseResult
    }

    public func compute(_ context: HouseContext) throws -> HouseComputation {
        switch context.system {
        case .equal:
            return computeEqual(context)
        case .placidus:
            return try computePlacidus(context)
        }
    }

    private func computeEqual(_ context: HouseContext, fallbackApplied: Bool = false) -> HouseComputation {
        let angles = computeAngles(for: context)
        let cusps = (0..<12).map { normalizeDegrees(angles.asc + Double($0) * 30.0) }
        return HouseComputation(
            angles: angles,
            houseResult: HouseResult(
                system: .equal,
                cusps: cusps,
                fallbackApplied: fallbackApplied,
                iterations: 0
            )
        )
    }

    private func computePlacidus(_ context: HouseContext) throws -> HouseComputation {
        let angles = computeAngles(for: context)
        let obliquity = meanObliquityDegrees(julianDayUT: context.julianDayUT)
        let placidusLatitudeLimit = 90.0 - obliquity
        guard abs(context.latitude) < placidusLatitudeLimit else {
            return computeEqual(context, fallbackApplied: true)
        }

        let cusp11 = findPlacidusRoot(targetPAF: 1.0 / 3.0, preferredHourAngleSign: .plus, context: context)
        let cusp12 = findPlacidusRoot(targetPAF: 2.0 / 3.0, preferredHourAngleSign: .plus, context: context)
        let cusp9 = findPlacidusRoot(targetPAF: -1.0 / 3.0, preferredHourAngleSign: .minus, context: context)
        let cusp8 = findPlacidusRoot(targetPAF: -2.0 / 3.0, preferredHourAngleSign: .minus, context: context)

        guard let cusp11, let cusp12, let cusp9, let cusp8 else {
            return computeEqual(context, fallbackApplied: true)
        }

        let cusps = [
            angles.asc,
            normalizeDegrees(cusp8 + 180.0),
            normalizeDegrees(cusp9 + 180.0),
            angles.ic,
            normalizeDegrees(cusp11 + 180.0),
            normalizeDegrees(cusp12 + 180.0),
            angles.dc,
            cusp8,
            cusp9,
            angles.mc,
            cusp11,
            cusp12
        ]

        guard houseSequenceIsUsable(cusps) else {
            return computeEqual(context, fallbackApplied: true)
        }

        return HouseComputation(
            angles: angles,
            houseResult: HouseResult(
                system: .placidus,
                cusps: cusps,
                fallbackApplied: false,
                iterations: 16
            )
        )
    }

    private func computeAngles(for context: HouseContext) -> AnglesResponse {
        let ramc = localSiderealTimeDegrees(
            julianDayUT: context.julianDayUT,
            dut1Seconds: context.dut1Seconds,
            longitude: context.longitude
        )
        let obliquity = meanObliquityDegrees(julianDayUT: context.julianDayUT)

        let ramcRadians = radians(ramc)
        let obliquityRadians = radians(obliquity)
        let latitudeRadians = radians(context.latitude)

        let mc = normalizeDegrees(
            degrees(
                atan2(
                    sin(ramcRadians),
                    cos(ramcRadians) * cos(obliquityRadians)
                )
            )
        )

        var asc = normalizeDegrees(
            degrees(
                atan2(
                    -cos(ramcRadians),
                    tan(latitudeRadians) * sin(obliquityRadians) + sin(ramcRadians) * cos(obliquityRadians)
                )
            )
        )

        if arcDistance(from: mc, to: asc) > 180.0 {
            asc = normalizeDegrees(asc + 180.0)
        }

        return AnglesResponse(
            asc: asc,
            mc: mc,
            ic: normalizeDegrees(mc + 180.0),
            dc: normalizeDegrees(asc + 180.0)
        )
    }

    private func findPlacidusRoot(
        targetPAF: Double,
        preferredHourAngleSign: FloatingPointSign,
        context: HouseContext
    ) -> Double? {
        let step = 0.25
        var previousLongitude = 0.0
        var previousPAF = placidusPAF(for: previousLongitude, context: context)
        var candidates: [Double] = []

        var longitude = step
        while longitude <= 360.0 {
            let currentPAF = placidusPAF(for: longitude, context: context)

            if let previousPAF, let currentPAF {
                let previousDelta = previousPAF - targetPAF
                let currentDelta = currentPAF - targetPAF

                if abs(previousDelta) < 1e-8 {
                    candidates.append(normalizeDegrees(previousLongitude))
                } else if previousDelta.sign != currentDelta.sign, abs(currentPAF - previousPAF) < 0.5 {
                    candidates.append(
                        bisectRoot(
                            lower: previousLongitude,
                            upper: longitude,
                            targetPAF: targetPAF,
                            context: context
                        )
                    )
                }
            }

            previousLongitude = longitude
            previousPAF = currentPAF
            longitude += step
        }

        let uniqueCandidates = deduplicateAngles(candidates)
        return uniqueCandidates.first(where: { candidate in
            guard let metric = rawMetric(for: candidate, context: context) else { return false }
            return metric.aboveHorizon && metric.hourAngle.sign == preferredHourAngleSign
        })
    }

    private func bisectRoot(lower: Double, upper: Double, targetPAF: Double, context: HouseContext) -> Double {
        var low = lower
        var high = upper

        for _ in 0..<24 {
            let midpoint = (low + high) / 2.0
            guard
                let lowValue = placidusPAF(for: low, context: context),
                let midValue = placidusPAF(for: midpoint, context: context)
            else {
                break
            }

            let lowDelta = lowValue - targetPAF
            let midDelta = midValue - targetPAF

            if abs(midDelta) < 1e-9 {
                return normalizeDegrees(midpoint)
            }

            if lowDelta.sign == midDelta.sign {
                low = midpoint
            } else {
                high = midpoint
            }
        }

        return normalizeDegrees((low + high) / 2.0)
    }

    private func placidusPAF(for longitude: Double, context: HouseContext) -> Double? {
        guard let metric = rawMetric(for: longitude, context: context) else {
            return nil
        }

        if metric.aboveHorizon {
            return metric.hourAngle / metric.diurnalSemiArc
        }

        guard let oppositionMetric = rawMetric(for: longitude + 180.0, context: context), oppositionMetric.aboveHorizon else {
            return nil
        }

        return oppositionMetric.hourAngle / oppositionMetric.diurnalSemiArc
    }

    private func rawMetric(for longitude: Double, context: HouseContext) -> PlacidusMetric? {
        let normalizedLongitude = normalizeDegrees(longitude)
        let ramc = localSiderealTimeDegrees(
            julianDayUT: context.julianDayUT,
            dut1Seconds: context.dut1Seconds,
            longitude: context.longitude
        )
        let obliquity = meanObliquityDegrees(julianDayUT: context.julianDayUT)

        let rightAscension = rightAscensionDegrees(longitude: normalizedLongitude, obliquityDegrees: obliquity)
        let diurnalArgument = sin(radians(rightAscension)) * tan(radians(obliquity)) * tan(radians(context.latitude))

        guard abs(diurnalArgument) <= 1.0 else {
            return nil
        }

        let diurnalSemiArc = 90.0 + degrees(asin(diurnalArgument))
        let hourAngle = normalizeSignedDegrees(rightAscension - ramc)

        return PlacidusMetric(
            hourAngle: hourAngle,
            diurnalSemiArc: diurnalSemiArc,
            aboveHorizon: abs(hourAngle) <= diurnalSemiArc + 1e-8
        )
    }

    private func houseSequenceIsUsable(_ cusps: [Double]) -> Bool {
        guard cusps.count == 12 else { return false }
        for index in 0..<cusps.count {
            let next = cusps[(index + 1) % cusps.count]
            let span = arcDistance(from: cusps[index], to: next)
            if span <= 0 || span >= 180 {
                return false
            }
        }
        return true
    }

    private func deduplicateAngles(_ angles: [Double]) -> [Double] {
        var result: [Double] = []

        for angle in angles.map(normalizeDegrees).sorted() {
            if result.contains(where: { abs(normalizeSignedDegrees($0 - angle)) < 1e-3 }) {
                continue
            }
            result.append(angle)
        }

        return result
    }

    private func localSiderealTimeDegrees(julianDayUT: Double, longitude: Double) -> Double {
        localSiderealTimeDegrees(julianDayUT: julianDayUT, dut1Seconds: nil, longitude: longitude)
    }

    private func localSiderealTimeDegrees(julianDayUT: Double, dut1Seconds: Double?, longitude: Double) -> Double {
        let ut1JulianDay = julianDayUT + (dut1Seconds ?? 0.0) / 86_400.0
        let t = (ut1JulianDay - 2_451_545.0) / 36_525.0
        let gmst =
            280.46061837 +
            360.98564736629 * (ut1JulianDay - 2_451_545.0) +
            0.000387933 * t * t -
            (t * t * t) / 38_710_000.0
        return normalizeDegrees(gmst + longitude)
    }

    private func rightAscensionDegrees(longitude: Double, obliquityDegrees: Double) -> Double {
        let longitudeRadians = radians(longitude)
        let obliquityRadians = radians(obliquityDegrees)

        return normalizeDegrees(
            degrees(
                atan2(
                    sin(longitudeRadians) * cos(obliquityRadians),
                    cos(longitudeRadians)
                )
            )
        )
    }

    private func meanObliquityDegrees(julianDayUT: Double) -> Double {
        let t = (julianDayUT - 2_451_545.0) / 36_525.0
        let seconds = 84_381.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t
        return seconds / 3_600.0
    }

    private func normalizeDegrees(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        return normalized >= 0 ? normalized : normalized + 360.0
    }

    private func normalizeSignedDegrees(_ degrees: Double) -> Double {
        let normalized = normalizeDegrees(degrees)
        return normalized > 180.0 ? normalized - 360.0 : normalized
    }

    private func arcDistance(from start: Double, to end: Double) -> Double {
        normalizeDegrees(end - start)
    }

    private func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private func degrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}

public enum HouseAssignment {
    public static func house(for longitude: Double, cusps: [Double]) -> Int {
        guard cusps.count == 12 else { return 0 }
        let normalizedLongitude = normalizeDegrees(longitude)

        for index in 0..<cusps.count {
            let start = normalizeDegrees(cusps[index])
            let end = normalizeDegrees(cusps[(index + 1) % cusps.count])
            let span = normalizeDegrees(end - start)
            let offset = normalizeDegrees(normalizedLongitude - start)

            if offset < span || abs(offset - span) < 1e-8 {
                return index + 1
            }
        }

        return 12
    }

    public static func assigning(_ bodies: BodiesResponse, cusps: [Double]) -> BodiesResponse {
        var result = bodies

        for body in BodyID.allCases {
            guard let position = result[body] else { continue }
            result[body] = BodyPosition(
                longitude: position.longitude,
                latitude: position.latitude,
                speedLongitude: position.speedLongitude,
                retrograde: position.retrograde,
                sign: position.sign,
                house: house(for: position.longitude, cusps: cusps)
            )
        }

        return result
    }

    private static func normalizeDegrees(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        return normalized >= 0 ? normalized : normalized + 360.0
    }
}

private struct PlacidusMetric {
    let hourAngle: Double
    let diurnalSemiArc: Double
    let aboveHorizon: Bool
}
