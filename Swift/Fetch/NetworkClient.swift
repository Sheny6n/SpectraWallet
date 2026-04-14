import Foundation
enum NetworkRetryProfile {
    case chainRead
    case chainWrite
    case diagnostics
    case litecoinRead
    case litecoinWrite
    case litecoinDiagnostics
    var policy: NetworkRetryPolicy {
        switch self {
        case .chainRead: return NetworkRetryPolicy(maxAttempts: 3, initialDelay: 0.35, multiplier: 2.0, maxDelay: 2.0)
        case .chainWrite: return NetworkRetryPolicy(maxAttempts: 2, initialDelay: 0.25, multiplier: 2.0, maxDelay: 1.0)
        case .diagnostics: return NetworkRetryPolicy(maxAttempts: 2, initialDelay: 0.2, multiplier: 2.0, maxDelay: 0.8)
        case .litecoinRead: return NetworkRetryPolicy(maxAttempts: 4, initialDelay: 0.55, multiplier: 2.0, maxDelay: 4.0)
        case .litecoinWrite: return NetworkRetryPolicy(maxAttempts: 3, initialDelay: 0.45, multiplier: 2.0, maxDelay: 3.0)
        case .litecoinDiagnostics: return NetworkRetryPolicy(maxAttempts: 3, initialDelay: 0.35, multiplier: 2.0, maxDelay: 2.5)
        }}
}
struct NetworkRetryPolicy {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let multiplier: Double
    let maxDelay: TimeInterval
}
// All transport + retry now lives in Rust (core/src/http_ffi.rs). This shim
// adapts Swift's URLRequest/URLResponse shapes to the UniFFI byte-oriented
// call so existing call sites compile unchanged.
enum NetworkResilience {
    static func data(
        for request: URLRequest, profile: NetworkRetryProfile, session _: URLSession = .shared, retryStatusCodes _: Set<Int> = Set([429] + Array(500 ... 599))
    ) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let method = (request.httpMethod ?? "GET").uppercased()
        let headers: [HttpHeader] = (request.allHTTPHeaderFields ?? [:]).map { HttpHeader(name: $0.key, value: $0.value) }
        let body: Data? = request.httpBody
        let rustProfile = profile.rustProfile
        let resp = try await httpRequest(method: method, url: url.absoluteString, headers: headers, body: body, profile: rustProfile)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: Int(resp.statusCode),
            httpVersion: "HTTP/1.1",
            headerFields: Dictionary(resp.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        ) ?? HTTPURLResponse()
        return (resp.body, httpResponse)
    }
    static func data(
        from url: URL, profile: NetworkRetryProfile, session: URLSession = .shared, retryStatusCodes: Set<Int> = Set([429] + Array(500 ... 599))
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(for: request, profile: profile, session: session, retryStatusCodes: retryStatusCodes)
    }
}

private extension NetworkRetryProfile {
    var rustProfile: HttpRetryProfile {
        switch self {
        case .chainRead: return .chainRead
        case .chainWrite: return .chainWrite
        case .diagnostics: return .diagnostics
        case .litecoinRead: return .litecoinRead
        case .litecoinWrite: return .litecoinWrite
        case .litecoinDiagnostics: return .litecoinDiagnostics
        }
    }
}
protocol SpectraNetworkClient {
    func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse)
}
extension SpectraNetworkClient {
    func data(from url: URL, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(for: request, profile: profile)
    }
}
struct LiveSpectraNetworkClient: SpectraNetworkClient {
    nonisolated init() {}
    func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) { try await NetworkResilience.data(for: request, profile: profile) }
}
actor SpectraNetworkRouter {
    static let shared = SpectraNetworkRouter()
    private var client: any SpectraNetworkClient
    init() { self.client = LiveSpectraNetworkClient() }
    func install(client: any SpectraNetworkClient) { self.client = client }
    func resetToDefault() { client = LiveSpectraNetworkClient() }
    func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) { try await client.data(for: request, profile: profile) }
    func data(from url: URL, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) { try await client.data(from: url, profile: profile) }
}
actor TestSpectraNetworkClient: SpectraNetworkClient {
    struct RequestKey: Hashable {
        let method: String
        let url: String
    }
    enum Event {
        case response(statusCode: Int, headers: [String: String], body: Data)
        case failure(URLError.Code)
    }
    private var queues: [RequestKey: [Event]] = [:]
    func enqueueResponse(method: String = "GET", url: String, statusCode: Int = 200, headers: [String: String] = [:], body: Data) {
        let key = RequestKey(method: method.uppercased(), url: url)
        queues[key, default: []].append(.response(statusCode: statusCode, headers: headers, body: body))
    }
    func data(for request: URLRequest, profile _: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        let method = (request.httpMethod ?? "GET").uppercased()
        let urlString = request.url?.absoluteString ?? ""
        let key = RequestKey(method: method, url: urlString)
        guard var events = queues[key], !events.isEmpty else { throw URLError(.resourceUnavailable) }
        let event = events.removeFirst()
        queues[key] = events.isEmpty ? nil : events
        switch event {
        case let .failure(code): throw URLError(code)
        case let .response(statusCode, headers, body): guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers) else { throw URLError(.badServerResponse) }
            return (body, response)
        }}
}
