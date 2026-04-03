import Foundation
import WalletCore

enum DogecoinNetworkMode: String, CaseIterable, Codable, Identifiable {
    case mainnet
    case testnet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        }
    }
}

struct DogecoinWalletEngine {
    static let derivationScanLimit = 200
    static let maxStandardTransactionBytes = 100_000
    static let minRelayFeePerKB: Double = 0.01
    static let dustThresholdDOGE: Double = 0.01
    static let koinuPerDOGE: Double = 100_000_000
    static let feePolicy = UTXOKilobyteFeePolicy(
        chainName: "Dogecoin",
        baseUnitsPerCoin: koinuPerDOGE,
        dustThreshold: UInt64((dustThresholdDOGE * koinuPerDOGE).rounded()),
        minimumRelayFeePerKB: minRelayFeePerKB,
        maxStandardTransactionBytes: UInt64(maxStandardTransactionBytes)
    )
    static let networkTimeoutSeconds: TimeInterval = 12
    static let networkRetryCount = 2
    static let utxoCacheTTLSeconds: TimeInterval = 180
    static let utxoCacheLock = NSLock()
    static var utxoCacheByAddress: [String: CachedUTXOSet] = [:]

    struct SigningKeyMaterial {
        let address: String
        let privateKeyData: Data
        let signingDerivationPath: String
        let changeAddress: String
        let changeDerivationPath: String
    }

    typealias DogecoinSpendPlan = UTXOSpendPlan<DogecoinUTXO>

    struct DogecoinWalletCoreSigningRequest {
        let keyMaterial: SigningKeyMaterial
        let utxos: [DogecoinUTXO]
        let destinationAddress: String
        let amountDOGE: Double
        let changeAddress: String
        let feeRateDOGEPerKB: Double
    }

    struct DogecoinWalletCoreSigningResult {
        let encodedTransaction: Data
        let transactionHash: String
    }

    enum FeePriority: String, CaseIterable, Equatable {
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
        let feePriority: FeePriority
        let maxSendableDOGE: Double
        let spendableBalance: Double
        let feeRateDescription: String?
        let maxSendable: Double
    }

    enum PostBroadcastVerificationStatus: Equatable {
        case verified
        case deferred
        case failed(String)
    }

    struct DogecoinSendResult: Equatable {
        let transactionHash: String
        let verificationStatus: PostBroadcastVerificationStatus
        let derivationMetadata: DerivationMetadata
        let rawTransactionHex: String
    }

    struct DogecoinRebroadcastResult: Equatable {
        let transactionHash: String
        let verificationStatus: PostBroadcastVerificationStatus
    }

    struct DerivationMetadata: Equatable {
        let sourceAddress: String
        let sourceDerivationPath: String
        let changeAddress: String
        let changeDerivationPath: String
    }

    struct DogecoinUTXO: Decodable {
        let transactionHash: String
        let index: Int
        let value: UInt64

        enum CodingKeys: String, CodingKey {
            case transactionHash = "transaction_hash"
            case index
            case value
        }
    }

    struct CachedUTXOSet {
        let utxos: [DogecoinUTXO]
        let updatedAt: Date
    }

    static func resetUTXOCache() {
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress.removeAll()
    }

    static func networkMode(for wallet: ImportedWallet) -> DogecoinNetworkMode {
        wallet.dogecoinNetworkMode
    }

    @discardableResult
    static func sendInBackground(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        to recipientAddress: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        changeIndex: Int? = nil,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) async throws -> DogecoinSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try send(
                        from: importedWallet,
                        seedPhrase: seedPhrase,
                        to: recipientAddress,
                        amountDOGE: amountDOGE,
                        feePriority: feePriority,
                        changeIndex: changeIndex,
                        maxInputCount: maxInputCount,
                        derivationAccount: derivationAccount
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func rebroadcastSignedTransactionInBackground(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        networkMode: DogecoinNetworkMode = .mainnet
    ) async throws -> DogecoinRebroadcastResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try rebroadcastSignedTransaction(
                        rawTransactionHex: rawTransactionHex,
                        expectedTransactionHash: expectedTransactionHash,
                        networkMode: networkMode
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func derivedAddress(for seedPhrase: String, account: Int = 0) throws -> String {
        try derivedAddress(for: seedPhrase, networkMode: .mainnet, account: account)
    }

    static func derivedAddress(
        for seedPhrase: String,
        networkMode: DogecoinNetworkMode,
        account: Int = 0
    ) throws -> String {
        try walletCoreDerivedAddress(
            seedPhrase: seedPhrase,
            networkMode: networkMode,
            isChange: false,
            index: 0,
            account: account
        )
    }

    static func derivedAddress(for seedPhrase: String, isChange: Bool, index: Int, account: Int = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            networkMode: .mainnet,
            isChange: isChange,
            index: index,
            account: account
        )
    }

    static func derivedAddress(
        for seedPhrase: String,
        networkMode: DogecoinNetworkMode,
        isChange: Bool,
        index: Int,
        account: Int = 0
    ) throws -> String {
        try walletCoreDerivedAddress(
            seedPhrase: seedPhrase,
            networkMode: networkMode,
            isChange: isChange,
            index: index,
            account: account
        )
    }

    static func fetchSendPreview(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) throws -> DogecoinSendPreview {
        guard amountDOGE > 0 else {
            throw DogecoinWalletEngineError.invalidAmount
        }

        let keyMaterial = try deriveSigningKeyMaterial(
            seedPhrase: seedPhrase,
            expectedAddress: importedWallet.dogecoinAddress,
            networkMode: networkMode(for: importedWallet),
            derivationAccount: derivationAccount
        )
        let spendableUTXOs = try fetchSpendableUTXOs(for: keyMaterial.address, networkMode: networkMode(for: importedWallet))
        guard !spendableUTXOs.isEmpty else {
            throw DogecoinWalletEngineError.noSpendableUTXOs
        }

        let feeRateDOGEPerKB = try resolveNetworkFeeRateDOGEPerKB(
            feePriority: feePriority,
            networkMode: networkMode(for: importedWallet)
        )
        let spendPlan = try buildSpendPlan(
            from: spendableUTXOs,
            amountDOGE: amountDOGE,
            feeRateDOGEPerKB: feeRateDOGEPerKB,
            maxInputCount: maxInputCount
        )
        let spendableBalanceDOGE = Double(spendableUTXOs.reduce(0) { $0 + $1.value }) / koinuPerDOGE
        let preview = feePolicy.preview(
            for: spendableUTXOs.reduce(0) { $0 + $1.value },
            inputCount: spendableUTXOs.count,
            feeRatePerKB: feeRateDOGEPerKB
        )
        let maxSendableDOGE = Double(preview.spendable) / koinuPerDOGE

        return DogecoinSendPreview(
            spendableBalanceDOGE: spendableBalanceDOGE,
            requestedAmountDOGE: amountDOGE,
            estimatedNetworkFeeDOGE: Double(spendPlan.fee) / koinuPerDOGE,
            estimatedFeeRateDOGEPerKB: feeRateDOGEPerKB,
            estimatedTransactionBytes: spendPlan.estimatedTransactionBytes,
            selectedInputCount: spendPlan.utxos.count,
            usesChangeOutput: spendPlan.usesChangeOutput,
            feePriority: feePriority,
            maxSendableDOGE: maxSendableDOGE,
            spendableBalance: spendableBalanceDOGE,
            feeRateDescription: String(format: "%.4f DOGE/KB", feeRateDOGEPerKB),
            maxSendable: maxSendableDOGE
        )
    }

    static func fetchSendPreviewInBackground(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) async throws -> DogecoinSendPreview {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let preview = try fetchSendPreview(
                        from: importedWallet,
                        seedPhrase: seedPhrase,
                        amountDOGE: amountDOGE,
                        feePriority: feePriority,
                        maxInputCount: maxInputCount,
                        derivationAccount: derivationAccount
                    )
                    continuation.resume(returning: preview)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    static func send(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        to recipientAddress: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        changeIndex: Int? = nil,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) throws -> DogecoinSendResult {
        let networkMode = networkMode(for: importedWallet)
        guard AddressValidation.isValidDogecoinAddress(recipientAddress, networkMode: networkMode) else {
            throw DogecoinWalletEngineError.invalidRecipientAddress
        }
        guard amountDOGE > 0 else {
            throw DogecoinWalletEngineError.invalidAmount
        }

        let keyMaterial = try deriveSigningKeyMaterial(
            seedPhrase: seedPhrase,
            expectedAddress: importedWallet.dogecoinAddress,
            networkMode: networkMode,
            derivationAccount: derivationAccount
        )

        let spendableUTXOs = try fetchSpendableUTXOs(for: keyMaterial.address, networkMode: networkMode)
        guard !spendableUTXOs.isEmpty else {
            throw DogecoinWalletEngineError.noSpendableUTXOs
        }

        let feeRateDOGEPerKB = try resolveNetworkFeeRateDOGEPerKB(
            feePriority: feePriority,
            networkMode: networkMode
        )
            let spendPlan = try buildSpendPlan(
                from: spendableUTXOs,
                amountDOGE: amountDOGE,
                feeRateDOGEPerKB: feeRateDOGEPerKB,
                maxInputCount: maxInputCount
            )
            guard spendPlan.estimatedTransactionBytes <= maxStandardTransactionBytes else {
                throw DogecoinWalletEngineError.transactionTooLarge
            }

            let resolvedChangeAddress = try resolveChangeAddress(
                seedPhrase: seedPhrase,
                keyMaterial: keyMaterial,
                networkMode: networkMode,
                changeIndex: changeIndex,
                derivationAccount: derivationAccount
            )
            let signingResult = try walletCoreSignTransaction(
                keyMaterial: keyMaterial,
                utxos: spendPlan.utxos,
                destinationAddress: recipientAddress,
                amountDOGE: amountDOGE,
                changeAddress: resolvedChangeAddress.address,
                feeRateDOGEPerKB: feeRateDOGEPerKB
            )
            let rawHex = signingResult.encodedTransaction.map { String(format: "%02x", $0) }.joined()
            guard !rawHex.isEmpty else {
                throw DogecoinWalletEngineError.transactionSignFailed
            }
            let rawByteCount = rawHex.count / 2
            guard rawByteCount <= maxStandardTransactionBytes else {
            throw DogecoinWalletEngineError.transactionTooLarge
        }

            try broadcastRawTransaction(rawHex, networkMode: networkMode)
            let txid = signingResult.transactionHash.isEmpty ? computeTXID(fromRawHex: rawHex) : signingResult.transactionHash
            let verificationStatus = verifyBroadcastedTransactionIfAvailable(txid: txid, networkMode: networkMode)
        return DogecoinSendResult(
            transactionHash: txid,
            verificationStatus: verificationStatus,
            derivationMetadata: DerivationMetadata(
                sourceAddress: keyMaterial.address,
                sourceDerivationPath: keyMaterial.signingDerivationPath,
                changeAddress: resolvedChangeAddress.address,
                changeDerivationPath: resolvedChangeAddress.derivationPath
            ),
            rawTransactionHex: rawHex
        )
    }

    static func rebroadcastSignedTransaction(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        networkMode: DogecoinNetworkMode = .mainnet
    ) throws -> DogecoinRebroadcastResult {
        let trimmedRawHex = rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRawHex.isEmpty, let rawData = Data(hexEncoded: trimmedRawHex) else {
            throw DogecoinWalletEngineError.broadcastFailed("Signed transaction hex is missing or invalid.")
        }
        guard rawData.count <= maxStandardTransactionBytes else {
            throw DogecoinWalletEngineError.transactionTooLarge
        }

        let computedTXID = computeTXID(fromRawHex: trimmedRawHex)
        guard !computedTXID.isEmpty else {
            throw DogecoinWalletEngineError.broadcastFailed("Unable to compute txid from signed transaction.")
        }
        if let expectedTransactionHash {
            let expected = expectedTransactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard expected.isEmpty || expected == computedTXID.lowercased() else {
                throw DogecoinWalletEngineError.broadcastFailed("Signed transaction does not match the recorded txid.")
            }
        }

        try broadcastRawTransaction(trimmedRawHex, networkMode: networkMode)
        let verificationStatus = verifyPresenceOnlyIfAvailable(txid: computedTXID, networkMode: networkMode)
        return DogecoinRebroadcastResult(
            transactionHash: computedTXID,
            verificationStatus: verificationStatus
        )
    }

}

enum DogecoinWalletEngineError: LocalizedError {
    case invalidRecipientAddress
    case invalidAmount
    case invalidSeedPhrase
    case walletAddressNotDerivedFromSeed
    case keyDerivationFailed
    case noSpendableUTXOs
    case insufficientFunds
    case transactionBuildFailed(String)
    case transactionSignFailed
    case amountBelowDustThreshold
    case changeBelowDustThreshold
    case transactionTooLarge
    case networkFailure(String)
    case broadcastFailed(String)
    case preBroadcastValidationFailed(String)
    case postBroadcastVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRecipientAddress:
            return CommonLocalization.invalidDestinationAddressPrompt("Dogecoin")
        case .invalidAmount:
            return CommonLocalization.invalidAssetAmountPrompt("DOGE")
        case .invalidSeedPhrase:
            return NSLocalizedString("Unable to derive Dogecoin keys from this seed phrase.", comment: "")
        case .walletAddressNotDerivedFromSeed:
            return NSLocalizedString("The imported Dogecoin address does not match the provided seed phrase.", comment: "")
        case .keyDerivationFailed:
            return NSLocalizedString("Failed to derive the Dogecoin private key for signing.", comment: "")
        case .noSpendableUTXOs:
            return NSLocalizedString("No spendable Dogecoin UTXOs were found for this wallet.", comment: "")
        case .insufficientFunds:
            return CommonLocalization.insufficientBalanceForAmountPlusNetworkFee("DOGE")
        case .transactionBuildFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .transactionSignFailed:
            return CommonLocalization.signingTransactionFailed("Dogecoin")
        case .amountBelowDustThreshold:
            return NSLocalizedString("Amount is below Dogecoin dust threshold.", comment: "")
        case .changeBelowDustThreshold:
            return NSLocalizedString("Calculated change is below dust threshold. Increase amount or consolidate UTXOs.", comment: "")
        case .transactionTooLarge:
            return NSLocalizedString("Dogecoin transaction is too large for standard relay policy.", comment: "")
        case .networkFailure(let message):
            return CommonLocalization.networkError("Dogecoin", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Dogecoin", message: message)
        case .preBroadcastValidationFailed(let message):
            let format = NSLocalizedString("Dogecoin pre-broadcast validation failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .postBroadcastVerificationFailed(let message):
            let format = NSLocalizedString("Dogecoin post-broadcast verification failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}
