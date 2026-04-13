import Foundation
enum SuiProvider {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.suiChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.suiChainName) }
}
