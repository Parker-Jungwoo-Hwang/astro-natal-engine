import XCTest
@testable import AstroFrames
@testable import AstroSchemas
@testable import AstroTime

final class TropicalGeocentricBodyPositionCalculatorTests: XCTestCase {
    func testCalculatorRecoversLongitudeLatitudeAndSpeedAtJ2000() throws {
        let resolvedTime = makeResolvedTime(julianDayUTC: 2_451_544.5, julianDayTT: 2_451_545.0, julianDayTDB: 2_451_545.0)
        let state = makeEquatorialState(longitude: 123.0, latitude: 5.0, speedLongitude: 1.25, julianDayTT: resolvedTime.julianDayTT)
        let provider = MockEphemerisProvider(bodyStates: [.mars: state], earthState: .zero)
        let calculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: provider)

        let position = try calculator.bodyPosition(for: .mars, at: resolvedTime)

        XCTAssertEqual(position.longitude, 123.0, accuracy: 0.001)
        XCTAssertEqual(position.latitude, 5.0, accuracy: 0.001)
        XCTAssertEqual(position.speedLongitude, 1.25, accuracy: 0.001)
        XCTAssertEqual(position.sign, .leo)
        XCTAssertFalse(position.retrograde)
        XCTAssertEqual(position.house, 0)
    }

    func testCalculatorFlagsRetrogradeMotion() throws {
        let resolvedTime = makeResolvedTime(julianDayUTC: 2_451_544.5, julianDayTT: 2_451_545.0, julianDayTDB: 2_451_545.0)
        let state = makeEquatorialState(longitude: 210.0, latitude: 0.0, speedLongitude: -0.45, julianDayTT: resolvedTime.julianDayTT)
        let provider = MockEphemerisProvider(bodyStates: [.venus: state], earthState: .zero)
        let calculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: provider)

        let position = try calculator.bodyPosition(for: .venus, at: resolvedTime)

        XCTAssertTrue(position.retrograde)
        XCTAssertEqual(position.speedLongitude, -0.45, accuracy: 0.001)
        XCTAssertEqual(position.sign, .libra)
    }

    func testPrecessionMovesLongitudeForwardForFutureDate() throws {
        let j2000 = makeResolvedTime(julianDayUTC: 2_451_544.5, julianDayTT: 2_451_545.0, julianDayTDB: 2_451_545.0)
        let year2050 = makeResolvedTime(
            julianDayUTC: 2_469_806.5,
            julianDayTT: 2_469_807.0,
            julianDayTDB: 2_469_807.0
        )
        let inertialDirection = makeEquatorialState(longitude: 0.0, latitude: 0.0, speedLongitude: 0.0, julianDayTT: j2000.julianDayTT)
        let provider = MockEphemerisProvider(bodyStates: [.sun: inertialDirection], earthState: .zero)
        let calculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: provider)

        let start = try calculator.bodyPosition(for: .sun, at: j2000)
        let later = try calculator.bodyPosition(for: .sun, at: year2050)

        XCTAssertEqual(start.longitude, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(later.longitude, 0.5)
        XCTAssertLessThan(later.longitude, 1.0)
    }

    func testApparentModeAppliesAberrationShift() throws {
        let resolvedTime = makeResolvedTime(julianDayUTC: 2_451_544.5, julianDayTT: 2_451_545.0, julianDayTDB: 2_451_545.0)
        let state = makeEquatorialState(longitude: 0.0, latitude: 0.0, speedLongitude: 0.0, julianDayTT: resolvedTime.julianDayTT)
        let earthState = StateVector(
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            velocityX: 0,
            velocityY: 29.78,
            velocityZ: 0
        )

        let meanCalculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: MockEphemerisProvider(bodyStates: [.sun: state], earthState: earthState))
        let apparentCalculator = TropicalGeocentricBodyPositionCalculator(
            ephemerisProvider: MockEphemerisProvider(bodyStates: [.sun: state], earthState: earthState),
            reductionMode: .apparentOfDate
        )

        let mean = try meanCalculator.bodyPosition(for: .sun, at: resolvedTime)
        let apparent = try apparentCalculator.bodyPosition(for: .sun, at: resolvedTime)

        XCTAssertGreaterThan(apparent.longitude, mean.longitude)
    }

    func testApparentModeAppliesLightTimeCorrection() throws {
        let resolvedTime = makeResolvedTime(julianDayUTC: 2_451_544.5, julianDayTT: 2_451_545.0, julianDayTDB: 2_451_545.0)
        let meanCalculator = TropicalGeocentricBodyPositionCalculator(
            ephemerisProvider: TimeVaryingEphemerisProvider(referenceJulianDay: resolvedTime.julianDayTDB)
        )
        let apparentCalculator = TropicalGeocentricBodyPositionCalculator(
            ephemerisProvider: TimeVaryingEphemerisProvider(referenceJulianDay: resolvedTime.julianDayTDB),
            reductionMode: .apparentOfDate
        )

        let mean = try meanCalculator.bodyPosition(for: .mars, at: resolvedTime)
        let apparent = try apparentCalculator.bodyPosition(for: .mars, at: resolvedTime)

        XCTAssertLessThan(apparent.longitude, mean.longitude)
        XCTAssertGreaterThan(mean.longitude - apparent.longitude, 0.05)
    }

    func testApparentModeAppliesNutationShift() throws {
        let resolvedTime = makeResolvedTime(julianDayUTC: 2_460_676.5, julianDayTT: 2_460_677.0, julianDayTDB: 2_460_677.0)
        let state = makeEquatorialState(longitude: 120.0, latitude: 0.0, speedLongitude: 0.0, julianDayTT: resolvedTime.julianDayTT)
        let meanCalculator = TropicalGeocentricBodyPositionCalculator(ephemerisProvider: MockEphemerisProvider(bodyStates: [.venus: state], earthState: .zero))
        let apparentCalculator = TropicalGeocentricBodyPositionCalculator(
            ephemerisProvider: MockEphemerisProvider(bodyStates: [.venus: state], earthState: .zero),
            reductionMode: .apparentOfDate
        )

        let mean = try meanCalculator.bodyPosition(for: .venus, at: resolvedTime)
        let apparent = try apparentCalculator.bodyPosition(for: .venus, at: resolvedTime)

        XCTAssertGreaterThan(abs(apparent.longitude - mean.longitude), 0.00005)
    }

    func testHighAccuracyApparentModeDiffersFromApproximateApparentMode() throws {
        let resolvedTime = makeResolvedTime(julianDayUTC: 2_460_676.5, julianDayTT: 2_460_677.0, julianDayTDB: 2_460_677.0)
        let state = makeEquatorialState(longitude: 45.0, latitude: 3.0, speedLongitude: 0.2, julianDayTT: resolvedTime.julianDayTT)
        let earthState = StateVector(
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            velocityX: 8_000,
            velocityY: 16_000,
            velocityZ: 0
        )

        let approximate = TropicalGeocentricBodyPositionCalculator(
            ephemerisProvider: MockEphemerisProvider(bodyStates: [.moon: state], earthState: earthState),
            reductionMode: .apparentOfDate
        )
        let highAccuracy = TropicalGeocentricBodyPositionCalculator(
            ephemerisProvider: MockEphemerisProvider(bodyStates: [.moon: state], earthState: earthState),
            reductionMode: .highAccuracyApparentOfDate
        )

        let approximatePosition = try approximate.bodyPosition(for: .moon, at: resolvedTime)
        let highAccuracyPosition = try highAccuracy.bodyPosition(for: .moon, at: resolvedTime)

        XCTAssertGreaterThan(
            abs(highAccuracyPosition.longitude - approximatePosition.longitude),
            0.000001
        )
    }

    private func makeResolvedTime(julianDayUTC: Double, julianDayTT: Double, julianDayTDB: Double) -> ResolvedTime {
        ResolvedTime(
            localDateTime: "2000-01-01T12:00:00",
            timeZoneId: "UTC",
            utcOffsetMinutesAtBirth: 0,
            ambiguityPolicy: .earlier,
            timePrecision: .second,
            utc: "2000-01-01T12:00:00Z",
            julianDayUTC: julianDayUTC,
            julianDayTT: julianDayTT,
            julianDayTDB: julianDayTDB,
            deltaTSeconds: 64.0
        )
    }
}

private struct MockEphemerisProvider: EphemerisProvider {
    let bodyStates: [BodyID: StateVector]
    let earthState: StateVector

    func stateVector(for body: BodyID, tdbJulianDay: Double) throws -> StateVector {
        _ = tdbJulianDay
        guard let state = bodyStates[body] else {
            return .zero
        }
        return state
    }

    func earthStateVector(tdbJulianDay: Double) throws -> StateVector {
        _ = tdbJulianDay
        return earthState
    }
}

private struct TimeVaryingEphemerisProvider: EphemerisProvider {
    let referenceJulianDay: Double

    func stateVector(for body: BodyID, tdbJulianDay: Double) throws -> StateVector {
        switch body {
        case .mars:
            let longitude = 100.0 + 10.0 * (tdbJulianDay - referenceJulianDay)
            return makeEquatorialState(
                longitude: longitude,
                latitude: 0.0,
                speedLongitude: 10.0,
                julianDayTT: tdbJulianDay,
                radius: 300_000_000.0
            )
        default:
            return .zero
        }
    }

    func earthStateVector(tdbJulianDay: Double) throws -> StateVector {
        _ = tdbJulianDay
        return .zero
    }
}

private extension StateVector {
    static let zero = StateVector(
        positionX: 0,
        positionY: 0,
        positionZ: 0,
        velocityX: 0,
        velocityY: 0,
        velocityZ: 0
    )
}

private func makeEquatorialState(
    longitude: Double,
    latitude: Double,
    speedLongitude: Double,
    julianDayTT: Double,
    radius: Double = 100_000_000.0
) -> StateVector {
    let lambda = longitude * .pi / 180.0
    let beta = latitude * .pi / 180.0
    let lambdaDot = speedLongitude * .pi / 180.0 / 86_400.0

    let eclipticPosition = (
        x: radius * cos(beta) * cos(lambda),
        y: radius * cos(beta) * sin(lambda),
        z: radius * sin(beta)
    )
    let eclipticVelocity = (
        x: -radius * cos(beta) * sin(lambda) * lambdaDot,
        y: radius * cos(beta) * cos(lambda) * lambdaDot,
        z: 0.0
    )

    let epsilon = meanObliquityRadians(julianDayTT: julianDayTT)
    let cosEpsilon = cos(epsilon)
    let sinEpsilon = sin(epsilon)

    return StateVector(
        positionX: eclipticPosition.x,
        positionY: cosEpsilon * eclipticPosition.y - sinEpsilon * eclipticPosition.z,
        positionZ: sinEpsilon * eclipticPosition.y + cosEpsilon * eclipticPosition.z,
        velocityX: eclipticVelocity.x,
        velocityY: cosEpsilon * eclipticVelocity.y - sinEpsilon * eclipticVelocity.z,
        velocityZ: sinEpsilon * eclipticVelocity.y + cosEpsilon * eclipticVelocity.z
    )
}

private func meanObliquityRadians(julianDayTT: Double) -> Double {
    let t = (julianDayTT - 2_451_545.0) / 36_525.0
    let seconds = 84_381.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t
    return seconds / 3_600.0 * .pi / 180.0
}
