import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPDataResponse: Sendable, Equatable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol RuntimeHTTPClient: Sendable {
    func get(_ url: URL) async throws -> HTTPDataResponse
}

public struct URLSessionRuntimeHTTPClient: RuntimeHTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> HTTPDataResponse {
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        return HTTPDataResponse(data: data, statusCode: statusCode)
    }
}
