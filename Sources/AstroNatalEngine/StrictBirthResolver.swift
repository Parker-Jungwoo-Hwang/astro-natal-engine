import Foundation
import AstroSchemas
import AstroTime

public struct StrictBirthResolver: BirthResolver {
    private let timeResolver: any BirthTimeResolving

    public init(timeResolver: any BirthTimeResolving = StrictTimeResolver()) {
        self.timeResolver = timeResolver
    }

    public func resolve(_ raw: RawBirthRequest) async throws -> ResolvedBirthRequest {
        try RequestValidator.validate(raw)
        let resolvedTime = try timeResolver.resolve(raw.birth)

        return ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: raw.birth.localDateTime,
                timeZoneId: resolvedTime.timeZoneId,
                utcOffsetMinutesAtBirth: resolvedTime.utcOffsetMinutesAtBirth,
                ambiguityPolicy: resolvedTime.ambiguityPolicy,
                timePrecision: resolvedTime.timePrecision
            ),
            location: raw.location,
            subject: raw.subject,
            profile: raw.profile
        )
    }
}
