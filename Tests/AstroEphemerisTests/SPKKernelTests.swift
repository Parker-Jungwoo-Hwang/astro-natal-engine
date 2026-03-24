import XCTest
import AstroEphemeris
import AstroSchemas

final class SPKKernelTests: XCTestCase {
    func testParsesHeaderDescriptorsAndSegmentNames() throws {
        let kernel = try makeReferenceKernel()

        XCTAssertTrue(kernel.looksLikeSPK)
        XCTAssertEqual(kernel.header.idWord, "DAF/SPK")
        XCTAssertEqual(kernel.header.nd, 2)
        XCTAssertEqual(kernel.header.ni, 6)
        XCTAssertEqual(kernel.header.binaryFormat, "LTL-IEEE")
        XCTAssertEqual(kernel.segments.count, 4)
        XCTAssertEqual(kernel.segments.map(\.name), ["SUN", "EMB", "EARTH", "MOON"])
        XCTAssertEqual(kernel.segments.map(\.targetNAIFID), [10, 3, 399, 301])
        XCTAssertTrue(kernel.hasBody(.sun))
        XCTAssertTrue(kernel.hasBody(.earth))
        XCTAssertTrue(kernel.hasBody(.moon))
        XCTAssertEqual(kernel.coverageEnvelope(for: .sun), -10.0 ... 10.0)
    }

    func testEvaluatesType2StateVectorAndCenterComposition() throws {
        let kernel = try makeReferenceKernel()
        let jd = 2_451_545.0 + (5.0 / 86_400.0)

        let sun = try kernel.stateVector(for: .sun, tdbJulianDay: jd)
        let earth = try kernel.stateVector(for: .earth, tdbJulianDay: jd)
        let moon = try kernel.stateVector(for: .moon, tdbJulianDay: jd)

        assertState(
            sun,
            equals: StateVector(positionX: 15.0, positionY: 30.0, positionZ: 45.0, velocityX: 1.0, velocityY: 2.0, velocityZ: 3.0)
        )
        assertState(
            earth,
            equals: StateVector(positionX: 99.45, positionY: 198.9, positionZ: 298.35, velocityX: 0.09, velocityY: 0.18, velocityZ: 0.27)
        )
        assertState(
            moon,
            equals: StateVector(positionX: 99.955, positionY: 199.91, positionZ: 299.865, velocityX: 0.091, velocityY: 0.182, velocityZ: 0.273)
        )
    }

    func testLaterOverlappingSegmentWins() throws {
        let segments = [
            SyntheticSPKFixture.linearSegment(
                name: "SUN_A",
                target: 10,
                center: 0,
                positionAtZero: (10, 20, 30),
                velocity: (1, 2, 3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "SUN_B",
                target: 10,
                center: 0,
                positionAtZero: (100, 200, 300),
                velocity: (10, 20, 30)
            )
        ]

        let kernel = try SPKKernel(data: SyntheticSPKFixture.makeKernelData(segments: segments))
        let jd = 2_451_545.0 + (5.0 / 86_400.0)
        let sun = try kernel.stateVector(for: .sun, tdbJulianDay: jd)

        assertState(
            sun,
            equals: StateVector(positionX: 150.0, positionY: 300.0, positionZ: 450.0, velocityX: 10.0, velocityY: 20.0, velocityZ: 30.0)
        )
    }

    func testRejectsUnsupportedSegmentType() throws {
        let kernel = try SPKKernel(
            data: SyntheticSPKFixture.makeKernelData(
                segments: [
                    SyntheticSPKFixture.linearSegment(
                        name: "BAD",
                        target: 10,
                        center: 0,
                        positionAtZero: (1, 2, 3),
                        velocity: (0, 0, 0),
                        dataType: 3
                    )
                ]
            )
        )

        XCTAssertThrowsError(try kernel.stateVector(for: .sun, tdbJulianDay: 2_451_545.0)) { error in
            XCTAssertEqual(error as? SPKKernelError, .unsupportedSegmentType(3))
        }
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
