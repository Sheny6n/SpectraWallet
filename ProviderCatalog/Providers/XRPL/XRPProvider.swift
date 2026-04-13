import Foundation
enum XRPProvider {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.xrpChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.xrpChainName) }
}
