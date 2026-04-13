import Foundation
enum EVMChainContext: Equatable {
    case ethereum
    case ethereumSepolia
    case ethereumHoodi
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    var displayName: String {
        switch self {
        case .ethereum:         return "Ethereum"
        case .ethereumSepolia:  return "Ethereum Sepolia"
        case .ethereumHoodi:    return "Ethereum Hoodi"
        case .ethereumClassic:  return "Ethereum Classic"
        case .arbitrum:         return "Arbitrum"
        case .optimism:         return "Optimism"
        case .bnb:              return "BNB Chain"
        case .avalanche:        return "Avalanche"
        case .hyperliquid:      return "Hyperliquid"
        }}
    var tokenTrackingChain: TokenTrackingChain? {
        switch self {
        case .ethereum:                     return .ethereum
        case .ethereumSepolia, .ethereumHoodi, .ethereumClassic: return nil
        case .arbitrum:                     return .arbitrum
        case .optimism:                     return .optimism
        case .bnb:                          return .bnb
        case .avalanche:                    return .avalanche
        case .hyperliquid:                  return .hyperliquid
        }}
    var expectedChainID: Int {
        switch self {
        case .ethereum:         return 1
        case .ethereumSepolia:  return 11_155_111
        case .ethereumHoodi:    return 560_048
        case .ethereumClassic:  return 61
        case .arbitrum:         return 42161
        case .optimism:         return 10
        case .bnb:              return 56
        case .avalanche:        return 43114
        case .hyperliquid:      return 999
        }}
    var defaultDerivationPath: String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid: return "m/44'/60'/0'/0/0"
        case .ethereumClassic: return "m/44'/61'/0'/0/0"
        }}
    func derivationPath(account: UInt32) -> String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid: return "m/44'/60'/\(account)'/0/0"
        case .ethereumClassic: return "m/44'/61'/\(account)'/0/0"
        }}
    var defaultRPCEndpoints: [String] { AppEndpointDirectory.evmRPCEndpoints(for: displayName) }
    var isEthereumFamily: Bool {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi: return true
        default: return false
        }}
    var isEthereumMainnet: Bool { self == .ethereum }
}
enum EthereumNetworkMode: String, CaseIterable, Identifiable {
    case mainnet
    case sepolia
    case hoodi
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet:  return "Mainnet"
        case .sepolia:  return "Sepolia"
        case .hoodi:    return "Hoodi"
        }}
}
struct EthereumSendPreview: Equatable {
    let nonce: Int
    let gasLimit: Int
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
    let estimatedNetworkFeeETH: Double
    let spendableBalance: Double?
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double?
}
struct EthereumSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let rawTransactionHex: String
    let preview: EthereumSendPreview
    let verificationStatus: SendBroadcastVerificationStatus
}
struct TronSendPreview: Equatable {
    let estimatedNetworkFeeTRX: Double
    let feeLimitSun: Int64
    let simulationUsed: Bool
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct TronSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeTRX: Double
    let signedTransactionJSON: String
    let verificationStatus: SendBroadcastVerificationStatus
}
struct SolanaSendPreview: Equatable {
    let estimatedNetworkFeeSOL: Double
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct SolanaSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeSOL: Double
    let signedTransactionBase64: String
    let verificationStatus: SendBroadcastVerificationStatus
}
struct XRPSendPreview: Equatable {
    let estimatedNetworkFeeXRP: Double
    let feeDrops: Int64
    let sequence: Int64
    let lastLedgerSequence: Int64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct StellarSendPreview: Equatable {
    let estimatedNetworkFeeXLM: Double
    let feeStroops: Int64
    let sequence: Int64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct MoneroSendPreview: Equatable {
    let estimatedNetworkFeeXMR: Double
    let priorityLabel: String
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct CardanoSendPreview: Equatable {
    let estimatedNetworkFeeADA: Double
    let ttlSlot: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct SuiSendPreview: Equatable {
    let estimatedNetworkFeeSUI: Double
    let gasBudgetMist: UInt64
    let referenceGasPrice: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct AptosSendPreview: Equatable {
    let estimatedNetworkFeeAPT: Double
    let maxGasAmount: UInt64
    let gasUnitPriceOctas: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct TONSendPreview: Equatable {
    let estimatedNetworkFeeTON: Double
    let sequenceNumber: UInt32
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct ICPSendPreview: Equatable {
    let estimatedNetworkFeeICP: Double
    let feeE8s: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct NearSendPreview: Equatable {
    let estimatedNetworkFeeNEAR: Double
    let gasPriceYoctoNear: String
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}
struct PolkadotSendPreview: Equatable {
    let estimatedNetworkFeeDOT: Double
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

// MARK: - UTXO engine types (moved from Send/Engines/UTXOEngineTypes.swift)

enum BitcoinFeePriority: String, CaseIterable, Identifiable {
    case economy
    case normal
    case priority
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .economy:  return "Economy"
        case .normal:   return "Normal"
        case .priority: return "Priority"
        }}
}
struct BitcoinSendPreview: Equatable {
    let estimatedFeeRateSatVb: UInt64
    let estimatedNetworkFeeBTC: Double
    let feeRateDescription: String?
    let spendableBalance: Double?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double?
}
struct BitcoinSendResult: Equatable {
    let transactionHash: String
    let rawTransactionHex: String
    let verificationStatus: SendBroadcastVerificationStatus
}
enum DogecoinFeePriority: String, CaseIterable, Equatable {
    case economy
    case normal
    case priority
}
struct DogecoinSendPreview: Equatable {
    let spendableBalanceDOGE: Double
    let requestedAmountDOGE: Double
    let estimatedNetworkFeeDOGE: Double
    let estimatedFeeRateDOGEPerKB: Double
    let estimatedTransactionBytes: Int
    let selectedInputCount: Int
    let usesChangeOutput: Bool
    let feePriority: DogecoinFeePriority
    let maxSendableDOGE: Double
    let spendableBalance: Double
    let feeRateDescription: String?
    let maxSendable: Double
}
enum LitecoinChangeStrategy: String, CaseIterable, Identifiable {
    case derivedChange
    case reuseSourceAddress
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .derivedChange:      return "Derived change address"
        case .reuseSourceAddress: return "Reuse source address"
        }}
}
enum SolanaDerivationPreference {
    case standard
    case legacy
}

// MARK: - EVM address utilities (moved from Send/Engines/EVM/)

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcFailure(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid EVM address."
        case .invalidResponse: return "Unexpected response from EVM provider."
        case .rpcFailure(let detail): return detail
        }}
}
func normalizeEVMAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
func isValidEVMAddress(_ address: String) -> Bool {
    let normalized = normalizeEVMAddress(address)
    guard normalized.count == 42, normalized.hasPrefix("0x") else { return false }
    return normalized.dropFirst(2).allSatisfy(\.isHexDigit)
}
func validateEVMAddress(_ address: String) throws -> String {
    let normalized = normalizeEVMAddress(address)
    guard isValidEVMAddress(normalized) else { throw EthereumWalletEngineError.invalidAddress }
    return normalized
}
func receiveEVMAddress(for address: String) throws -> String {
    try validateEVMAddress(address)
}
func evmHasContractCode(_ code: String) -> Bool {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized != "0x" && normalized != "0x0"
}
