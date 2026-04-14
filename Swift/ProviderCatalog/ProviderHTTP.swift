import Foundation
// All HTTP transport is now Rust-backed (core/src/http_ffi.rs). This enum is
// the only Swift-side facade; it routes URLRequest/URL callers through the
// Rust retry engine via NetworkResilience.
enum ProviderHTTP {
    static func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) { try await SpectraNetworkRouter.shared.data(for: request, profile: profile) }
    static func data(from url: URL, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) { try await SpectraNetworkRouter.shared.data(from: url, profile: profile) }
}
