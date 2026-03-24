import XCTest
@testable import AstroSchemas

final class SchemaRoundTripTests: XCTestCase {
    func testResolvedRequestRoundTrips() throws {
        let request = ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: "female"),
            profile: .standardNatal
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(ResolvedBirthRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testRawRequestValidationRejectsOutOfRangeCoordinates() {
        let request = RawBirthRequest(
            birth: RawBirth(localDateTime: "1994-11-03T14:25:00"),
            location: BirthLocation(city: "Nowhere", latitude: 92.0, longitude: 10.0),
            subject: BirthSubject(gender: nil),
            profile: .standardNatal
        )

        XCTAssertThrowsError(try RequestValidator.validate(request)) { error in
            XCTAssertEqual(error as? NatalEngineError, .invalidCoordinates)
        }
    }

    func testResolvedRequestValidationRejectsOutOfRangeYear() {
        let request = ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: "1899-12-31T23:59:00",
                timeZoneId: "UTC+00:00",
                utcOffsetMinutesAtBirth: 0,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: nil, latitude: 0.0, longitude: 0.0),
            subject: BirthSubject(gender: nil),
            profile: .standardNatal
        )

        XCTAssertThrowsError(try RequestValidator.validate(request)) { error in
            XCTAssertEqual(error as? NatalEngineError, .invalidBirthDateRange)
        }
    }
}
