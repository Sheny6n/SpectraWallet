/// Shared value types used by UTXO and chain send engines.
///
/// Kept in a dedicated file so they remain available after the individual
/// engine files are deleted. UI and store layers import from here directly
/// rather than via the engine namespace.

// MARK: - Dogecoin

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

// MARK: - Litecoin

enum LitecoinChangeStrategy: String, CaseIterable, Identifiable {
    case derivedChange
    case reuseSourceAddress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .derivedChange:      return "Derived change address"
        case .reuseSourceAddress: return "Reuse source address"
        }
    }
}

// MARK: - Solana derivation preference

enum SolanaDerivationPreference {
    case standard
    case legacy
}
