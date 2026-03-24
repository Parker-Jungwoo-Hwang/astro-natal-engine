import Foundation
import AstroSchemas

public actor NatalChartEngine {
    // `prepare()` is the only place that turns the mutable runtime pack store into
    // the immutable environment snapshot consumed by chart generation. Keeping the
    // task inside the actor prevents concurrent callers from triggering duplicate
    // downloads while still letting a failed preparation be retried from `.idle`.
    private enum PreparationState {
        case idle
        case preparing(Task<NatalEngineEnvironment, Error>)
        case ready(NatalEngineEnvironment)
    }

    private let configuration: NatalEngineConfiguration
    private var preparationState: PreparationState = .idle

    public init(configuration: NatalEngineConfiguration) {
        self.configuration = configuration
    }

    public func prepare() async throws {
        switch preparationState {
        case .ready:
            return
        case let .preparing(task):
            _ = try await task.value
        case .idle:
            let task = Task { [configuration] in
                try await configuration.dataPackStore.ensureReady()
                let dataVersions = try await configuration.dataPackStore.installedDataVersions()
                return NatalEngineEnvironment(
                    engineVersion: configuration.engineVersion,
                    dataVersions: dataVersions
                )
            }
            preparationState = .preparing(task)
            do {
                let environment = try await task.value
                preparationState = .ready(environment)
            } catch {
                preparationState = .idle
                throw error
            }
        }
    }

    public func generate(_ request: ResolvedBirthRequest) async throws -> NatalChartResponse {
        try RequestValidator.validate(request)
        let environment = try preparedEnvironment()
        return try await configuration.chartComputer.generate(request: request, environment: environment)
    }

    public func generate(_ request: RawBirthRequest) async throws -> NatalChartResponse {
        try RequestValidator.validate(request)
        let resolved = try await configuration.birthResolver.resolve(request)
        return try await generate(resolved)
    }

    public func generateJSON(_ requestData: Data) async throws -> Data {
        let response: NatalChartResponse
        let decoder = JSONDecoder()

        if let resolved = try? decoder.decode(ResolvedBirthRequest.self, from: requestData) {
            response = try await generate(resolved)
        } else if let raw = try? decoder.decode(RawBirthRequest.self, from: requestData) {
            response = try await generate(raw)
        } else {
            throw NatalEngineError.malformedRequest("Input data is neither natal.raw.v1 nor natal.resolved.v1.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(response)
    }

    public func preparedDataVersions() throws -> EngineDataVersions {
        try preparedEnvironment().dataVersions
    }

    private func preparedEnvironment() throws -> NatalEngineEnvironment {
        // `generate` does not await an in-flight `prepare()`: callers must make the
        // lifecycle transition explicit so they can distinguish "still preparing"
        // from a successful environment that is safe to embed in responses.
        switch preparationState {
        case let .ready(environment):
            return environment
        case .idle, .preparing:
            throw NatalEngineError.engineNotPrepared
        }
    }
}
