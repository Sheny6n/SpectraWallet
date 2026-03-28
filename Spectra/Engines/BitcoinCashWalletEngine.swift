// MARK: - File Overview
// Bitcoin Cash transaction/signing engine built on WalletCore and Blockchair UTXO data.
//
// Responsibilities:
// - Derives BCH addresses from seed material.
// - Estimates and signs BCH transactions, then broadcasts them.

import Foundation
import WalletCore

enum BitcoinCashWalletEngineError: LocalizedError {
    case invalidSeedPhrase
    case invalidAddress
    case signingFailed(String)
    case insufficientFunds
    case invalidUTXO
    case sourceAddressDoesNotMatchSeed
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSeedPhrase:
            return NSLocalizedString("The Bitcoin Cash seed phrase is invalid.", comment: "")
        case .invalidAddress:
            return NSLocalizedString("The Bitcoin Cash destination address is invalid.", comment: "")
        case .signingFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .insufficientFunds:
            return NSLocalizedString("Insufficient Bitcoin Cash balance for amount plus network fee.", comment: "")
        case .invalidUTXO:
            return NSLocalizedString("Received invalid Bitcoin Cash UTXO data.", comment: "")
        case .sourceAddressDoesNotMatchSeed:
            return NSLocalizedString("The source Bitcoin Cash address does not match the provided seed phrase.", comment: "")
        case .broadcastFailed(let message):
            return NSLocalizedString(message, comment: "")
        }
    }
}

enum BitcoinCashWalletEngine {
    private static let satoshisPerBCH: Double = 100_000_000
    private static let defaultFeeRateSatVb: UInt64 = 1
    private static let minimumFeeSatoshis: UInt64 = 1_000
    private static let blockchairPushURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairPushURL
    private static let blockchairTransactionURLPrefix = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairTransactionURLPrefix
    private static let defaultDerivationPath = "m/44'/145'/0'/0/0"

    struct SendOptions {
        let maxInputCount: Int?
        let enableRBF: Bool
    }

    struct SendResult {
        let transactionHash: String
        let rawTransactionHex: String
        let verificationStatus: SendBroadcastVerificationStatus
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            derivationPath: defaultDerivationPath
                .replacingOccurrences(of: "/0'/0/0", with: "/\(account)'/0/0")
        )
    }

    static func derivedAddress(for seedPhrase: String, derivationPath: String) throws -> String {
        let normalized = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let words = BitcoinWalletEngine.normalizedMnemonicWords(from: normalized)
        guard !words.isEmpty else { throw BitcoinCashWalletEngineError.invalidSeedPhrase }
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalized,
            coin: .bitcoinCash,
            derivationPath: derivationPath
        )
        return material.address
    }

    static func estimateSendPreview(
        sourceAddress: String,
        maxInputCount: Int? = nil
    ) async throws -> BitcoinSendPreview {
        let fetched = try await BitcoinCashBalanceService.fetchUTXOs(for: sourceAddress)
        let utxos = limitedUTXOs(from: fetched, maxInputCount: maxInputCount)
        let totalInputSatoshis = utxos.reduce(UInt64(0)) { $0 + $1.value }
        let estimatedBytes = UInt64(10 + (148 * max(1, utxos.count)) + 68)
        let estimatedFee = max(minimumFeeSatoshis, UInt64(Double(estimatedBytes) * Double(defaultFeeRateSatVb)))
        let spendable = totalInputSatoshis > estimatedFee ? totalInputSatoshis - estimatedFee : 0
        guard spendable > 0 else {
            throw BitcoinCashWalletEngineError.insufficientFunds
        }
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: defaultFeeRateSatVb,
            estimatedNetworkFeeBTC: Double(estimatedFee) / satoshisPerBCH
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        sourceAddress: String,
        to destinationAddress: String,
        amountBCH: Double,
        options: SendOptions? = nil,
        derivationPath: String = "m/44'/145'/0'/0/0"
    ) async throws -> SendResult {
        let effectiveOptions = options ?? SendOptions(maxInputCount: nil, enableRBF: false)
        guard AddressValidation.isValidBitcoinCashAddress(destinationAddress) else {
            throw BitcoinCashWalletEngineError.invalidAddress
        }

        let normalizedSeed = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let normalizedDerivationPath = DerivationPathParser.normalize(
            derivationPath,
            fallback: defaultDerivationPath
        )
        let sourceMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .bitcoinCash,
            derivationPath: normalizedDerivationPath
        )
        let normalizedSourceAddress = sourceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceMaterial.address.caseInsensitiveCompare(normalizedSourceAddress) == .orderedSame else {
            throw BitcoinCashWalletEngineError.sourceAddressDoesNotMatchSeed
        }
        let changePath = changeDerivationPath(for: normalizedDerivationPath)
        let changeMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .bitcoinCash,
            derivationPath: changePath
        )

        let amountSatoshis = UInt64((amountBCH * satoshisPerBCH).rounded())
        guard amountSatoshis > 0 else {
            throw BitcoinCashWalletEngineError.invalidUTXO
        }

        let fetchedUTXOs = try await BitcoinCashBalanceService.fetchUTXOs(for: sourceAddress)
        guard !fetchedUTXOs.isEmpty else {
            throw BitcoinCashWalletEngineError.insufficientFunds
        }

        let selectedUTXOs = try selectUTXOs(
            from: fetchedUTXOs,
            sendAmountSatoshis: amountSatoshis,
            feeRateSatVb: defaultFeeRateSatVb,
            maxInputCount: effectiveOptions.maxInputCount
        )

        let sourceScript = try sourceScript(for: sourceAddress)

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x41
        signingInput.amount = Int64(amountSatoshis)
        signingInput.byteFee = Int64(defaultFeeRateSatVb)
        signingInput.toAddress = destinationAddress
        signingInput.changeAddress = changeMaterial.address
        signingInput.coinType = CoinType.bitcoinCash.rawValue
        signingInput.privateKey = [sourceMaterial.privateKeyData]
        signingInput.utxo = try selectedUTXOs.map {
            try walletCoreUnspentTransaction(
                from: $0,
                sourceScript: sourceScript,
                sequence: effectiveOptions.enableRBF ? 0xFFFFFFFD : UInt32.max
            )
        }

        let output: BitcoinSigningOutput = AnySigner.sign(input: signingInput, coin: .bitcoinCash)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            let message = output.errorMessage.isEmpty ? "Failed to sign Bitcoin Cash transaction." : output.errorMessage
            throw BitcoinCashWalletEngineError.signingFailed(message)
        }

        let rawHex = output.encoded.map { String(format: "%02x", $0) }.joined()
        let txid = try await broadcast(rawTransactionHex: rawHex)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid)
        return SendResult(
            transactionHash: txid,
            rawTransactionHex: rawHex,
            verificationStatus: verificationStatus
        )
    }

    private static func limitedUTXOs(from utxos: [BitcoinCashUTXO], maxInputCount: Int?) -> [BitcoinCashUTXO] {
        guard let maxInputCount, maxInputCount > 0 else { return utxos }
        return Array(utxos.sorted(by: { $0.value > $1.value }).prefix(maxInputCount))
    }

    private static func walletCoreUnspentTransaction(
        from utxo: BitcoinCashUTXO,
        sourceScript: Data,
        sequence: UInt32
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.txid), txHashData.count == 32 else {
            throw BitcoinCashWalletEngineError.invalidUTXO
        }

        var outPoint = BitcoinOutPoint()
        outPoint.hash = Data(txHashData.reversed())
        outPoint.index = UInt32(utxo.vout)
        outPoint.sequence = sequence

        var unspent = BitcoinUnspentTransaction()
        unspent.amount = Int64(utxo.value)
        unspent.script = sourceScript
        unspent.outPoint = outPoint
        return unspent
    }

    private static func selectUTXOs(
        from utxos: [BitcoinCashUTXO],
        sendAmountSatoshis: UInt64,
        feeRateSatVb: UInt64,
        maxInputCount: Int?
    ) throws -> [BitcoinCashUTXO] {
        let sorted = utxos.sorted(by: { $0.value > $1.value })
        let cap = maxInputCount.map { max(1, $0) } ?? sorted.count
        var selected: [BitcoinCashUTXO] = []
        var runningTotal: UInt64 = 0

        for utxo in sorted {
            if selected.count >= cap { break }
            selected.append(utxo)
            runningTotal += utxo.value
            let estimatedBytes = UInt64(10 + (148 * selected.count) + 68)
            let estimatedFee = max(minimumFeeSatoshis, UInt64(Double(estimatedBytes) * Double(feeRateSatVb)))
            if runningTotal >= sendAmountSatoshis + estimatedFee {
                return selected
            }
        }

        throw BitcoinCashWalletEngineError.insufficientFunds
    }

    private static func sourceScript(for address: String) throws -> Data {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = BitcoinScript.lockScriptForAddress(address: trimmed, coin: .bitcoinCash)
        guard !script.data.isEmpty else {
            throw BitcoinCashWalletEngineError.invalidAddress
        }
        return script.data
    }

    private static func broadcast(rawTransactionHex: String) async throws -> String {
        guard let url = URL(string: blockchairPushURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = "data=\(rawTransactionHex)".data(using: .utf8)

        let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainWrite)

        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BitcoinCashWalletEngineError.broadcastFailed("Bitcoin Cash broadcast failed.")
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataValue = jsonObject["data"] as? [String: Any],
           let transactionHash = dataValue["transaction_hash"] as? String,
           !transactionHash.isEmpty {
            return transactionHash
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataValue = jsonObject["data"] as? String,
           !dataValue.isEmpty {
            return dataValue
        }

        throw BitcoinCashWalletEngineError.broadcastFailed("Bitcoin Cash broadcast returned an empty transaction hash.")
    }

    private static func verifyBroadcastedTransactionIfAvailable(txid: String) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if try await verifyPresenceOnlyIfAvailable(txid: txid) {
                    return .verified
                }
            } catch {
                lastError = error
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func verifyPresenceOnlyIfAvailable(txid: String) async throws -> Bool {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockchairTransactionURLPrefix)\(encoded)") else {
            throw URLError(.badURL)
        }

        let (_, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw BitcoinCashWalletEngineError.broadcastFailed("Invalid Bitcoin Cash verification response.")
        }
        if (200 ..< 300).contains(http.statusCode) {
            return true
        }
        if http.statusCode == 404 {
            return false
        }
        throw BitcoinCashWalletEngineError.broadcastFailed("Bitcoin Cash verification failed with status \(http.statusCode).")
    }

    private static func changeDerivationPath(for sourceDerivationPath: String) -> String {
        switch sourceDerivationPath {
        case "m/0":
            return "m/1"
        default:
            return DerivationPathParser.replacingLastTwoSegments(
                in: sourceDerivationPath,
                branch: UInt32(WalletDerivationBranch.change.rawValue),
                index: 0,
                fallback: "m/44'/145'/0'/1/0"
            )
        }
    }
}
