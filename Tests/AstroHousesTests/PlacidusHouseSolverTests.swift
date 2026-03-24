import XCTest
@testable import AstroHouses
@testable import AstroSchemas

final class PlacidusHouseSolverTests: XCTestCase {
    private let solver = PlacidusHouseSolver()

    func testEqualHouseSystemUsesAscendantAsFirstCusp() throws {
        let computation = try solver.compute(
            HouseContext(
                julianDayUT: 2_449_660.725694,
                latitude: 37.5665,
                longitude: 126.9780,
                system: .equal
            )
        )

        XCTAssertEqual(computation.houseResult.system, .equal)
        XCTAssertFalse(computation.houseResult.fallbackApplied)
        XCTAssertEqual(computation.houseResult.cusps[0], computation.angles.asc, accuracy: 0.0001)

        for index in 0..<12 {
            let expected = normalizeDegrees(computation.angles.asc + Double(index) * 30.0)
            XCTAssertEqual(computation.houseResult.cusps[index], expected, accuracy: 0.0001)
        }
    }

    func testPlacidusProducesOrderedCuspsAndOppositions() throws {
        let computation = try solver.compute(
            HouseContext(
                julianDayUT: 2_449_660.725694,
                latitude: 37.5665,
                longitude: 126.9780,
                system: .placidus
            )
        )

        XCTAssertEqual(computation.houseResult.system, .placidus)
        XCTAssertFalse(computation.houseResult.fallbackApplied)
        XCTAssertEqual(computation.houseResult.cusps.count, 12)
        XCTAssertEqual(computation.houseResult.cusps[0], computation.angles.asc, accuracy: 0.0001)
        XCTAssertEqual(computation.houseResult.cusps[3], computation.angles.ic, accuracy: 0.0001)
        XCTAssertEqual(computation.houseResult.cusps[6], computation.angles.dc, accuracy: 0.0001)
        XCTAssertEqual(computation.houseResult.cusps[9], computation.angles.mc, accuracy: 0.0001)

        for index in 0..<6 {
            let oppositeIndex = index + 6
            XCTAssertEqual(
                normalizeDegrees(computation.houseResult.cusps[index] + 180.0),
                computation.houseResult.cusps[oppositeIndex],
                accuracy: 0.001
            )
        }

        for index in 0..<12 {
            let next = computation.houseResult.cusps[(index + 1) % 12]
            let span = normalizeDegrees(next - computation.houseResult.cusps[index])
            XCTAssertGreaterThan(span, 0.1)
            XCTAssertLessThan(span, 179.9)
        }
    }

    func testPlacidusFallsBackToEqualNearPolarLatitude() throws {
        let computation = try solver.compute(
            HouseContext(
                julianDayUT: 2_449_660.725694,
                latitude: 75.0,
                longitude: 0.0,
                system: .placidus
            )
        )

        XCTAssertEqual(computation.houseResult.system, .equal)
        XCTAssertTrue(computation.houseResult.fallbackApplied)
        XCTAssertEqual(computation.houseResult.cusps[0], computation.angles.asc, accuracy: 0.0001)
        XCTAssertEqual(computation.houseResult.iterations, 0)
    }

    func testHouseAssignmentHandlesWrappedCusps() {
        let cusps = [350, 20, 50, 80, 110, 140, 170, 200, 230, 260, 290, 320].map(Double.init)

        XCTAssertEqual(HouseAssignment.house(for: 355, cusps: cusps), 1)
        XCTAssertEqual(HouseAssignment.house(for: 15, cusps: cusps), 1)
        XCTAssertEqual(HouseAssignment.house(for: 21, cusps: cusps), 2)
        XCTAssertEqual(HouseAssignment.house(for: 205, cusps: cusps), 8)
    }
}

private func normalizeDegrees(_ degrees: Double) -> Double {
    let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
    return normalized >= 0 ? normalized : normalized + 360.0
}
