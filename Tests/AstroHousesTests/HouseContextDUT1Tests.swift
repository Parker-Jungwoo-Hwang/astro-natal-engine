import XCTest
@testable import AstroHouses
@testable import AstroSchemas

final class HouseContextDUT1Tests: XCTestCase {
    func testDUT1ShiftsAnglesSlightly() throws {
        let solver = PlacidusHouseSolver()
        let base = try solver.compute(
            HouseContext(
                julianDayUT: 2_449_660.725694,
                latitude: 37.5665,
                longitude: 126.9780,
                system: .placidus
            )
        )
        let adjusted = try solver.compute(
            HouseContext(
                julianDayUT: 2_449_660.725694,
                dut1Seconds: 0.8,
                latitude: 37.5665,
                longitude: 126.9780,
                system: .placidus
            )
        )

        XCTAssertNotEqual(base.angles.asc, adjusted.angles.asc)
        XCTAssertNotEqual(base.angles.mc, adjusted.angles.mc)
    }
}
