import Foundation
import AstroSchemas

public struct NatalEngineEnvironment: Sendable, Equatable {
    public let engineVersion: String
    public let dataVersions: EngineDataVersions

    public init(engineVersion: String, dataVersions: EngineDataVersions) {
        self.engineVersion = engineVersion
        self.dataVersions = dataVersions
    }
}

public protocol NatalChartComputer: Sendable {
    func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse
}

public struct StubNatalChartComputer: NatalChartComputer {
    public init() {}

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        _ = request
        _ = environment
        throw NatalEngineError.featureNotImplemented(
            "Chart computation begins in later stages (ephemeris, time axis, frames, and houses)."
        )
    }
}
