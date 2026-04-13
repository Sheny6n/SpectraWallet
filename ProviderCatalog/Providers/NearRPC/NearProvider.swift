import Foundation
enum NearProvider {
    static let rpcEndpoints = ChainBackendRegistry.NearRuntimeEndpoints.rpcBaseURLs
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.nearChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.nearChainName) }
}
