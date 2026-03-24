import Foundation
import AstroSchemas
import AstroTime

public protocol BodyPositionComputing: Sendable {
    func bodyPosition(for body: BodyID, at resolvedTime: ResolvedTime) throws -> BodyPosition
    func bodies(at resolvedTime: ResolvedTime) throws -> BodiesResponse
}

public struct TropicalGeocentricBodyPositionCalculator: BodyPositionComputing {
    // Stage computers change chart fidelity almost entirely by swapping this mode.
    // Houses/aspects stay the same; only the geocentric reduction path and how
    // longitude speed is estimated differ across Stage 4, 8, and 12.
    public enum ReductionMode: Sendable {
        case meanOfDate
        case apparentOfDate
        case highAccuracyApparentOfDate
    }

    public let ephemerisProvider: any EphemerisProvider
    public let reductionMode: ReductionMode

    public init(
        ephemerisProvider: any EphemerisProvider,
        reductionMode: ReductionMode = .meanOfDate
    ) {
        self.ephemerisProvider = ephemerisProvider
        self.reductionMode = reductionMode
    }

    public func bodyPosition(for body: BodyID, at resolvedTime: ResolvedTime) throws -> BodyPosition {
        let sample = try sampleCoordinates(
            body: body,
            julianDayTT: resolvedTime.julianDayTT,
            julianDayTDB: resolvedTime.julianDayTDB
        )

        let speedLongitude: Double
        switch reductionMode {
        case .meanOfDate:
            let eclipticState = try meanEclipticState(
                body: body,
                julianDayTT: resolvedTime.julianDayTT,
                julianDayTDB: resolvedTime.julianDayTDB
            )
            let xyRadiusSquared =
                eclipticState.position.x * eclipticState.position.x +
                eclipticState.position.y * eclipticState.position.y
            guard xyRadiusSquared > 0 else {
                throw NatalEngineError.malformedRequest("Geocentric state collapsed to the ecliptic pole.")
            }
            let longitudeRateRadiansPerSecond =
                (
                    eclipticState.position.x * eclipticState.velocity.y -
                    eclipticState.position.y * eclipticState.velocity.x
                ) / xyRadiusSquared
            speedLongitude = longitudeRateRadiansPerSecond * 180.0 / .pi * 86_400.0
        case .apparentOfDate, .highAccuracyApparentOfDate:
            let derivativeStepDays = 60.0 / 86_400.0
            let previous = try sampleCoordinates(
                body: body,
                julianDayTT: resolvedTime.julianDayTT - derivativeStepDays,
                julianDayTDB: resolvedTime.julianDayTDB - derivativeStepDays
            )
            let next = try sampleCoordinates(
                body: body,
                julianDayTT: resolvedTime.julianDayTT + derivativeStepDays,
                julianDayTDB: resolvedTime.julianDayTDB + derivativeStepDays
            )
            speedLongitude = angularDeltaDegrees(from: previous.longitude, to: next.longitude) / (2.0 * derivativeStepDays)
        }

        return BodyPosition(
            longitude: sample.longitude,
            latitude: sample.latitude,
            speedLongitude: speedLongitude,
            retrograde: speedLongitude < 0,
            sign: zodiacSign(for: sample.longitude),
            house: 0
        )
    }

    public func bodies(at resolvedTime: ResolvedTime) throws -> BodiesResponse {
        var result = BodiesResponse.empty
        for body in BodyID.allCases {
            result[body] = try bodyPosition(for: body, at: resolvedTime)
        }
        return result
    }

    private func zodiacSign(for longitude: Double) -> ZodiacSign {
        let normalized = normalizeDegrees(longitude)
        let index = min(Int(normalized / 30.0), ZodiacSign.allCases.count - 1)
        return ZodiacSign.allCases[index]
    }

    private func sampleCoordinates(
        body: BodyID,
        julianDayTT: Double,
        julianDayTDB: Double
    ) throws -> (longitude: Double, latitude: Double) {
        let eclipticPosition = try sampleEclipticPosition(
            body: body,
            julianDayTT: julianDayTT,
            julianDayTDB: julianDayTDB
        )

        let longitude = normalizeDegrees(atan2(eclipticPosition.y, eclipticPosition.x) * 180.0 / .pi)
        let latitude = atan2(
            eclipticPosition.z,
            hypot(eclipticPosition.x, eclipticPosition.y)
        ) * 180.0 / .pi

        return (longitude, latitude)
    }

    private func meanEclipticState(
        body: BodyID,
        julianDayTT: Double,
        julianDayTDB: Double
    ) throws -> CartesianStateVector {
        let geocentricJ2000 = try rawGeocentricState(body: body, julianDayTDB: julianDayTDB)
        let geocentricOfDate = geocentricJ2000.precessedToMeanEquatorOfDate(julianDayTT: julianDayTT)
        return geocentricOfDate.rotatedToMeanEclipticOfDate(julianDayTT: julianDayTT)
    }

    private func sampleEclipticPosition(
        body: BodyID,
        julianDayTT: Double,
        julianDayTDB: Double
    ) throws -> CartesianVector {
        switch reductionMode {
        case .meanOfDate:
            return try meanEclipticState(
                body: body,
                julianDayTT: julianDayTT,
                julianDayTDB: julianDayTDB
            ).position
        case .apparentOfDate:
            // Stage 8 keeps the same kernel inputs but adds one-pass light-time and
            // simple aberration/nutation corrections before house assignment.
            let apparentJ2000 = try apparentGeocentricState(body: body, julianDayTDB: julianDayTDB)
            let geocentricOfDate = apparentJ2000.precessedToMeanEquatorOfDate(julianDayTT: julianDayTT)
            let nutation = NutationAngles.approximate(julianDayTT: julianDayTT)
            return geocentricOfDate.rotatedToApparentEclipticOfDate(nutation: nutation).position
        case .highAccuracyApparentOfDate:
            // Stage 12 upgrades only the apparent reduction fidelity. Stage 10's
            // runtime-loaded kernel and Stage 7's EOP-aware house/aspect pipeline
            // remain intact around this higher-accuracy sample.
            let apparentJ2000 = try highAccuracyApparentGeocentricState(body: body, julianDayTDB: julianDayTDB)
            let geocentricOfDate = apparentJ2000.precessedToMeanEquatorOfDate(julianDayTT: julianDayTT)
            let nutation = NutationAngles.truncatedIAU1980(julianDayTT: julianDayTT)
            return geocentricOfDate.rotatedToApparentEclipticOfDate(nutation: nutation).position
        }
    }

    private func rawGeocentricState(body: BodyID, julianDayTDB: Double) throws -> CartesianStateVector {
        // `EphemerisProvider` returns barycentric J2000 states; subtracting Earth is
        // the contract boundary where the engine turns kernel output into observer-
        // centric coordinates that every later reduction mode refines.
        let bodyState = try ephemerisProvider.stateVector(for: body, tdbJulianDay: julianDayTDB)
        let earthState = try ephemerisProvider.earthStateVector(tdbJulianDay: julianDayTDB)
        return CartesianStateVector(bodyState) - CartesianStateVector(earthState)
    }

    private func apparentGeocentricState(body: BodyID, julianDayTDB: Double) throws -> CartesianStateVector {
        let observedEarthState = CartesianStateVector(try ephemerisProvider.earthStateVector(tdbJulianDay: julianDayTDB))
        var bodyState = CartesianStateVector(try ephemerisProvider.stateVector(for: body, tdbJulianDay: julianDayTDB))
        var geocentricState = bodyState - observedEarthState

        let lightTimeDays = geocentricState.position.magnitude / Self.speedOfLightKmPerSecond / 86_400.0
        if lightTimeDays > 0 {
            bodyState = CartesianStateVector(
                try ephemerisProvider.stateVector(for: body, tdbJulianDay: julianDayTDB - lightTimeDays)
            )
            geocentricState = bodyState - observedEarthState
        }

        let observerBeta = observedEarthState.velocity.scaled(by: 1.0 / Self.speedOfLightKmPerSecond)
        let apparentDirection = geocentricState.position.normalized().aberrated(by: observerBeta)
        return CartesianStateVector(
            position: apparentDirection.scaled(by: geocentricState.position.magnitude),
            velocity: geocentricState.velocity
        )
    }

    private func highAccuracyApparentGeocentricState(body: BodyID, julianDayTDB: Double) throws -> CartesianStateVector {
        let observedEarthState = CartesianStateVector(try ephemerisProvider.earthStateVector(tdbJulianDay: julianDayTDB))
        var bodyState = CartesianStateVector(try ephemerisProvider.stateVector(for: body, tdbJulianDay: julianDayTDB))
        var geocentricState = bodyState - observedEarthState

        for _ in 0..<2 {
            let lightTimeDays = geocentricState.position.magnitude / Self.speedOfLightKmPerSecond / 86_400.0
            guard lightTimeDays > 0 else { break }
            bodyState = CartesianStateVector(
                try ephemerisProvider.stateVector(for: body, tdbJulianDay: julianDayTDB - lightTimeDays)
            )
            geocentricState = bodyState - observedEarthState
        }

        let observerBeta = observedEarthState.velocity.scaled(by: 1.0 / Self.speedOfLightKmPerSecond)
        let apparentDirection = geocentricState.position.normalized().relativisticallyAberrated(by: observerBeta)
        return CartesianStateVector(
            position: apparentDirection.scaled(by: geocentricState.position.magnitude),
            velocity: geocentricState.velocity
        )
    }

    private func angularDeltaDegrees(from start: Double, to end: Double) -> Double {
        let delta = normalizeDegrees(end - start)
        return delta > 180.0 ? delta - 360.0 : delta
    }

    private func normalizeDegrees(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        return normalized >= 0 ? normalized : normalized + 360.0
    }

    private static let speedOfLightKmPerSecond = 299_792.458
}

private struct CartesianVector: Sendable {
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    func normalized() -> CartesianVector {
        let length = magnitude
        guard length > 0 else { return self }
        return scaled(by: 1.0 / length)
    }

    func scaled(by factor: Double) -> CartesianVector {
        CartesianVector(x: x * factor, y: y * factor, z: z * factor)
    }

    func rotatedAroundZ(_ radians: Double) -> CartesianVector {
        let cosine = cos(radians)
        let sine = sin(radians)
        return CartesianVector(
            x: cosine * x - sine * y,
            y: sine * x + cosine * y,
            z: z
        )
    }

    func aberrated(by observerBeta: CartesianVector) -> CartesianVector {
        (self + observerBeta).normalized()
    }

    func relativisticallyAberrated(by observerBeta: CartesianVector) -> CartesianVector {
        let betaSquared = observerBeta.dot(observerBeta)
        guard betaSquared > 0 else { return self }

        let gamma = 1.0 / sqrt(max(1.0 - betaSquared, 1e-16))
        let dot = self.dot(observerBeta)
        let scale = gamma / (1.0 + gamma) * dot
        let numerator =
            self.scaled(by: 1.0 / gamma) +
            observerBeta +
            observerBeta.scaled(by: scale)
        let denominator = 1.0 + dot
        return numerator.scaled(by: 1.0 / denominator).normalized()
    }

    func dot(_ other: CartesianVector) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    static func + (lhs: CartesianVector, rhs: CartesianVector) -> CartesianVector {
        CartesianVector(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }
}

private struct CartesianStateVector: Sendable {
    let position: CartesianVector
    let velocity: CartesianVector

    init(_ stateVector: StateVector) {
        self.position = CartesianVector(x: stateVector.positionX, y: stateVector.positionY, z: stateVector.positionZ)
        self.velocity = CartesianVector(x: stateVector.velocityX, y: stateVector.velocityY, z: stateVector.velocityZ)
    }

    init(position: CartesianVector, velocity: CartesianVector) {
        self.position = position
        self.velocity = velocity
    }

    static func - (lhs: CartesianStateVector, rhs: CartesianStateVector) -> CartesianStateVector {
        CartesianStateVector(
            position: CartesianVector(
                x: lhs.position.x - rhs.position.x,
                y: lhs.position.y - rhs.position.y,
                z: lhs.position.z - rhs.position.z
            ),
            velocity: CartesianVector(
                x: lhs.velocity.x - rhs.velocity.x,
                y: lhs.velocity.y - rhs.velocity.y,
                z: lhs.velocity.z - rhs.velocity.z
            )
        )
    }

    func precessedToMeanEquatorOfDate(julianDayTT: Double) -> CartesianStateVector {
        let matrix = PrecessionMatrix(julianDayTT: julianDayTT)
        return CartesianStateVector(
            position: matrix.apply(to: position),
            velocity: matrix.apply(to: velocity)
        )
    }

    func rotatedToMeanEclipticOfDate(julianDayTT: Double) -> CartesianStateVector {
        rotatedToEcliptic(obliquityRadians: meanObliquityRadians(julianDayTT: julianDayTT))
    }

    func rotatedToApparentEclipticOfDate(nutation: NutationAngles) -> CartesianStateVector {
        let ecliptic = rotatedToEcliptic(obliquityRadians: nutation.trueObliquityRadians)
        return CartesianStateVector(
            position: ecliptic.position.rotatedAroundZ(nutation.deltaPsiRadians),
            velocity: ecliptic.velocity.rotatedAroundZ(nutation.deltaPsiRadians)
        )
    }

    private func rotatedToEcliptic(obliquityRadians epsilon: Double) -> CartesianStateVector {
        let cosEpsilon = cos(epsilon)
        let sinEpsilon = sin(epsilon)

        return CartesianStateVector(
            position: CartesianVector(
                x: position.x,
                y: cosEpsilon * position.y + sinEpsilon * position.z,
                z: -sinEpsilon * position.y + cosEpsilon * position.z
            ),
            velocity: CartesianVector(
                x: velocity.x,
                y: cosEpsilon * velocity.y + sinEpsilon * velocity.z,
                z: -sinEpsilon * velocity.y + cosEpsilon * velocity.z
            )
        )
    }

    private func meanObliquityRadians(julianDayTT: Double) -> Double {
        let t = (julianDayTT - 2_451_545.0) / 36_525.0
        let seconds = 84_381.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t
        return seconds / 3_600.0 * .pi / 180.0
    }
}

private struct NutationAngles {
    let deltaPsiRadians: Double
    let deltaEpsilonRadians: Double
    let trueObliquityRadians: Double

    static func approximate(julianDayTT: Double) -> NutationAngles {
        let t = (julianDayTT - 2_451_545.0) / 36_525.0
        let daysSinceJ2000 = julianDayTT - 2_451_545.0

        let omega = (125.04452 - 1_934.136261 * t).truncatingRemainder(dividingBy: 360.0)
        let sunMeanLongitude = (280.4665 + 36_000.7698 * t).truncatingRemainder(dividingBy: 360.0)
        let moonMeanLongitude = (218.3165 + 481_267.8813 * t).truncatingRemainder(dividingBy: 360.0)

        let deltaPsiArcseconds =
            -17.20 * sin(omega * .pi / 180.0) -
            1.32 * sin(2.0 * sunMeanLongitude * .pi / 180.0) -
            0.23 * sin(2.0 * moonMeanLongitude * .pi / 180.0) +
            0.21 * sin(2.0 * omega * .pi / 180.0)

        let deltaEpsilonArcseconds =
            9.20 * cos(omega * .pi / 180.0) +
            0.57 * cos(2.0 * sunMeanLongitude * .pi / 180.0) +
            0.10 * cos(2.0 * moonMeanLongitude * .pi / 180.0) -
            0.09 * cos(2.0 * omega * .pi / 180.0)

        let meanObliquityDegrees = 23.4393 - 0.0000004 * daysSinceJ2000
        let deltaPsiRadians = deltaPsiArcseconds / 3_600.0 * .pi / 180.0
        let deltaEpsilonRadians = deltaEpsilonArcseconds / 3_600.0 * .pi / 180.0
        let trueObliquityRadians = meanObliquityDegrees * .pi / 180.0 + deltaEpsilonRadians

        return NutationAngles(
            deltaPsiRadians: deltaPsiRadians,
            deltaEpsilonRadians: deltaEpsilonRadians,
            trueObliquityRadians: trueObliquityRadians
        )
    }

    static func truncatedIAU1980(julianDayTT: Double) -> NutationAngles {
        let t = (julianDayTT - 2_451_545.0) / 36_525.0

        let d = normalizedRadians(297.85036 + 445_267.111480 * t - 0.0019142 * t * t + t * t * t / 189_474.0)
        let m = normalizedRadians(357.52772 + 35_999.050340 * t - 0.0001603 * t * t - t * t * t / 300_000.0)
        let mp = normalizedRadians(134.96298 + 477_198.867398 * t + 0.0086972 * t * t + t * t * t / 56_250.0)
        let f = normalizedRadians(93.27191 + 483_202.017538 * t - 0.0036825 * t * t + t * t * t / 327_270.0)
        let omega = normalizedRadians(125.04452 - 1_934.136261 * t + 0.0020708 * t * t + t * t * t / 450_000.0)

        var deltaPsiUnits = 0.0
        var deltaEpsilonUnits = 0.0
        for term in highAccuracyTerms {
            let argument =
                Double(term.d) * d +
                Double(term.m) * m +
                Double(term.mp) * mp +
                Double(term.f) * f +
                Double(term.omega) * omega
            deltaPsiUnits += (term.sin0 + term.sin1 * t) * sin(argument)
            deltaEpsilonUnits += (term.cos0 + term.cos1 * t) * cos(argument)
        }

        let meanObliquityArcseconds =
            84_381.448 -
            46.8150 * t -
            0.00059 * t * t +
            0.001813 * t * t * t
        let deltaPsiRadians = deltaPsiUnits * 1e-4 / 3_600.0 * .pi / 180.0
        let deltaEpsilonRadians = deltaEpsilonUnits * 1e-4 / 3_600.0 * .pi / 180.0
        let trueObliquityRadians = meanObliquityArcseconds / 3_600.0 * .pi / 180.0 + deltaEpsilonRadians

        return NutationAngles(
            deltaPsiRadians: deltaPsiRadians,
            deltaEpsilonRadians: deltaEpsilonRadians,
            trueObliquityRadians: trueObliquityRadians
        )
    }

    private static func normalizedRadians(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        let adjusted = normalized >= 0 ? normalized : normalized + 360.0
        return adjusted * .pi / 180.0
    }

    private static let highAccuracyTerms: [NutationTerm] = [
        NutationTerm(d: 0, m: 0, mp: 0, f: 0, omega: 1, sin0: -171_996.0, sin1: -174.2, cos0: 92_025.0, cos1: 8.9),
        NutationTerm(d: -2, m: 0, mp: 0, f: 2, omega: 2, sin0: -13_187.0, sin1: -1.6, cos0: 5_736.0, cos1: -3.1),
        NutationTerm(d: 0, m: 0, mp: 0, f: 2, omega: 2, sin0: -2_274.0, sin1: -0.2, cos0: 977.0, cos1: -0.5),
        NutationTerm(d: 0, m: 0, mp: 0, f: 0, omega: 2, sin0: 2_062.0, sin1: 0.2, cos0: -895.0, cos1: 0.5),
        NutationTerm(d: 0, m: 1, mp: 0, f: 0, omega: 0, sin0: 1_426.0, sin1: -3.4, cos0: 54.0, cos1: -0.1),
        NutationTerm(d: 0, m: 0, mp: 1, f: 0, omega: 0, sin0: 712.0, sin1: 0.1, cos0: -7.0, cos1: 0.0),
        NutationTerm(d: -2, m: 1, mp: 0, f: 2, omega: 2, sin0: -517.0, sin1: 1.2, cos0: 224.0, cos1: -0.6),
        NutationTerm(d: 0, m: 0, mp: 0, f: 2, omega: 1, sin0: -386.0, sin1: -0.4, cos0: 200.0, cos1: 0.0),
        NutationTerm(d: 0, m: 0, mp: 1, f: 2, omega: 2, sin0: -301.0, sin1: 0.0, cos0: 129.0, cos1: -0.1),
        NutationTerm(d: -2, m: -1, mp: 0, f: 2, omega: 2, sin0: 217.0, sin1: -0.5, cos0: -95.0, cos1: 0.3),
        NutationTerm(d: -2, m: 0, mp: 1, f: 0, omega: 0, sin0: -158.0, sin1: 0.0, cos0: 0.0, cos1: 0.0),
        NutationTerm(d: -2, m: 0, mp: 0, f: 2, omega: 1, sin0: 129.0, sin1: 0.1, cos0: -70.0, cos1: 0.0),
        NutationTerm(d: 0, m: 0, mp: -1, f: 2, omega: 2, sin0: 123.0, sin1: 0.0, cos0: -53.0, cos1: 0.0),
        NutationTerm(d: 2, m: 0, mp: 0, f: 0, omega: 0, sin0: 63.0, sin1: 0.0, cos0: 0.0, cos1: 0.0),
        NutationTerm(d: 0, m: 0, mp: 1, f: 0, omega: 1, sin0: 63.0, sin1: 0.1, cos0: -33.0, cos1: 0.0),
        NutationTerm(d: 2, m: 0, mp: -1, f: 2, omega: 2, sin0: -59.0, sin1: 0.0, cos0: 26.0, cos1: 0.0),
        NutationTerm(d: 0, m: 0, mp: -1, f: 0, omega: 1, sin0: -58.0, sin1: -0.1, cos0: 32.0, cos1: 0.0),
        NutationTerm(d: 0, m: 0, mp: 1, f: 2, omega: 1, sin0: -51.0, sin1: 0.0, cos0: 27.0, cos1: 0.0),
        NutationTerm(d: -2, m: 0, mp: 2, f: 0, omega: 0, sin0: 48.0, sin1: 0.0, cos0: 0.0, cos1: 0.0),
        NutationTerm(d: 0, m: 0, mp: -2, f: 2, omega: 1, sin0: 46.0, sin1: 0.0, cos0: -24.0, cos1: 0.0)
    ]
}

private struct NutationTerm {
    let d: Int
    let m: Int
    let mp: Int
    let f: Int
    let omega: Int
    let sin0: Double
    let sin1: Double
    let cos0: Double
    let cos1: Double
}

private struct PrecessionMatrix {
    let m11: Double
    let m12: Double
    let m13: Double
    let m21: Double
    let m22: Double
    let m23: Double
    let m31: Double
    let m32: Double
    let m33: Double

    init(julianDayTT: Double) {
        let t = (julianDayTT - 2_451_545.0) / 36_525.0
        let arcsecondsToRadians = .pi / (180.0 * 3_600.0)

        let zeta = (2_306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsecondsToRadians
        let z = (2_306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsecondsToRadians
        let theta = (2_004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsecondsToRadians

        let czeta = cos(zeta)
        let szeta = sin(zeta)
        let cz = cos(z)
        let sz = sin(z)
        let ctheta = cos(theta)
        let stheta = sin(theta)

        self.m11 = czeta * ctheta * cz - szeta * sz
        self.m12 = -szeta * ctheta * cz - czeta * sz
        self.m13 = -stheta * cz
        self.m21 = czeta * ctheta * sz + szeta * cz
        self.m22 = -szeta * ctheta * sz + czeta * cz
        self.m23 = -stheta * sz
        self.m31 = czeta * stheta
        self.m32 = -szeta * stheta
        self.m33 = ctheta
    }

    func apply(to vector: CartesianVector) -> CartesianVector {
        CartesianVector(
            x: m11 * vector.x + m12 * vector.y + m13 * vector.z,
            y: m21 * vector.x + m22 * vector.y + m23 * vector.z,
            z: m31 * vector.x + m32 * vector.y + m33 * vector.z
        )
    }
}
