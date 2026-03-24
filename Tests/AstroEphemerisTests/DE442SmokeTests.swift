import XCTest
@testable import AstroEphemeris
import AstroSchemas

final class DE442SmokeTests: XCTestCase {
    func testReadsRealDE442KernelWhenAvailable() throws {
        guard let kernelURL = DE442KernelLocator.locateKernelURL() else {
            throw XCTSkip("Set ASTRO_DE442_PATH to run the real-kernel smoke test.")
        }

        let kernel = try SPKKernel(url: kernelURL)

        XCTAssertTrue(kernel.looksLikeSPK)
        XCTAssertTrue(kernel.hasBody(.sun))
        XCTAssertTrue(kernel.hasBody(.earth))
        XCTAssertTrue(kernel.hasBody(.moon))

        let jd = 2_451_545.0
        let sun = try kernel.stateVector(for: .sun, tdbJulianDay: jd)
        let earth = try kernel.stateVector(for: .earth, tdbJulianDay: jd)
        let moon = try kernel.stateVector(for: .moon, tdbJulianDay: jd)

        XCTAssertTrue([sun, earth, moon].allSatisfy(\.isFinite))
    }
}

private extension StateVector {
    var isFinite: Bool {
        [positionX, positionY, positionZ, velocityX, velocityY, velocityZ].allSatisfy(\.isFinite)
    }
}
