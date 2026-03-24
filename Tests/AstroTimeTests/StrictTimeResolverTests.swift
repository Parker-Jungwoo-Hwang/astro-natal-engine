import XCTest
@testable import AstroTime
@testable import AstroSchemas

final class StrictTimeResolverTests: XCTestCase {
    private let resolver = StrictTimeResolver()

    func testOffsetTakesPrecedenceWhenProvided() throws {
        let resolved = try resolver.resolve(
            RawBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "America/New_York",
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .second
            )
        )

        XCTAssertEqual(resolved.timeZoneId, "America/New_York")
        XCTAssertEqual(resolved.utcOffsetMinutesAtBirth, 540)
        XCTAssertEqual(resolved.utc, "1994-11-03T05:25:00Z")
    }

    func testTimeZoneIDResolvesUniqueLocalTime() throws {
        let resolved = try resolver.resolve(
            RawBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                ambiguityPolicy: .earlier,
                timePrecision: .second
            )
        )

        XCTAssertEqual(resolved.timeZoneId, "Asia/Seoul")
        XCTAssertEqual(resolved.utcOffsetMinutesAtBirth, 540)
        XCTAssertEqual(resolved.utc, "1994-11-03T05:25:00Z")
        XCTAssertGreaterThan(resolved.julianDayTT, resolved.julianDayUTC)
        XCTAssertNotEqual(resolved.julianDayTDB, resolved.julianDayTT)
        XCTAssertLessThan(abs(resolved.julianDayTDB - resolved.julianDayTT), 0.01 / 86_400.0)
    }

    func testFoldUsesEarlierPolicy() throws {
        let resolved = try resolver.resolve(
            RawBirth(
                localDateTime: "2021-11-07T01:30:00",
                timeZoneId: "America/New_York",
                ambiguityPolicy: .earlier,
                timePrecision: .second
            )
        )

        XCTAssertEqual(resolved.utcOffsetMinutesAtBirth, -240)
        XCTAssertEqual(resolved.utc, "2021-11-07T05:30:00Z")
    }

    func testFoldUsesLaterPolicy() throws {
        let resolved = try resolver.resolve(
            RawBirth(
                localDateTime: "2021-11-07T01:30:00",
                timeZoneId: "America/New_York",
                ambiguityPolicy: .later,
                timePrecision: .second
            )
        )

        XCTAssertEqual(resolved.utcOffsetMinutesAtBirth, -300)
        XCTAssertEqual(resolved.utc, "2021-11-07T06:30:00Z")
    }

    func testFoldRejectPolicyThrows() {
        XCTAssertThrowsError(
            try resolver.resolve(
                RawBirth(
                    localDateTime: "2021-11-07T01:30:00",
                    timeZoneId: "America/New_York",
                    ambiguityPolicy: .reject,
                    timePrecision: .second
                )
            )
        ) { error in
            XCTAssertEqual(error as? NatalEngineError, .ambiguousLocalTime)
        }
    }

    func testGapThrowsMalformedRequest() {
        XCTAssertThrowsError(
            try resolver.resolve(
                RawBirth(
                    localDateTime: "2021-03-14T02:30:00",
                    timeZoneId: "America/New_York",
                    ambiguityPolicy: .earlier,
                    timePrecision: .second
                )
            )
        ) { error in
            guard case let .malformedRequest(message) = error as? NatalEngineError else {
                return XCTFail("Expected malformedRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("daylight-saving gap"))
        }
    }

    func testEarly1900sBirthStillResolves() throws {
        let resolved = try resolver.resolve(
            RawBirth(
                localDateTime: "1901-01-15T10:00:00",
                timeZoneId: "America/New_York",
                ambiguityPolicy: .earlier,
                timePrecision: .second
            )
        )

        XCTAssertEqual(resolved.utcOffsetMinutesAtBirth, -300)
        XCTAssertLessThan(resolved.deltaTSeconds, 0)
    }

    func testLate2150BirthStillResolves() throws {
        let resolved = try resolver.resolve(
            RawBirth(
                localDateTime: "2150-12-31T23:30:00",
                timeZoneId: "UTC",
                ambiguityPolicy: .earlier,
                timePrecision: .second
            )
        )

        XCTAssertEqual(resolved.utcOffsetMinutesAtBirth, 0)
        XCTAssertGreaterThan(resolved.deltaTSeconds, 200)
    }

    func testMissingTimeZoneAndOffsetThrows() {
        XCTAssertThrowsError(
            try resolver.resolve(
                RawBirth(
                    localDateTime: "1994-11-03T14:25:00",
                    ambiguityPolicy: .earlier,
                    timePrecision: .minute
                )
            )
        ) { error in
            XCTAssertEqual(error as? NatalEngineError, .timezoneUnresolved)
        }
    }

    func testInvalidOffsetThrows() {
        XCTAssertThrowsError(
            try resolver.resolve(
                RawBirth(
                    localDateTime: "1994-11-03T14:25:00",
                    utcOffsetMinutesAtBirth: 900,
                    ambiguityPolicy: .earlier,
                    timePrecision: .minute
                )
            )
        ) { error in
            XCTAssertEqual(error as? NatalEngineError, .invalidUTCOffset)
        }
    }
}
