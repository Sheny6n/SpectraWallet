// MARK: - File Overview
// XRP Ledger engine for address derivation, signing, and transaction serialization.
//
// Responsibilities:
// - Implements XRPL-specific send operation primitives.
// - Surfaces deterministic chain behavior for WalletStore integration.

import Foundation
import WalletCore
import SwiftProtobuf

enum XRPWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The XRP address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The amount is not valid for this XRP transfer.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The XRP seed phrase is invalid.", comment: "")
        case .signingFailed(let message):
            let format = NSLocalizedString("Failed to sign XRP transaction: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .networkError(let message):
            let format = NSLocalizedString("XRP network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("XRP broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct XRPSendPreview: Equatable {
    let estimatedNetworkFeeXRP: Double
    let feeDrops: Int64
    let sequence: Int64
    let lastLedgerSequence: Int64
}

struct XRPSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeXRP: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum XRPWalletEngine {
    private static let xrpJSONRPCEndpoints = ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs

    private struct RPCEnvelope<ResultType: Decodable>: Decodable {
        let result: ResultType?
        let error: String?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case result
            case error
            case errorMessage = "error_message"
        }
    }

    private struct FeeResult: Decodable {
        let drops: FeeDrops?
        struct FeeDrops: Decodable {
            let openLedgerFee: String?
            let minimumFee: String?
            enum CodingKeys: String, CodingKey {
                case openLedgerFee = "open_ledger_fee"
                case minimumFee = "minimum_fee"
            }
        }
    }

    private struct AccountInfoResult: Decodable {
        let accountData: AccountData?
        let ledgerCurrentIndex: Int64?

        enum CodingKeys: String, CodingKey {
            case accountData = "account_data"
            case ledgerCurrentIndex = "ledger_current_index"
        }

        struct AccountData: Decodable {
            let sequence: Int64?
            enum CodingKeys: String, CodingKey {
                case sequence = "Sequence"
            }
        }
    }

    private struct SubmitResult: Decodable {
        let engineResult: String?
        let engineResultMessage: String?
        let txJSON: SubmitTxJSON?

        enum CodingKeys: String, CodingKey {
            case engineResult = "engine_result"
            case engineResultMessage = "engine_result_message"
            case txJSON = "tx_json"
        }

        struct SubmitTxJSON: Decodable {
            let hash: String?
        }
    }

    /// Handles "estimateSendPreview" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> XRPSendPreview {
        guard AddressValidation.isValidXRPAddress(ownerAddress),
              AddressValidation.isValidXRPAddress(destinationAddress) else {
            throw XRPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let feeDrops = try await fetchFeeDrops()
        let accountInfo = try await fetchAccountInfo(address: ownerAddress)
        let sequence = accountInfo.accountData?.sequence ?? 0
        let currentLedger = accountInfo.ledgerCurrentIndex ?? 0
        let lastLedgerSequence = currentLedger > 0 ? currentLedger + 20 : 0

        return XRPSendPreview(
            estimatedNetworkFeeXRP: Double(feeDrops) / 1_000_000.0,
            feeDrops: feeDrops,
            sequence: sequence,
            lastLedgerSequence: lastLedgerSequence
        )
    }

    /// Handles "sendInBackground" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationAccount: UInt32 = 0
    ) async throws -> XRPSendResult {
        guard AddressValidation.isValidXRPAddress(ownerAddress),
              AddressValidation.isValidXRPAddress(destinationAddress) else {
            throw XRPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let amountDrops = Int64((amount * 1_000_000.0).rounded(.towardZero))
        guard amountDrops > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .xrp,
            account: derivationAccount
        )
        guard !material.privateKeyData.isEmpty else {
            throw XRPWalletEngineError.invalidSeedPhrase
        }

        let operation = RippleOperationPayment.with {
            $0.destination = destinationAddress
            $0.amount = amountDrops
        }
        let sequence = UInt32(clamping: preview.sequence)
        let lastLedgerSequence = UInt32(clamping: preview.lastLedgerSequence)
        let input = RippleSigningInput.with {
            $0.fee = preview.feeDrops
            $0.sequence = sequence
            if lastLedgerSequence > 0 {
                $0.lastLedgerSequence = lastLedgerSequence
            }
            $0.account = ownerAddress
            $0.privateKey = material.privateKeyData
            $0.opPayment = operation
        }
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        let txBlobHex = output.encoded.hexString
        guard !txBlobHex.isEmpty else {
            throw XRPWalletEngineError.signingFailed("WalletCore produced an empty transaction payload.")
        }

        let submit = try await submitTransaction(txBlobHex: txBlobHex)
        let resultCode = submit.engineResult ?? ""
        guard resultCode.hasPrefix("tes") else {
            let message = submit.engineResultMessage ?? "Engine result \(resultCode)"
            throw XRPWalletEngineError.broadcastFailed(message)
        }
        let txHash = submit.txJSON?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !txHash.isEmpty else {
            throw XRPWalletEngineError.broadcastFailed("Missing transaction hash from XRP submit response.")
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(transactionHash: txHash)

        return XRPSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeXRP: preview.estimatedNetworkFeeXRP,
            verificationStatus: verificationStatus
        )
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .xrp)
        guard AddressValidation.isValidXRPAddress(material.address) else {
            throw XRPWalletEngineError.invalidAddress
        }
        return material.address
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async throws -> XRPSendResult {
        guard AddressValidation.isValidXRPAddress(ownerAddress),
              AddressValidation.isValidXRPAddress(destinationAddress) else {
            throw XRPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let amountDrops = Int64((amount * 1_000_000.0).rounded(.towardZero))
        guard amountDrops > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .xrp)
        guard !material.privateKeyData.isEmpty else {
            throw XRPWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw XRPWalletEngineError.invalidAddress
        }

        let operation = RippleOperationPayment.with {
            $0.destination = destinationAddress
            $0.amount = amountDrops
        }
        let sequence = UInt32(clamping: preview.sequence)
        let lastLedgerSequence = UInt32(clamping: preview.lastLedgerSequence)
        let input = RippleSigningInput.with {
            $0.fee = preview.feeDrops
            $0.sequence = sequence
            if lastLedgerSequence > 0 {
                $0.lastLedgerSequence = lastLedgerSequence
            }
            $0.account = ownerAddress
            $0.privateKey = material.privateKeyData
            $0.opPayment = operation
        }
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        let txBlobHex = output.encoded.hexString
        guard !txBlobHex.isEmpty else {
            throw XRPWalletEngineError.signingFailed("WalletCore produced an empty transaction payload.")
        }

        let submit = try await submitTransaction(txBlobHex: txBlobHex)
        let resultCode = submit.engineResult ?? ""
        guard resultCode.hasPrefix("tes") else {
            let message = submit.engineResultMessage ?? "Engine result \(resultCode)"
            throw XRPWalletEngineError.broadcastFailed(message)
        }
        let txHash = submit.txJSON?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !txHash.isEmpty else {
            throw XRPWalletEngineError.broadcastFailed("Missing transaction hash from XRP submit response.")
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(transactionHash: txHash)

        return XRPSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeXRP: preview.estimatedNetworkFeeXRP,
            verificationStatus: verificationStatus
        )
    }

    private struct TransactionLookupResult: Decodable {
        let validated: Bool?
        let hash: String?
        let meta: TransactionMeta?

        struct TransactionMeta: Decodable {
            let transactionResult: String?

            enum CodingKeys: String, CodingKey {
                case transactionResult = "TransactionResult"
            }
        }
    }

    private static func verifyBroadcastedTransactionIfAvailable(transactionHash: String) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if let lookup = try await fetchTransactionLookup(transactionHash: transactionHash) {
                    if let transactionResult = lookup.meta?.transactionResult,
                       !transactionResult.hasPrefix("tes") {
                        return .failed("Ledger reported result \(transactionResult).")
                    }
                    if lookup.validated == true || lookup.hash?.caseInsensitiveCompare(transactionHash) == .orderedSame {
                        return .verified
                    }
                }
            } catch {
                lastError = error
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func fetchTransactionLookup(transactionHash: String) async throws -> TransactionLookupResult? {
        let payload: [String: Any] = [
            "method": "tx",
            "params": [[
                "transaction": transactionHash
            ]]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        var lastError: Error?

        for endpoint in xrpJSONRPCEndpoints {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw XRPWalletEngineError.networkError("HTTP \(code)")
                }

                let decoded = try JSONDecoder().decode(RPCEnvelope<TransactionLookupResult>.self, from: data)
                if let result = decoded.result {
                    return result
                }
                let message = decoded.errorMessage ?? decoded.error ?? ""
                if message.localizedCaseInsensitiveContains("notfound") || message.localizedCaseInsensitiveContains("txnnotfound") {
                    return nil
                }
                throw XRPWalletEngineError.networkError(message.isEmpty ? "Unknown XRP RPC error." : message)
            } catch {
                lastError = error
            }
        }

        throw XRPWalletEngineError.networkError(lastError?.localizedDescription ?? "Unknown XRP RPC error.")
    }

    /// Handles "fetchFeeDrops" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func fetchFeeDrops() async throws -> Int64 {
        let payload: [String: Any] = [
            "method": "fee",
            "params": [[:]]
        ]
        let result: FeeResult = try await postRPC(payload: payload)
        let feeString = result.drops?.openLedgerFee ?? result.drops?.minimumFee ?? "12"
        guard let fee = Int64(feeString), fee > 0 else {
            throw XRPWalletEngineError.networkError("Invalid fee response from XRP network.")
        }
        return fee
    }

    /// Handles "fetchAccountInfo" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func fetchAccountInfo(address: String) async throws -> AccountInfoResult {
        let payload: [String: Any] = [
            "method": "account_info",
            "params": [[
                "account": address,
                "ledger_index": "current",
                "strict": true
            ]]
        ]
        let result: AccountInfoResult = try await postRPC(payload: payload)
        return result
    }

    /// Handles "submitTransaction" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private static func submitTransaction(txBlobHex: String) async throws -> SubmitResult {
        let payload: [String: Any] = [
            "method": "submit",
            "params": [[
                "tx_blob": txBlobHex
            ]]
        ]
        let result: SubmitResult = try await postRPC(payload: payload)
        return result
    }

    private static func postRPC<ResultType: Decodable>(payload: [String: Any]) async throws -> ResultType {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        var lastError: Error?

        for endpoint in xrpJSONRPCEndpoints {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainWrite)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw XRPWalletEngineError.networkError("HTTP \(code)")
                }

                let decoded = try JSONDecoder().decode(RPCEnvelope<ResultType>.self, from: data)
                if let result = decoded.result {
                    return result
                }
                let message = decoded.errorMessage ?? decoded.error ?? "Unknown XRP RPC error."
                throw XRPWalletEngineError.networkError(message)
            } catch {
                lastError = error
            }
        }

        throw XRPWalletEngineError.networkError(lastError?.localizedDescription ?? "Unknown XRP RPC error.")
    }

    /// Handles "derivedAddress" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .xrp,
            account: account
        )
        guard AddressValidation.isValidXRPAddress(material.address) else {
            throw XRPWalletEngineError.invalidSeedPhrase
        }
        return material.address
    }
}
