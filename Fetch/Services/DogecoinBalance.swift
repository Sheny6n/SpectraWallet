import Foundation
enum DogecoinNetworkMode: String, CaseIterable, Codable, Identifiable {
    case mainnet
    case testnet
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        }}
}
struct DogecoinTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int? let networkFeeDOGE: Double? let confirmations: Int?
}
enum DogecoinBalanceService {
    typealias NetworkMode = DogecoinNetworkMode
    struct AddressTransactionSnapshot {
        let hash: String
        let kind: TransactionKind
        let status: TransactionStatus
        let amount: Double
        let counterpartyAddress: String
        let createdAt: Date
        let blockNumber: Int? }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.dogecoinChainName) }
    static func endpointCatalogByNetwork() -> [(title: String, endpoints: [String])] { AppEndpointDirectory.groupedSettingsEntries(for: ChainBackendRegistry.dogecoinChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.dogecoinChainName) }
}
