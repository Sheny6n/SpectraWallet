// MARK: - File Overview
// Cardano-specific signing and address/transaction engine layer consumed by the app state coordinator.
//
// Responsibilities:
// - Implements Cardano derivation and transaction-building entry points.
// - Provides consistent error surfaces for wallet UX and diagnostics.

import Foundation
import WalletCore

enum CardanoWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The Cardano address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The Cardano amount is not valid.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The Cardano seed phrase is invalid.", comment: "")
        case .signingFailed(let message):
            let format = NSLocalizedString("Cardano signing failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .networkError(let message):
            let format = NSLocalizedString("Cardano network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("Cardano broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct CardanoSendPreview: Equatable {
    let estimatedNetworkFeeADA: Double
    let ttlSlot: UInt64
}

struct CardanoSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeADA: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum CardanoWalletEngine {
    private static let koiosBaseURL = ChainBackendRegistry.CardanoRuntimeEndpoints.primaryBaseURL

    private struct RPCAddressUTXO {
        let txHash: String
        let txIndex: UInt64
        let amountLovelace: UInt64
    }

    private struct TipResult {
        let absSlot: UInt64
    }

    /// Handles "derivedAddress" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            derivationPath: "m/1852'/1815'/\(account)'/0/0"
        )
    }

    static func derivedAddress(for seedPhrase: String, derivationPath: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .cardano,
            derivationPath: derivationPath
        )
        guard AddressValidation.isValidCardanoAddress(material.address) else {
            throw CardanoWalletEngineError.invalidSeedPhrase
        }
        return material.address
    }

    /// Handles "estimateSendPreview" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> CardanoSendPreview {
        guard AddressValidation.isValidCardanoAddress(ownerAddress),
              AddressValidation.isValidCardanoAddress(destinationAddress) else {
            throw CardanoWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let tip = try await fetchTip()
        // Conservative ADA fee estimate for basic transfer tx.
        return CardanoSendPreview(
            estimatedNetworkFeeADA: 0.2,
            ttlSlot: tip.absSlot + 7_200
        )
    }

    /// Handles "sendInBackground" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/1852'/1815'/0'/0/0"
    ) async throws -> CardanoSendResult {
        guard AddressValidation.isValidCardanoAddress(ownerAddress),
              AddressValidation.isValidCardanoAddress(destinationAddress) else {
            throw CardanoWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .cardano,
            derivationPath: derivationPath
        )
        guard !material.privateKeyData.isEmpty else {
            throw CardanoWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw CardanoWalletEngineError.invalidAddress
        }

        let amountLovelace = try scaledSignedAmount(amount, decimals: 6)
        guard amountLovelace > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let utxos = try await fetchAddressUTXOs(address: ownerAddress)
        guard !utxos.isEmpty else {
            throw CardanoWalletEngineError.networkError("No spendable UTXOs found for this Cardano address.")
        }

        let tip = try await fetchTip()
        let ttl = tip.absSlot + 7_200

        var input = CardanoSigningInput()
        input.privateKey = [material.privateKeyData]
        input.ttl = ttl

        var transfer = CardanoTransfer()
        transfer.toAddress = destinationAddress
        transfer.changeAddress = ownerAddress
        transfer.amount = UInt64(amountLovelace)
        input.transferMessage = transfer

        input.utxos = utxos.compactMap { item in
            guard let txHashData = Data(hexString: item.txHash) else { return nil }
            var outPoint = CardanoOutPoint()
            outPoint.txHash = txHashData
            outPoint.outputIndex = item.txIndex

            var txInput = CardanoTxInput()
            txInput.outPoint = outPoint
            txInput.address = ownerAddress
            txInput.amount = item.amountLovelace
            return txInput
        }

        if input.utxos.isEmpty {
            throw CardanoWalletEngineError.networkError("Unable to parse Cardano UTXOs for signing.")
        }

        let output: CardanoSigningOutput = AnySigner.sign(input: input, coin: .cardano)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned \(output.error.rawValue)." : output.errorMessage
            throw CardanoWalletEngineError.signingFailed(message)
        }
        guard !output.encoded.isEmpty else {
            throw CardanoWalletEngineError.signingFailed("WalletCore returned empty transaction payload.")
        }

        let txHashData = output.txID
        let txHashHex = txHashData.hexEncodedString()
        guard !txHashHex.isEmpty else {
            throw CardanoWalletEngineError.signingFailed("Missing transaction hash from signing output.")
        }

        try await submitTransactionCBOR(cbor: output.encoded)

        return CardanoSendResult(
            transactionHash: txHashHex,
            estimatedNetworkFeeADA: 0.2,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: ownerAddress, transactionHash: txHashHex)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHash.isEmpty else {
            return .deferred
        }
        let result = await CardanoBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 40)
        if result.snapshots.contains(where: { $0.transactionHash.lowercased() == normalizedHash }) {
            return .verified
        }
        if let error = result.diagnostics.error, !error.isEmpty {
            return .failed(error)
        }
        return .deferred
    }

    /// Handles "fetchTip" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func fetchTip() async throws -> TipResult {
        let url = koiosBaseURL.appendingPathComponent("tip")
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CardanoWalletEngineError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CardanoWalletEngineError.networkError("HTTP \(code)")
        }

        guard let rows = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
              let first = rows.first else {
            throw CardanoWalletEngineError.networkError("Invalid /tip response payload.")
        }

        if let absSlot = first["abs_slot"] as? UInt64 {
            return TipResult(absSlot: absSlot)
        }
        if let absSlotInt = first["abs_slot"] as? Int {
            return TipResult(absSlot: UInt64(max(0, absSlotInt)))
        }
        if let absSlotString = first["abs_slot"] as? String,
           let absSlot = UInt64(absSlotString) {
            return TipResult(absSlot: absSlot)
        }

        throw CardanoWalletEngineError.networkError("Missing abs_slot in /tip response.")
    }

    /// Handles "fetchAddressUTXOs" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func fetchAddressUTXOs(address: String) async throws -> [RPCAddressUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(koiosBaseURL.absoluteString)/address_utxos?_address=eq.\(encodedAddress)") else {
            throw CardanoWalletEngineError.networkError("Invalid Cardano UTXO endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CardanoWalletEngineError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CardanoWalletEngineError.networkError("HTTP \(code)")
        }

        guard let rows = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            throw CardanoWalletEngineError.networkError("Invalid Cardano UTXO response payload.")
        }

        return rows.compactMap { row in
            guard let txHash = row["tx_hash"] as? String,
                  !txHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let txIndex: UInt64 = {
                if let value = row["tx_index"] as? UInt64 { return value }
                if let value = row["tx_index"] as? Int { return UInt64(max(0, value)) }
                if let value = row["tx_index"] as? String, let parsed = UInt64(value) { return parsed }
                return 0
            }()

            let lovelace: UInt64? = {
                if let value = row["value"] as? UInt64 { return value }
                if let value = row["value"] as? Int { return UInt64(max(0, value)) }
                if let value = row["value"] as? String { return UInt64(value) }
                return nil
            }()

            guard let amount = lovelace, amount > 0 else { return nil }
            return RPCAddressUTXO(txHash: txHash, txIndex: txIndex, amountLovelace: amount)
        }
    }

    /// Handles "submitTransactionCBOR" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func submitTransactionCBOR(cbor: Data) async throws {
        let url = koiosBaseURL.appendingPathComponent("submittx")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/cbor", forHTTPHeaderField: "Content-Type")
        request.httpBody = cbor

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CardanoWalletEngineError.broadcastFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CardanoWalletEngineError.broadcastFailed("Missing HTTP response from Cardano submit endpoint.")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CardanoWalletEngineError.broadcastFailed("HTTP \(http.statusCode) \(body)")
        }
    }

    /// Handles "scaledSignedAmount" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func scaledSignedAmount(_ amount: Double, decimals: Int) throws -> Int64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        guard rounded != NSDecimalNumber.notANumber,
              rounded.compare(NSDecimalNumber.zero) == .orderedDescending else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let maxValue = NSDecimalNumber(value: Int64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let value = rounded.int64Value
        guard value > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }
        return value
    }

    /// Handles "decimalPowerOfTen" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }
}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }

    /// Handles "hexEncodedString" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
