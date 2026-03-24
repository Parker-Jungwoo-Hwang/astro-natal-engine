import XCTest
import AstroEphemeris
import AstroSchemas

final class JPLEphemerisProviderTests: XCTestCase {
    func testProviderRegressionCasesForSunEarthAndMoon() throws {
        let provider = JPLEphemerisProvider(kernel: try makeReferenceKernel())

        let cases: [(et: Double, body: BodyID, expected: StateVector)] = [
            (
                et: -5.0,
                body: .sun,
                expected: StateVector(positionX: 5.0, positionY: 10.0, positionZ: 15.0, velocityX: 1.0, velocityY: 2.0, velocityZ: 3.0)
            ),
            (
                et: 5.0,
                body: .sun,
                expected: StateVector(positionX: 15.0, positionY: 30.0, positionZ: 45.0, velocityX: 1.0, velocityY: 2.0, velocityZ: 3.0)
            ),
            (
                et: -5.0,
                body: .moon,
                expected: StateVector(positionX: 99.045, positionY: 198.09, positionZ: 297.135, velocityX: 0.091, velocityY: 0.182, velocityZ: 0.273)
            ),
            (
                et: 5.0,
                body: .moon,
                expected: StateVector(positionX: 99.955, positionY: 199.91, positionZ: 299.865, velocityX: 0.091, velocityY: 0.182, velocityZ: 0.273)
            )
        ]

        for regressionCase in cases {
            let jd = 2_451_545.0 + (regressionCase.et / 86_400.0)
            let state = try provider.stateVector(for: regressionCase.body, tdbJulianDay: jd)
            assertState(state, equals: regressionCase.expected)
        }

        let earthJD = 2_451_545.0 + (5.0 / 86_400.0)
        let earth = try provider.earthStateVector(tdbJulianDay: earthJD)
        assertState(
            earth,
            equals: StateVector(positionX: 99.45, positionY: 198.9, positionZ: 298.35, velocityX: 0.09, velocityY: 0.18, velocityZ: 0.27)
        )
    }

    func testProviderFallsBackToMarsBarycenterWhenPlanetCenterAbsent() throws {
        let kernel = try SPKKernel(
            data: SyntheticSPKFixture.makeKernelData(
                segments: [
                    SyntheticSPKFixture.linearSegment(
                        name: "MARS_BARY",
                        target: 4,
                        center: 0,
                        positionAtZero: (50, 60, 70),
                        velocity: (0.5, 0.6, 0.7)
                    )
                ]
            )
        )

        let provider = JPLEphemerisProvider(kernel: kernel)
        let jd = 2_451_545.0 + (4.0 / 86_400.0)
        let mars = try provider.stateVector(for: BodyID.mars, tdbJulianDay: jd)

        assertState(
            mars,
            equals: StateVector(positionX: 52.0, positionY: 62.4, positionZ: 72.8, velocityX: 0.5, velocityY: 0.6, velocityZ: 0.7)
        )
    }

    private func makeReferenceKernel() throws -> SPKKernel {
        let segments = [
            SyntheticSPKFixture.linearSegment(
                name: "SUN",
                target: 10,
                center: 0,
                positionAtZero: (10, 20, 30),
                velocity: (1, 2, 3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "EMB",
                target: 3,
                center: 0,
                positionAtZero: (100, 200, 300),
                velocity: (0.1, 0.2, 0.3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "EARTH",
                target: 399,
                center: 3,
                positionAtZero: (-1, -2, -3),
                velocity: (-0.01, -0.02, -0.03)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "MOON",
                target: 301,
                center: 399,
                positionAtZero: (0.5, 1.0, 1.5),
                velocity: (0.001, 0.002, 0.003)
            )
        ]

        return try SPKKernel(data: SyntheticSPKFixture.makeKernelData(segments: segments))
    }

    private func assertState(
        _ actual: StateVector,
        equals expected: StateVector,
        positionAccuracy: Double = 5e-4,
        velocityAccuracy: Double = 1e-12
    ) {
        XCTAssertEqual(actual.positionX, expected.positionX, accuracy: positionAccuracy)
        XCTAssertEqual(actual.positionY, expected.positionY, accuracy: positionAccuracy)
        XCTAssertEqual(actual.positionZ, expected.positionZ, accuracy: positionAccuracy)
        XCTAssertEqual(actual.velocityX, expected.velocityX, accuracy: velocityAccuracy)
        XCTAssertEqual(actual.velocityY, expected.velocityY, accuracy: velocityAccuracy)
        XCTAssertEqual(actual.velocityZ, expected.velocityZ, accuracy: velocityAccuracy)
    }
}
