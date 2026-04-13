import Foundation
enum BitcoinNetworkMode: String, CaseIterable, Identifiable, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet:  return "Mainnet"
        case .testnet:  return "Testnet"
        case .testnet4: return "Testnet4"
        case .signet:   return "Signet"
        }}
}
struct BitcoinHistorySnapshot: Equatable {
    let txid: String
    let amountBTC: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int? let createdAt: Date
}
struct BitcoinHistoryPage {
    let snapshots: [BitcoinHistorySnapshot]
    let nextCursor: String? let sourceUsed: String
}
