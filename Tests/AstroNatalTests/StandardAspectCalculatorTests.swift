import XCTest
@testable import AstroNatal
@testable import AstroSchemas

final class StandardAspectCalculatorTests: XCTestCase {
    private let calculator = StandardAspectCalculator()

    func testStandardProfileDetectsMajorAspects() throws {
        let aspects = try calculator.aspects(
            from: BodiesResponse(
                sun: makePosition(0),
                moon: makePosition(60.5),
                venus: makePosition(120.0),
                mars: makePosition(179.0)
            ),
            profile: .standardNatal
        )

        XCTAssertTrue(containsAspect(aspects, a: .sun, b: .moon, type: .sextile))
        XCTAssertTrue(containsAspect(aspects, a: .sun, b: .mars, type: .opposition))
        XCTAssertTrue(containsAspect(aspects, a: .sun, b: .venus, type: .trine))
    }

    func testStandardProfileSkipsWideSextile() throws {
        let aspects = try calculator.aspects(
            from: BodiesResponse(
                sun: makePosition(0),
                moon: makePosition(65.0)
            ),
            profile: .standardNatal
        )

        XCTAssertFalse(aspects.contains(where: { $0.type == .sextile }))
    }

    func testEnhancedProfileUsesWiderOrbs() throws {
        let aspects = try calculator.aspects(
            from: BodiesResponse(
                sun: makePosition(0),
                moon: makePosition(65.0)
            ),
            profile: .enhancedNatal
        )

        XCTAssertEqual(aspects.count, 1)
        XCTAssertEqual(aspects.first?.type, .sextile)
        XCTAssertEqual(aspects.first!.orb, 5.0, accuracy: 0.0001)
    }

    func testClosestAspectWinsPerPair() throws {
        let aspects = try calculator.aspects(
            from: BodiesResponse(
                sun: makePosition(0),
                moon: makePosition(91.5)
            ),
            profile: .standardNatal
        )

        XCTAssertEqual(aspects.count, 1)
        XCTAssertEqual(aspects.first?.type, .square)
        XCTAssertEqual(aspects.first!.orb, 1.5, accuracy: 0.0001)
    }

    private func makePosition(_ longitude: Double) -> BodyPosition {
        BodyPosition(
            longitude: longitude,
            latitude: 0,
            speedLongitude: 1,
            retrograde: false,
            sign: ZodiacSign.allCases[min(Int(longitude / 30.0), 11)],
            house: 0
        )
    }

    private func containsAspect(
        _ aspects: [AspectResponse],
        a: BodyID,
        b: BodyID,
        type: AspectType
    ) -> Bool {
        aspects.contains(where: { aspect in
            aspect.a == a && aspect.b == b && aspect.type == type
        })
    }
}
