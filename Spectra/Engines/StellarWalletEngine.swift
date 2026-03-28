// MARK: - File Overview
// Stellar wallet engine for key derivation, payment assembly, signing, and submission.
//
// Responsibilities:
// - Derives Stellar keypairs and addresses from local wallet secrets.
// - Builds, signs, broadcasts, and verifies Stellar payment transactions.

import Foundation
import WalletCore
import SwiftProtobuf

enum StellarWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The Stellar address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The amount is not valid for this Stellar transfer.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The Stellar seed phrase is invalid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The Stellar provider response was invalid.", comment: "")
        case .signingFailed(let message):
            let format = NSLocalizedString("Failed to sign Stellar transaction: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .networkError(let message):
            let format = NSLocalizedString("Stellar network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("Stellar broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct StellarSendPreview: Equatable {
    let estimatedNetworkFeeXLM: Double
    let feeStroops: Int64
    let sequence: Int64
}

struct StellarSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeXLM: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum StellarWalletEngine {
    static func derivedAddress(for seedPhrase: String, derivationPath: String = "m/44'/148'/0'") throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .stellar,
            derivationPath: derivationPath
        )
        let normalized = material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidStellarAddress(normalized) else {
            throw StellarWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .stellar)
        let normalized = material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidStellarAddress(normalized) else {
            throw StellarWalletEngineError.invalidAddress
        }
        return normalized
    }

    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> StellarSendPreview {
        guard AddressValidation.isValidStellarAddress(ownerAddress),
              AddressValidation.isValidStellarAddress(destinationAddress) else {
            throw StellarWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw StellarWalletEngineError.invalidAmount
        }

        let feeStroops = try await StellarBalanceService.fetchBaseFeeStroops()
        let sequence = try await StellarBalanceService.fetchSequence(for: ownerAddress)
        return StellarSendPreview(
            estimatedNetworkFeeXLM: Double(feeStroops) / 10_000_000.0,
            feeStroops: feeStroops,
            sequence: sequence
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/44'/148'/0'"
    ) async throws -> StellarSendResult {
        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .stellar,
            derivationPath: derivationPath
        )
        guard !material.privateKeyData.isEmpty else {
            throw StellarWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw StellarWalletEngineError.invalidAddress
        }
        let envelope = try signEnvelope(
            privateKey: material.privateKeyData,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            feeStroops: preview.feeStroops,
            sequence: preview.sequence
        )
        let hash = try await StellarBalanceService.submitTransaction(xdrEnvelope: envelope)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(hash: hash)
        return StellarSendResult(
            transactionHash: hash,
            estimatedNetworkFeeXLM: preview.estimatedNetworkFeeXLM,
            verificationStatus: verificationStatus
        )
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async throws -> StellarSendResult {
        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .stellar)
        guard material.address == ownerAddress else {
            throw StellarWalletEngineError.invalidAddress
        }
        let envelope = try signEnvelope(
            privateKey: material.privateKeyData,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            feeStroops: preview.feeStroops,
            sequence: preview.sequence
        )
        let hash = try await StellarBalanceService.submitTransaction(xdrEnvelope: envelope)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(hash: hash)
        return StellarSendResult(
            transactionHash: hash,
            estimatedNetworkFeeXLM: preview.estimatedNetworkFeeXLM,
            verificationStatus: verificationStatus
        )
    }

    private struct TransactionLookupResponse: Decodable {
        let successful: Bool?
        let hash: String?
    }

    private static func verifyBroadcastedTransactionIfAvailable(hash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else { return .deferred }

        var lastError: Error?
        for attempt in 0 ..< 3 {
            for endpoint in StellarBalanceService.endpointCatalog() {
                do {
                    guard let encoded = normalizedHash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let url = URL(string: "\(endpoint)/transactions/\(encoded)") else { continue }
                    let (data, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
                    guard let http = response as? HTTPURLResponse else {
                        throw StellarWalletEngineError.invalidResponse
                    }
                    if http.statusCode == 404 {
                        continue
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw StellarWalletEngineError.networkError("HTTP \(http.statusCode)")
                    }
                    let lookup = try JSONDecoder().decode(TransactionLookupResponse.self, from: data)
                    if lookup.successful == false {
                        return .failed("Stellar Horizon reported unsuccessful transaction execution.")
                    }
                    if lookup.hash?.caseInsensitiveCompare(normalizedHash) == .orderedSame || lookup.successful == true {
                        return .verified
                    }
                } catch {
                    lastError = error
                }
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func signEnvelope(
        privateKey: Data,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        feeStroops: Int64,
        sequence: Int64
    ) throws -> String {
        guard AddressValidation.isValidStellarAddress(ownerAddress),
              AddressValidation.isValidStellarAddress(destinationAddress) else {
            throw StellarWalletEngineError.invalidAddress
        }
        let amountStroops = try StellarBalanceService.stroops(fromXLM: amount)

        let input = StellarSigningInput.with {
            $0.account = ownerAddress
            $0.privateKey = privateKey
            $0.fee = Int32(clamping: feeStroops)
            $0.sequence = sequence
            $0.passphrase = StellarPassphrase.stellar.description
            $0.opPayment = StellarOperationPayment.with {
                $0.destination = destinationAddress
                $0.amount = amountStroops
            }
        }
        let output: StellarSigningOutput = AnySigner.sign(input: input, coin: .stellar)
        let signedEnvelope = output.signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signedEnvelope.isEmpty else {
            let message = output.errorMessage.isEmpty ? "WalletCore returned an empty Stellar envelope." : output.errorMessage
            throw StellarWalletEngineError.signingFailed(message)
        }
        return signedEnvelope
    }
}
