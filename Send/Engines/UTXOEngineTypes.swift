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
    let feeRateDescription: String? let spendableBalance: Double? let estimatedTransactionBytes: Int? let selectedInputCount: Int? let usesChangeOutput: Bool? let maxSendable: Double?
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
    let feeRateDescription: String? let maxSendable: Double
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
