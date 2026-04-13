import Foundation
enum BitcoinSVBalanceService {
    static func endpointCatalog() -> [String] { BitcoinSVProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { BitcoinSVProvider.diagnosticsChecks() }
}
