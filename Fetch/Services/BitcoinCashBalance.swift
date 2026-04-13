import Foundation
enum BitcoinCashBalanceService {
    static func endpointCatalog() -> [String] { BitcoinCashProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { BitcoinCashProvider.diagnosticsChecks() }
}
