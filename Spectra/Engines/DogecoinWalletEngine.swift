// MARK: - File Overview
// Dogecoin engine implementing transaction creation, UTXO handling, broadcasting strategy hooks, and chain-specific signing behavior.
//
// Responsibilities:
// - Builds/signs DOGE transactions with chain policy and fee controls.
// - Integrates with provider selection and operational telemetry paths.

import Foundation
import CryptoKit
import WalletCore

struct DogecoinWalletEngine {
    private static let derivationScanLimit = 200
    private static let maxStandardTransactionBytes = 100_000
    private static let minRelayFeePerKB: Double = 0.01
    private static let dustThresholdDOGE: Double = 0.01
    private static let koinuPerDOGE: Double = 100_000_000
    private static let networkTimeoutSeconds: TimeInterval = 12
    private static let networkRetryCount = 2
    private static let utxoCacheTTLSeconds: TimeInterval = 180
    private static let utxoCacheLock = NSLock()
    private static var utxoCacheByAddress: [String: CachedUTXOSet] = [:]
    private static let broadcastReliabilityDefaultsKey = "dogecoin.broadcast.provider.reliability.v1"
    private static let broadcastProviderSelectionDefaultsKey = "dogecoin.broadcast.provider.selection.v1"
    private static let broadcastProviderSelectionLock = NSLock()
    private static let blockchairAPIBaseURLString = ChainBackendRegistry.DogecoinRuntimeEndpoints.blockchairBaseURL
    private static let blockcypherAPIBaseURLString = ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL

    private struct SigningKeyMaterial {
        let address: String
        let privateKeyData: Data
        let signingDerivationPath: String
        let changeAddress: String
        let changeDerivationPath: String
    }

    private struct DogecoinSpendPlan {
        let utxos: [DogecoinUTXO]
        let totalInputDOGE: Double
        let feeDOGE: Double
        let changeDOGE: Double
        let usesChangeOutput: Bool
        let estimatedTransactionBytes: Int
    }

    private struct DogecoinWalletCoreSigningRequest {
        let keyMaterial: SigningKeyMaterial
        let utxos: [DogecoinUTXO]
        let destinationAddress: String
        let amountDOGE: Double
        let changeAddress: String
        let feeRateDOGEPerKB: Double
    }

    private struct DogecoinWalletCoreSigningResult {
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

    private struct DogecoinUTXO: Decodable {
        let transactionHash: String
        let index: Int
        let value: UInt64

        enum CodingKeys: String, CodingKey {
            case transactionHash = "transaction_hash"
            case index
            case value
        }
    }

    private struct CachedUTXOSet {
        let utxos: [DogecoinUTXO]
        let updatedAt: Date
    }

    private struct DogecoinAddressDashboardEntry: Decodable {
        let utxo: [DogecoinUTXO]
    }

    private struct DogecoinAddressDashboardResponse: Decodable {
        let data: [String: DogecoinAddressDashboardEntry]
    }

    private struct BlockCypherAddressResponse: Decodable {
        struct UTXO: Decodable {
            let txHash: String
            let txOutputIndex: Int
            let value: UInt64

            enum CodingKeys: String, CodingKey {
                case txHash = "tx_hash"
                case txOutputIndex = "tx_output_n"
                case value
            }
        }

        let txrefs: [UTXO]?
        let unconfirmedTxrefs: [UTXO]?

        enum CodingKeys: String, CodingKey {
            case txrefs
            case unconfirmedTxrefs = "unconfirmed_txrefs"
        }
    }

    private struct BlockCypherNetworkResponse: Decodable {
        let highFeePerKB: Double?
        let mediumFeePerKB: Double?
        let lowFeePerKB: Double?

        enum CodingKeys: String, CodingKey {
            case highFeePerKB = "high_fee_per_kb"
            case mediumFeePerKB = "medium_fee_per_kb"
            case lowFeePerKB = "low_fee_per_kb"
        }
    }

    private struct BlockchairTransactionDashboardResponse: Decodable {
        let data: [String: BlockchairTransactionDashboardEntry]
    }

    private struct BlockchairTransactionDashboardEntry: Decodable {
        let transaction: BlockchairTransaction
    }

    private struct BlockchairTransaction: Decodable {
        let hash: String?
    }

    private struct BlockCypherTransactionResponse: Decodable {
        let hash: String?
    }

    private struct SoChainTransactionResponse: Decodable {
        struct Payload: Decodable {
            let txid: String?
        }

        let status: String?
        let data: Payload?
    }

    private enum UTXOProvider: String, CaseIterable {
        case blockchair
        case blockcypher
    }

    private enum BroadcastProvider: String, CaseIterable {
        case blockchair
        case blockcypher
    }

    private struct BroadcastProviderReliabilityCounter: Codable {
        var successCount: Int
        var failureCount: Int
        var lastUpdatedAt: TimeInterval
    }

    struct BroadcastProviderReliability: Identifiable, Equatable {
        let providerID: String
        let successCount: Int
        let failureCount: Int
        let successRate: Double

        var id: String { providerID }
    }

    /// Dogecoin engine operation: Broadcast provider reliability snapshot.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func broadcastProviderReliabilitySnapshot() -> [BroadcastProviderReliability] {
        let counters = loadBroadcastReliabilityCounters()
        return orderedBroadcastProviders(counters: counters).map { provider in
            let counter = counters[provider.rawValue] ?? BroadcastProviderReliabilityCounter(
                successCount: 0,
                failureCount: 0,
                lastUpdatedAt: 0
            )
            let attempts = max(1, counter.successCount + counter.failureCount)
            return BroadcastProviderReliability(
                providerID: provider.rawValue,
                successCount: counter.successCount,
                failureCount: counter.failureCount,
                successRate: Double(counter.successCount) / Double(attempts)
            )
        }
    }

    /// Dogecoin engine operation: Configure broadcast providers.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func configureBroadcastProviders(useBlockchair: Bool, useBlockCypher: Bool) {
        broadcastProviderSelectionLock.lock()
        defer { broadcastProviderSelectionLock.unlock() }

        var enabledProviderIDs: [String] = []
        if useBlockchair {
            enabledProviderIDs.append(BroadcastProvider.blockchair.rawValue)
        }
        if useBlockCypher {
            enabledProviderIDs.append(BroadcastProvider.blockcypher.rawValue)
        }
        UserDefaults.standard.set(enabledProviderIDs, forKey: broadcastProviderSelectionDefaultsKey)
    }

    /// Dogecoin engine operation: Reset broadcast provider reliability.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func resetBroadcastProviderReliability() {
        UserDefaults.standard.removeObject(forKey: broadcastReliabilityDefaultsKey)
    }

    /// Dogecoin engine operation: Reset broadcast provider selection.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func resetBroadcastProviderSelection() {
        broadcastProviderSelectionLock.lock()
        defer { broadcastProviderSelectionLock.unlock() }
        UserDefaults.standard.removeObject(forKey: broadcastProviderSelectionDefaultsKey)
    }

    /// Dogecoin engine operation: Reset utxocache.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func resetUTXOCache() {
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress.removeAll()
    }

    @discardableResult
    /// Dogecoin engine operation: Send in background.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
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

    /// Dogecoin engine operation: Rebroadcast signed transaction in background.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func rebroadcastSignedTransactionInBackground(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil
    ) async throws -> DogecoinRebroadcastResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try rebroadcastSignedTransaction(
                        rawTransactionHex: rawTransactionHex,
                        expectedTransactionHash: expectedTransactionHash
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Dogecoin engine operation: Derived address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func derivedAddress(for seedPhrase: String, account: Int = 0) throws -> String {
        try walletCoreDerivedAddress(seedPhrase: seedPhrase, isChange: false, index: 0, account: account)
    }

    /// Dogecoin engine operation: Derived address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func derivedAddress(for seedPhrase: String, isChange: Bool, index: Int, account: Int = 0) throws -> String {
        try walletCoreDerivedAddress(seedPhrase: seedPhrase, isChange: isChange, index: index, account: account)
    }

    /// Dogecoin engine operation: Fetch send preview.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
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
            derivationAccount: derivationAccount
        )
        let spendableUTXOs = try fetchSpendableUTXOs(for: keyMaterial.address)
        guard !spendableUTXOs.isEmpty else {
            throw DogecoinWalletEngineError.noSpendableUTXOs
        }

        let feeRateDOGEPerKB = resolveNetworkFeeRateDOGEPerKB(feePriority: feePriority)
        let spendPlan = try buildSpendPlan(
            from: spendableUTXOs,
            amountDOGE: amountDOGE,
            feeRateDOGEPerKB: feeRateDOGEPerKB,
            maxInputCount: maxInputCount
        )
        let spendableBalanceDOGE = Double(spendableUTXOs.reduce(0) { $0 + $1.value }) / koinuPerDOGE
        let maxSendableBytes = estimateTransactionBytes(inputCount: spendableUTXOs.count, outputCount: 1)
        let maxSendableFeeDOGE = estimateNetworkFeeDOGE(
            estimatedBytes: maxSendableBytes,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let maxSendableDOGE = max(0, spendableBalanceDOGE - maxSendableFeeDOGE)

        return DogecoinSendPreview(
            spendableBalanceDOGE: spendableBalanceDOGE,
            requestedAmountDOGE: amountDOGE,
            estimatedNetworkFeeDOGE: spendPlan.feeDOGE,
            estimatedFeeRateDOGEPerKB: feeRateDOGEPerKB,
            estimatedTransactionBytes: spendPlan.estimatedTransactionBytes,
            selectedInputCount: spendPlan.utxos.count,
            usesChangeOutput: spendPlan.usesChangeOutput,
            feePriority: feePriority,
            maxSendableDOGE: maxSendableDOGE
        )
    }

    /// Dogecoin engine operation: Fetch send preview in background.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
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
    /// Dogecoin engine operation: Send.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
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
        guard AddressValidation.isValidDogecoinAddress(recipientAddress, allowTestnet: true) else {
            throw DogecoinWalletEngineError.invalidRecipientAddress
        }
        guard amountDOGE > 0 else {
            throw DogecoinWalletEngineError.invalidAmount
        }

        let keyMaterial = try deriveSigningKeyMaterial(
            seedPhrase: seedPhrase,
            expectedAddress: importedWallet.dogecoinAddress,
            derivationAccount: derivationAccount
        )

        let spendableUTXOs = try fetchSpendableUTXOs(for: keyMaterial.address)
        guard !spendableUTXOs.isEmpty else {
            throw DogecoinWalletEngineError.noSpendableUTXOs
        }

        let feeRateDOGEPerKB = resolveNetworkFeeRateDOGEPerKB(feePriority: feePriority)
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

            try broadcastRawTransaction(rawHex)
            let txid = signingResult.transactionHash.isEmpty ? computeTXID(fromRawHex: rawHex) : signingResult.transactionHash
            let verificationStatus = verifyBroadcastedTransactionIfAvailable(txid: txid)
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

    /// Dogecoin engine operation: Rebroadcast signed transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func rebroadcastSignedTransaction(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil
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

        try broadcastRawTransaction(trimmedRawHex)
        let verificationStatus = verifyPresenceOnlyIfAvailable(txid: computedTXID)
        return DogecoinRebroadcastResult(
            transactionHash: computedTXID,
            verificationStatus: verificationStatus
        )
    }

    /// Dogecoin engine operation: Resolve change address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func resolveChangeAddress(
        seedPhrase: String,
        keyMaterial: SigningKeyMaterial,
        changeIndex: Int?,
        derivationAccount: UInt32
    ) throws -> (address: String, derivationPath: String) {
        guard let changeIndex else {
            return (keyMaterial.changeAddress, keyMaterial.changeDerivationPath)
        }

        let address = try derivedAddress(
            for: seedPhrase,
            isChange: true,
            index: changeIndex,
            account: Int(derivationAccount)
        )
        return (
            address,
            WalletDerivationPath.dogecoin(
                account: derivationAccount,
                branch: .change,
                index: UInt32(changeIndex)
            )
        )
    }

    /// Dogecoin engine operation: Derive signing key material.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func deriveSigningKeyMaterial(
        seedPhrase: String,
        expectedAddress: String?,
        derivationAccount: UInt32
    ) throws -> SigningKeyMaterial {
        try deriveSigningKeyMaterialWithWalletCore(
            seedPhrase: seedPhrase,
            expectedAddress: expectedAddress,
            derivationAccount: derivationAccount
        )
    }

    /// Dogecoin engine operation: Derive signing key material with wallet core.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func deriveSigningKeyMaterialWithWalletCore(
        seedPhrase: String,
        expectedAddress: String?,
        derivationAccount: UInt32
    ) throws -> SigningKeyMaterial {
        let normalizedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let normalizedExpectedAddress = expectedAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mnemonicWords = BitcoinWalletEngine.normalizedMnemonicWords(from: normalizedSeedPhrase)
        guard !mnemonicWords.isEmpty else {
            throw DogecoinWalletEngineError.invalidSeedPhrase
        }
        for index in 0 ..< derivationScanLimit {
            let signingMaterial = try WalletCoreDerivation.deriveMaterial(
                seedPhrase: normalizedSeedPhrase,
                coin: .dogecoin,
                account: derivationAccount,
                branch: .external,
                index: UInt32(index)
            )
            let signingAddress = signingMaterial.address
            if let normalizedExpectedAddress, normalizedExpectedAddress != signingAddress {
                continue
            }

            let changeMaterial = try WalletCoreDerivation.deriveMaterial(
                seedPhrase: normalizedSeedPhrase,
                coin: .dogecoin,
                account: derivationAccount,
                branch: .change,
                index: UInt32(index)
            )
            return SigningKeyMaterial(
                address: signingAddress,
                privateKeyData: signingMaterial.privateKeyData,
                signingDerivationPath: signingMaterial.derivationPath,
                changeAddress: changeMaterial.address,
                changeDerivationPath: changeMaterial.derivationPath
            )
        }
        throw DogecoinWalletEngineError.walletAddressNotDerivedFromSeed
    }

    /// Dogecoin engine operation: Wallet core sign transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func walletCoreSignTransaction(
        keyMaterial: SigningKeyMaterial,
        utxos: [DogecoinUTXO],
        destinationAddress: String,
        amountDOGE: Double,
        changeAddress: String,
        feeRateDOGEPerKB: Double
    ) throws -> DogecoinWalletCoreSigningResult {
        let request = DogecoinWalletCoreSigningRequest(
            keyMaterial: keyMaterial,
            utxos: utxos,
            destinationAddress: destinationAddress,
            amountDOGE: amountDOGE,
            changeAddress: changeAddress,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let signingInput = try buildWalletCoreSigningInput(from: request)
        return try signWithWalletCore(input: signingInput)
    }

    /// Dogecoin engine operation: Build wallet core signing input.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func buildWalletCoreSigningInput(
        from request: DogecoinWalletCoreSigningRequest
    ) throws -> BitcoinSigningInput {
        guard let sourceScript = standardScriptPubKey(for: request.keyMaterial.address) else {
            throw DogecoinWalletEngineError.transactionBuildFailed("Unable to derive source script for selected UTXOs.")
        }
        let amountKoinu = UInt64((request.amountDOGE * koinuPerDOGE).rounded())
        let feePerByteKoinu = max(1, Int64(((request.feeRateDOGEPerKB * koinuPerDOGE) / 1_000).rounded(.up)))

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x01
        signingInput.amount = Int64(amountKoinu)
        signingInput.byteFee = feePerByteKoinu
        signingInput.toAddress = request.destinationAddress
        signingInput.changeAddress = request.changeAddress
        signingInput.coinType = CoinType.dogecoin.rawValue
        signingInput.privateKey = [request.keyMaterial.privateKeyData]
        signingInput.utxo = try request.utxos.map { try walletCoreUnspentTransaction(from: $0, sourceScript: sourceScript) }
        return signingInput
    }

    /// Dogecoin engine operation: Wallet core unspent transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func walletCoreUnspentTransaction(
        from utxo: DogecoinUTXO,
        sourceScript: Data
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.transactionHash), txHashData.count == 32 else {
            throw DogecoinWalletEngineError.transactionBuildFailed("One or more UTXOs had invalid txid encoding.")
        }
        var outPoint = BitcoinOutPoint()
        outPoint.hash = Data(txHashData.reversed())
        outPoint.index = UInt32(utxo.index)
        outPoint.sequence = UInt32.max

        var unspent = BitcoinUnspentTransaction()
        unspent.amount = Int64(utxo.value)
        unspent.script = sourceScript
        unspent.outPoint = outPoint
        return unspent
    }

    /// Dogecoin engine operation: Sign with wallet core.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func signWithWalletCore(input: BitcoinSigningInput) throws -> DogecoinWalletCoreSigningResult {
        let output: BitcoinSigningOutput = AnySigner.sign(input: input, coin: .dogecoin)
        if !output.errorMessage.isEmpty {
            throw DogecoinWalletEngineError.transactionSignFailed
        }
        guard !output.encoded.isEmpty else {
            throw DogecoinWalletEngineError.transactionSignFailed
        }
        return DogecoinWalletCoreSigningResult(
            encodedTransaction: output.encoded,
            transactionHash: output.transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Dogecoin engine operation: Wallet core derived address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func walletCoreDerivedAddress(
        seedPhrase: String,
        isChange: Bool,
        index: Int,
        account: Int
    ) throws -> String {
        guard index >= 0 else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        let normalizedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let mnemonicWords = BitcoinWalletEngine.normalizedMnemonicWords(from: normalizedSeedPhrase)
        guard !mnemonicWords.isEmpty else {
            throw DogecoinWalletEngineError.invalidSeedPhrase
        }
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeedPhrase,
            coin: .dogecoin,
            account: UInt32(max(0, account)),
            branch: isChange ? .change : .external,
            index: UInt32(index)
        )
        guard !material.address.isEmpty else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        return material.address
    }

    /// Dogecoin engine operation: Fetch spendable utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchSpendableUTXOs(for address: String) throws -> [DogecoinUTXO] {
        var providerErrors: [String] = []
        var providerResults: [UTXOProvider: [DogecoinUTXO]] = [:]

        for provider in UTXOProvider.allCases {
            do {
                let utxos: [DogecoinUTXO]
                switch provider {
                case .blockchair:
                    utxos = try fetchBlockchairUTXOs(for: address)
                case .blockcypher:
                    utxos = try fetchBlockCypherUTXOs(for: address)
                }
                providerResults[provider] = sanitizeUTXOs(utxos)
            } catch {
                providerErrors.append("\(provider.rawValue): \(error.localizedDescription)")
                continue
            }
        }

        if providerResults.isEmpty {
            if let cached = cachedUTXOs(for: address) {
                return cached
            }
            throw DogecoinWalletEngineError.networkFailure("All UTXO providers failed (\(providerErrors.joined(separator: " | "))).")
        }

        let merged: [DogecoinUTXO]
        if let blockchairUTXOs = providerResults[.blockchair],
           let blockcypherUTXOs = providerResults[.blockcypher] {
            merged = try mergeConsistentUTXOs(
                blockchairUTXOs: blockchairUTXOs,
                blockcypherUTXOs: blockcypherUTXOs
            )
        } else {
            merged = providerResults.values.first ?? []
        }

        if !merged.isEmpty {
            cacheUTXOs(merged, for: address)
            return merged
        }

        if let cached = cachedUTXOs(for: address) {
            return cached
        }

        return []
    }

    /// Dogecoin engine operation: Sanitize utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func sanitizeUTXOs(_ utxos: [DogecoinUTXO]) -> [DogecoinUTXO] {
        var deduped: [String: DogecoinUTXO] = [:]
        for utxo in utxos where utxo.value > 0 {
            let key = outpointKey(hash: utxo.transactionHash, index: utxo.index)
            if let existing = deduped[key] {
                deduped[key] = existing.value >= utxo.value ? existing : utxo
            } else {
                deduped[key] = utxo
            }
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            if lhs.transactionHash != rhs.transactionHash {
                return lhs.transactionHash < rhs.transactionHash
            }
            return lhs.index < rhs.index
        }
    }

    /// Dogecoin engine operation: Merge consistent utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func mergeConsistentUTXOs(
        blockchairUTXOs: [DogecoinUTXO],
        blockcypherUTXOs: [DogecoinUTXO]
    ) throws -> [DogecoinUTXO] {
        let blockchairMap = Dictionary(uniqueKeysWithValues: blockchairUTXOs.map { (outpointKey(hash: $0.transactionHash, index: $0.index), $0) })
        let blockcypherMap = Dictionary(uniqueKeysWithValues: blockcypherUTXOs.map { (outpointKey(hash: $0.transactionHash, index: $0.index), $0) })

        let blockchairKeys = Set(blockchairMap.keys)
        let blockcypherKeys = Set(blockcypherMap.keys)
        let overlap = blockchairKeys.intersection(blockcypherKeys)

        for key in overlap {
            guard let lhs = blockchairMap[key], let rhs = blockcypherMap[key] else { continue }
            if lhs.value != rhs.value {
                throw DogecoinWalletEngineError.networkFailure("UTXO providers returned conflicting values for the same outpoint. Refusing to build Dogecoin transaction.")
            }
        }

        if !blockchairKeys.isEmpty, !blockcypherKeys.isEmpty, overlap.isEmpty {
            throw DogecoinWalletEngineError.networkFailure("UTXO providers disagree on spendable set (no overlap). Refusing to build Dogecoin transaction.")
        }

        let merged = Array(blockchairMap.values) + blockcypherMap.compactMap { key, value in
            blockchairMap[key] == nil ? value : nil
        }
        return sanitizeUTXOs(merged)
    }

    /// Dogecoin engine operation: Outpoint key.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
    }

    /// Dogecoin engine operation: Normalized base urlstring.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    /// Dogecoin engine operation: Blockchair url.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func blockchairURL(path: String) -> URL? {
        URL(string: blockchairAPIBaseURLString + path)
    }

    /// Dogecoin engine operation: Blockcypher url.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func blockcypherURL(path: String) -> URL? {
        URL(string: blockcypherAPIBaseURLString + path)
    }

    /// Dogecoin engine operation: Normalized address cache key.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func normalizedAddressCacheKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Dogecoin engine operation: Cache utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func cacheUTXOs(_ utxos: [DogecoinUTXO], for address: String) {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress[key] = CachedUTXOSet(utxos: utxos, updatedAt: Date())
    }

    /// Dogecoin engine operation: Cached utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func cachedUTXOs(for address: String) -> [DogecoinUTXO]? {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        guard let cached = utxoCacheByAddress[key] else { return nil }
        guard Date().timeIntervalSince(cached.updatedAt) <= utxoCacheTTLSeconds else {
            utxoCacheByAddress[key] = nil
            return nil
        }
        return cached.utxos
    }

    /// Dogecoin engine operation: Fetch blockchair utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockchairUTXOs(for address: String) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let baseURL = blockchairURL(path: "/dashboards/address/\(encodedAddress)"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }
        components.queryItems = [URLQueryItem(name: "limit", value: "200")]
        guard let url = components.url else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(DogecoinAddressDashboardResponse.self, from: data)
        guard let entry = payload.data.values.first else {
            return []
        }
        return entry.utxo
    }

    /// Dogecoin engine operation: Fetch block cypher utxos.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockCypherUTXOs(for address: String) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let baseURL = blockcypherURL(path: "/addrs/\(encodedAddress)"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "unspentOnly", value: "true"),
            URLQueryItem(name: "includeScript", value: "true"),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components.url else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherAddressResponse.self, from: data)
        let confirmed = payload.txrefs ?? []
        let pending = payload.unconfirmedTxrefs ?? []
        return (confirmed + pending).map {
            DogecoinUTXO(transactionHash: $0.txHash, index: $0.txOutputIndex, value: $0.value)
        }
    }

    /// Dogecoin engine operation: Build spend plan.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func buildSpendPlan(
        from utxos: [DogecoinUTXO],
        amountDOGE: Double,
        feeRateDOGEPerKB: Double,
        maxInputCount: Int?
    ) throws -> DogecoinSpendPlan {
        guard amountDOGE >= dustThresholdDOGE else {
            throw DogecoinWalletEngineError.amountBelowDustThreshold
        }

        let sortedUTXOs = utxos.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            if $0.transactionHash != $1.transactionHash { return $0.transactionHash < $1.transactionHash }
            return $0.index < $1.index
        }

        let effectiveMaxInputCount = maxInputCount.map { max(1, $0) }
        var candidates: [[DogecoinUTXO]] = []
        candidates.reserveCapacity(sortedUTXOs.count * 2)

        var prefix: [DogecoinUTXO] = []
        prefix.reserveCapacity(sortedUTXOs.count)
        for utxo in sortedUTXOs {
            prefix.append(utxo)
            if let effectiveMaxInputCount, prefix.count > effectiveMaxInputCount {
                continue
            }
            candidates.append(prefix)
        }

        for utxo in sortedUTXOs {
            candidates.append([utxo])
        }

        var bestPlan: DogecoinSpendPlan?
        for candidate in candidates {
            guard let plan = evaluateCandidate(
                candidate,
                amountDOGE: amountDOGE,
                feeRateDOGEPerKB: feeRateDOGEPerKB
            ) else {
                continue
            }
            if let currentBest = bestPlan {
                if isBetterSpendPlan(plan, than: currentBest) {
                    bestPlan = plan
                }
            } else {
                bestPlan = plan
            }
        }

        guard let bestPlan else {
            throw DogecoinWalletEngineError.insufficientFunds
        }
        return bestPlan
    }

    /// Dogecoin engine operation: Evaluate candidate.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func evaluateCandidate(
        _ utxos: [DogecoinUTXO],
        amountDOGE: Double,
        feeRateDOGEPerKB: Double
    ) -> DogecoinSpendPlan? {
        guard !utxos.isEmpty else { return nil }
        let inputDOGE = Double(utxos.reduce(0) { $0 + $1.value }) / koinuPerDOGE

        let bytesWithChange = estimateTransactionBytes(inputCount: utxos.count, outputCount: 2)
        let feeWithChange = estimateNetworkFeeDOGE(
            estimatedBytes: bytesWithChange,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let changeWithChange = inputDOGE - amountDOGE - feeWithChange
        if changeWithChange >= dustThresholdDOGE {
            return DogecoinSpendPlan(
                utxos: utxos,
                totalInputDOGE: inputDOGE,
                feeDOGE: feeWithChange,
                changeDOGE: changeWithChange,
                usesChangeOutput: true,
                estimatedTransactionBytes: bytesWithChange
            )
        }

        let bytesWithoutChange = estimateTransactionBytes(inputCount: utxos.count, outputCount: 1)
        let baseFeeWithoutChange = estimateNetworkFeeDOGE(
            estimatedBytes: bytesWithoutChange,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let remainderDOGE = inputDOGE - amountDOGE - baseFeeWithoutChange
        guard remainderDOGE >= 0 else {
            return nil
        }
        let effectiveFeeDOGE = baseFeeWithoutChange + remainderDOGE
        return DogecoinSpendPlan(
            utxos: utxos,
            totalInputDOGE: inputDOGE,
            feeDOGE: effectiveFeeDOGE,
            changeDOGE: 0,
            usesChangeOutput: false,
            estimatedTransactionBytes: bytesWithoutChange
        )
    }

    /// Dogecoin engine operation: Is better spend plan.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func isBetterSpendPlan(_ lhs: DogecoinSpendPlan, than rhs: DogecoinSpendPlan) -> Bool {
        if lhs.usesChangeOutput != rhs.usesChangeOutput {
            return lhs.usesChangeOutput && !rhs.usesChangeOutput
        }
        if lhs.utxos.count != rhs.utxos.count {
            return lhs.utxos.count < rhs.utxos.count
        }
        if lhs.feeDOGE != rhs.feeDOGE {
            return lhs.feeDOGE < rhs.feeDOGE
        }
        return lhs.changeDOGE < rhs.changeDOGE
    }

    /// Dogecoin engine operation: Estimate transaction bytes.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func estimateTransactionBytes(inputCount: Int, outputCount: Int) -> Int {
        // Conservative P2PKH approximation for Dogecoin.
        10 + (148 * inputCount) + (34 * outputCount)
    }

    /// Dogecoin engine operation: Estimate network fee doge.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func estimateNetworkFeeDOGE(estimatedBytes: Int, feeRateDOGEPerKB: Double) -> Double {
        let kb = max(1, Int(ceil(Double(estimatedBytes) / 1000)))
        return Double(kb) * max(minRelayFeePerKB, feeRateDOGEPerKB)
    }

    /// Dogecoin engine operation: Resolve network fee rate dogeper kb.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func resolveNetworkFeeRateDOGEPerKB(feePriority: FeePriority) -> Double {
        let candidates = (try? fetchBlockCypherFeeRateCandidatesDOGEPerKB()) ?? []
        let deterministicFallback: Double
        switch feePriority {
        case .economy:
            deterministicFallback = minRelayFeePerKB
        case .normal:
            deterministicFallback = max(minRelayFeePerKB, 0.015)
        case .priority:
            deterministicFallback = max(minRelayFeePerKB, 0.03)
        }
        let baseRate: Double
        if candidates.isEmpty {
            baseRate = deterministicFallback
        } else {
            let sorted = candidates.sorted()
            baseRate = sorted[sorted.count / 2]
        }
        let boundedRate = max(minRelayFeePerKB, min(baseRate, 10))
        return adjustedFeeRateDOGEPerKB(baseRate: boundedRate, feePriority: feePriority)
    }

    /// Dogecoin engine operation: Adjusted fee rate dogeper kb.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func adjustedFeeRateDOGEPerKB(baseRate: Double, feePriority: FeePriority) -> Double {
        let multiplier: Double
        switch feePriority {
        case .economy:
            multiplier = 0.9
        case .normal:
            multiplier = 1.0
        case .priority:
            multiplier = 1.25
        }
        let adjusted = baseRate * multiplier
        return max(minRelayFeePerKB, min(adjusted, 25))
    }

    /// Dogecoin engine operation: Fetch block cypher fee rate candidates dogeper kb.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockCypherFeeRateCandidatesDOGEPerKB() throws -> [Double] {
        guard let url = blockcypherURL(path: "") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin network fee endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherNetworkResponse.self, from: data)

        let rawCandidates = [payload.lowFeePerKB, payload.mediumFeePerKB, payload.highFeePerKB]
        let candidates = rawCandidates
            .compactMap { $0 }
            .map { $0 / koinuPerDOGE }
            .filter { $0 > 0 }

        guard !candidates.isEmpty else {
            throw DogecoinWalletEngineError.networkFailure("Fee-rate data was missing from BlockCypher.")
        }

        return candidates
    }

    /// Dogecoin engine operation: Perform synchronous request.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func performSynchronousRequest(
        _ request: URLRequest,
        timeout: TimeInterval = networkTimeoutSeconds,
        retries: Int = networkRetryCount
    ) throws -> Data {
        do {
            return try UTXOEngineSupport.performSynchronousRequest(
                request,
                timeout: timeout,
                retries: retries
            )
        } catch {
            throw DogecoinWalletEngineError.networkFailure(error.localizedDescription)
        }
    }

    /// Dogecoin engine operation: Broadcast raw transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func broadcastRawTransaction(_ rawHex: String) throws {
        let providerOrder = orderedBroadcastProviders(counters: loadBroadcastReliabilityCounters())
        var providerErrors: [String] = []

        for provider in providerOrder {
            let maxAttempts = 2
            for attempt in 0 ..< maxAttempts {
                do {
                    try broadcastRawTransaction(rawHex, via: provider)
                    recordBroadcastAttempt(provider: provider, success: true)
                    return
                } catch {
                    let errorDescription = error.localizedDescription
                    if isAlreadyBroadcastedError(errorDescription) {
                        recordBroadcastAttempt(provider: provider, success: true)
                        return
                    }

                    recordBroadcastAttempt(provider: provider, success: false)
                    let shouldRetry = attempt < maxAttempts - 1 && isRetryableBroadcastError(errorDescription)
                    if shouldRetry {
                        usleep(UInt32(250_000 * (attempt + 1)))
                        continue
                    }

                    providerErrors.append("\(provider.rawValue.capitalized): \(errorDescription)")
                    break
                }
            }
        }

        let message = providerErrors.isEmpty
            ? "No broadcast provider accepted the transaction."
            : providerErrors.joined(separator: " | ")
        throw DogecoinWalletEngineError.broadcastFailed(message)
    }

    /// Dogecoin engine operation: Broadcast raw transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func broadcastRawTransaction(_ rawHex: String, via provider: BroadcastProvider) throws {
        switch provider {
        case .blockchair:
            try broadcastRawTransactionViaBlockchair(rawHex)
        case .blockcypher:
            try broadcastRawTransactionViaBlockCypher(rawHex)
        }
    }

    /// Dogecoin engine operation: Broadcast raw transaction via blockchair.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func broadcastRawTransactionViaBlockchair(_ rawHex: String) throws {
        guard let url = blockchairURL(path: "/push/transaction") else {
            throw DogecoinWalletEngineError.broadcastFailed("Invalid Dogecoin broadcast endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: rawHex)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let context = object["context"] as? [String: Any],
           let errorMessage = context["error"] as? String,
           !errorMessage.isEmpty {
            throw DogecoinWalletEngineError.broadcastFailed(errorMessage)
        }
    }

    /// Dogecoin engine operation: Broadcast raw transaction via block cypher.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func broadcastRawTransactionViaBlockCypher(_ rawHex: String) throws {
        guard let url = blockcypherURL(path: "/txs/push") else {
            throw DogecoinWalletEngineError.broadcastFailed("Invalid BlockCypher broadcast endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tx": rawHex], options: [])

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorMessage = object["error"] as? String, !errorMessage.isEmpty {
                throw DogecoinWalletEngineError.broadcastFailed(errorMessage)
            }
            if let errors = object["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["error"] as? String,
               !message.isEmpty {
                throw DogecoinWalletEngineError.broadcastFailed(message)
            }
        }
    }

    /// Dogecoin engine operation: Is already broadcasted error.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func isAlreadyBroadcastedError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("already known")
            || normalized.contains("already in blockchain")
            || normalized.contains("already in block chain")
            || normalized.contains("already exists")
            || normalized.contains("already have transaction")
            || normalized.contains("txn-already")
            || normalized.contains("already spent")
    }

    /// Dogecoin engine operation: Is retryable broadcast error.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func isRetryableBroadcastError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("timed out")
            || normalized.contains("timeout")
            || normalized.contains("temporarily")
            || normalized.contains("connection")
            || normalized.contains("network")
            || normalized.contains("server error")
            || normalized.contains("bad gateway")
            || normalized.contains("service unavailable")
            || normalized.contains("too many requests")
            || normalized.contains("429")
            || normalized.contains("502")
            || normalized.contains("503")
            || normalized.contains("504")
    }

    /// Dogecoin engine operation: Ordered broadcast providers.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func orderedBroadcastProviders(
        counters: [String: BroadcastProviderReliabilityCounter]
    ) -> [BroadcastProvider] {
        enabledBroadcastProviders().sorted { lhs, rhs in
            let left = counters[lhs.rawValue] ?? BroadcastProviderReliabilityCounter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)
            let right = counters[rhs.rawValue] ?? BroadcastProviderReliabilityCounter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)

            let leftAttempts = left.successCount + left.failureCount
            let rightAttempts = right.successCount + right.failureCount
            let leftSuccessRate = leftAttempts == 0 ? 1.0 : Double(left.successCount) / Double(leftAttempts)
            let rightSuccessRate = rightAttempts == 0 ? 1.0 : Double(right.successCount) / Double(rightAttempts)

            if leftSuccessRate != rightSuccessRate {
                return leftSuccessRate > rightSuccessRate
            }
            if left.successCount != right.successCount {
                return left.successCount > right.successCount
            }
            return left.lastUpdatedAt > right.lastUpdatedAt
        }
    }

    /// Dogecoin engine operation: Enabled broadcast providers.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func enabledBroadcastProviders() -> [BroadcastProvider] {
        broadcastProviderSelectionLock.lock()
        defer { broadcastProviderSelectionLock.unlock() }

        guard let configuredProviderIDs = UserDefaults.standard.array(forKey: broadcastProviderSelectionDefaultsKey) as? [String] else {
            return BroadcastProvider.allCases
        }

        let providers = configuredProviderIDs.compactMap(BroadcastProvider.init(rawValue:))
        return providers.isEmpty ? BroadcastProvider.allCases : providers
    }

    /// Dogecoin engine operation: Load broadcast reliability counters.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func loadBroadcastReliabilityCounters() -> [String: BroadcastProviderReliabilityCounter] {
        guard let data = UserDefaults.standard.data(forKey: broadcastReliabilityDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: BroadcastProviderReliabilityCounter].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// Dogecoin engine operation: Save broadcast reliability counters.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func saveBroadcastReliabilityCounters(_ counters: [String: BroadcastProviderReliabilityCounter]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: broadcastReliabilityDefaultsKey)
    }

    /// Dogecoin engine operation: Record broadcast attempt.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func recordBroadcastAttempt(provider: BroadcastProvider, success: Bool) {
        var counters = loadBroadcastReliabilityCounters()
        var counter = counters[provider.rawValue] ?? BroadcastProviderReliabilityCounter(
            successCount: 0,
            failureCount: 0,
            lastUpdatedAt: 0
        )
        if success {
            counter.successCount += 1
        } else {
            counter.failureCount += 1
        }
        counter.lastUpdatedAt = Date().timeIntervalSince1970
        counters[provider.rawValue] = counter
        saveBroadcastReliabilityCounters(counters)
    }

    /// Dogecoin engine operation: Verify broadcasted transaction if available.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func verifyBroadcastedTransactionIfAvailable(
        txid: String
    ) -> PostBroadcastVerificationStatus {
        let maxAttempts = 3

        for attempt in 0 ..< maxAttempts {
            let status = verifyPresenceOnlyIfAvailable(txid: txid)
            if status == .verified {
                return .verified
            }
            if attempt < maxAttempts - 1 {
                usleep(UInt32(350_000 * (attempt + 1)))
            }
        }

        return .deferred
    }

    /// Dogecoin engine operation: Verify presence only if available.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func verifyPresenceOnlyIfAvailable(txid: String) -> PostBroadcastVerificationStatus {
        if (try? fetchBlockchairTransactionHash(txid: txid)) != nil {
            return .verified
        }
        if (try? fetchBlockCypherTransactionHash(txid: txid)) != nil {
            return .verified
        }
        if (try? fetchSoChainTransactionHash(txid: txid)) != nil {
            return .verified
        }
        return .deferred
    }

    /// Dogecoin engine operation: Fetch blockchair transaction hash.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockchairTransactionHash(txid: String) throws -> String? {
        guard let entry = try fetchBlockchairTransaction(txid: txid),
              let txHash = entry.transaction.hash,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    /// Dogecoin engine operation: Fetch block cypher transaction hash.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockCypherTransactionHash(txid: String) throws -> String? {
        guard let payload = try fetchBlockCypherTransaction(txid: txid),
              let txHash = payload.hash,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    /// Dogecoin engine operation: Fetch so chain transaction hash.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchSoChainTransactionHash(txid: String) throws -> String? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(ChainBackendRegistry.DogecoinRuntimeEndpoints.sochainBaseURL)/get_tx/DOGE/\(encodedTXID)") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid SoChain transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )

        let payload = try JSONDecoder().decode(SoChainTransactionResponse.self, from: data)
        guard payload.status?.lowercased() == "success",
              let tx = payload.data,
              let txHash = tx.txid,
              !txHash.isEmpty else {
            return nil
        }

        return txHash
    }

    /// Dogecoin engine operation: Fetch blockchair transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockchairTransaction(txid: String) throws -> BlockchairTransactionDashboardEntry? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockchairURL(path: "/dashboards/transactions/\(encodedTXID)") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )
        let payload = try JSONDecoder().decode(BlockchairTransactionDashboardResponse.self, from: data)
        return payload.data.values.first
    }

    /// Dogecoin engine operation: Fetch block cypher transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchBlockCypherTransaction(txid: String) throws -> BlockCypherTransactionResponse? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/txs/\(encodedTXID)") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher Dogecoin transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = object["error"] as? String,
           !errorMessage.isEmpty {
            if errorMessage.lowercased().contains("not found") {
                return nil
            }
            throw DogecoinWalletEngineError.networkFailure("BlockCypher transaction lookup failed: \(errorMessage)")
        }

        return try JSONDecoder().decode(BlockCypherTransactionResponse.self, from: data)
    }

    /// Dogecoin engine operation: Standard script pub key.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func standardScriptPubKey(for address: String) -> Data? {
        guard let decoded = base58CheckDecode(address),
              !decoded.isEmpty else {
            return nil
        }

        let prefix = decoded[0]
        let hash160 = decoded.dropFirst()
        guard hash160.count == 20 else { return nil }

        switch prefix {
        case 0x1e, 0x71: // mainnet/testnet P2PKH
            return Data([0x76, 0xa9, 0x14]) + hash160 + Data([0x88, 0xac])
        case 0x16, 0xc4: // mainnet/testnet P2SH
            return Data([0xa9, 0x14]) + hash160 + Data([0x87])
        default:
            return nil
        }
    }

    /// Dogecoin engine operation: Base58 check decode.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func base58CheckDecode(_ string: String) -> Data? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var indexes: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() {
            indexes[character] = index
        }

        var bytes: [UInt8] = [0]
        for character in string {
            guard let value = indexes[character] else { return nil }

            var carry = value
            for idx in bytes.indices {
                let x = Int(bytes[idx]) * 58 + carry
                bytes[idx] = UInt8(x & 0xff)
                carry = x >> 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        var leadingZeroCount = 0
        for character in string where character == "1" {
            leadingZeroCount += 1
        }

        let decoded = Data(repeating: 0, count: leadingZeroCount) + Data(bytes.reversed())
        guard decoded.count >= 5 else { return nil }

        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let firstHash = SHA256.hash(data: payload)
        let secondHash = SHA256.hash(data: Data(firstHash))
        let computedChecksum = Data(secondHash.prefix(4))
        guard checksum.elementsEqual(computedChecksum) else { return nil }

        return Data(payload)
    }

    /// Dogecoin engine operation: Compute txid.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func computeTXID(fromRawHex rawHex: String) -> String {
        guard let rawData = Data(hexEncoded: rawHex) else {
            return ""
        }
        let firstHash = SHA256.hash(data: rawData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Data(secondHash.reversed()).map { String(format: "%02x", $0) }.joined()
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
            return NSLocalizedString("Enter a valid Dogecoin destination address.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("Enter a valid Dogecoin amount.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("Unable to derive Dogecoin keys from this seed phrase.", comment: "")
        case .walletAddressNotDerivedFromSeed:
            return NSLocalizedString("The imported Dogecoin address does not match the provided seed phrase.", comment: "")
        case .keyDerivationFailed:
            return NSLocalizedString("Failed to derive the Dogecoin private key for signing.", comment: "")
        case .noSpendableUTXOs:
            return NSLocalizedString("No spendable Dogecoin UTXOs were found for this wallet.", comment: "")
        case .insufficientFunds:
            return NSLocalizedString("Insufficient DOGE to cover amount plus network fee.", comment: "")
        case .transactionBuildFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .transactionSignFailed:
            return NSLocalizedString("Failed to sign the Dogecoin transaction.", comment: "")
        case .amountBelowDustThreshold:
            return NSLocalizedString("Amount is below Dogecoin dust threshold.", comment: "")
        case .changeBelowDustThreshold:
            return NSLocalizedString("Calculated change is below dust threshold. Increase amount or consolidate UTXOs.", comment: "")
        case .transactionTooLarge:
            return NSLocalizedString("Dogecoin transaction is too large for standard relay policy.", comment: "")
        case .networkFailure(let message):
            let format = NSLocalizedString("Dogecoin network error: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("Dogecoin broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .preBroadcastValidationFailed(let message):
            let format = NSLocalizedString("Dogecoin pre-broadcast validation failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .postBroadcastVerificationFailed(let message):
            let format = NSLocalizedString("Dogecoin post-broadcast verification failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}
