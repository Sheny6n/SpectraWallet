import Foundation
import SwiftProtobuf
import WalletCore

enum ICPWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case insufficientBalance
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The ICP account identifier is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The amount is not valid for this ICP transfer.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The ICP seed phrase is invalid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The ICP provider response was invalid.", comment: "")
        case .insufficientBalance:
            return NSLocalizedString("Insufficient ICP to cover amount and network fee.", comment: "")
        case .signingFailed(let message):
            let format = NSLocalizedString("Failed to sign ICP transaction: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .networkError(let message):
            let format = NSLocalizedString("ICP network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("ICP broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct ICPSendPreview: Equatable {
    let estimatedNetworkFeeICP: Double
    let feeE8s: UInt64
}

struct ICPSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeICP: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum ICPWalletEngine {
    private static let defaultFeeE8s: UInt64 = 10_000
    private static let defaultMemo: UInt64 = 0
    private static let permittedDriftNanos: UInt64 = 60_000_000_000

    static func derivedAddress(for seedPhrase: String, derivationPath: String = "m/44'/223'/0'/0/0") throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .internetComputer,
            derivationPath: derivationPath
        )
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidICPAddress(normalized) else {
            throw ICPWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .internetComputer)
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidICPAddress(normalized) else {
            throw ICPWalletEngineError.invalidAddress
        }
        return normalized
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> ICPSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidICPAddress(normalizedOwner),
              AddressValidation.isValidICPAddress(normalizedDestination) else {
            throw ICPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw ICPWalletEngineError.invalidAmount
        }

        return ICPSendPreview(
            estimatedNetworkFeeICP: Double(defaultFeeE8s) / 100_000_000.0,
            feeE8s: defaultFeeE8s
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/44'/223'/0'/0/0"
    ) async throws -> ICPSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidICPAddress(normalizedOwner),
              AddressValidation.isValidICPAddress(normalizedDestination) else {
            throw ICPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw ICPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let amountE8s = try scaledUnsignedAmount(amount, decimals: 8)
        let balanceICP = try await ICPBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceICP + 0.00000001 >= amount + preview.estimatedNetworkFeeICP else {
            throw ICPWalletEngineError.insufficientBalance
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .internetComputer,
            derivationPath: derivationPath
        )
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw ICPWalletEngineError.invalidAddress
        }

        let signedTransaction = try signTransaction(
            privateKey: material.privateKeyData,
            destinationAddress: normalizedDestination,
            amountE8s: amountE8s
        )
        let hash = try await ICPBalanceService.submitSignedTransaction(signedTransaction.hexEncodedString())
        return ICPSendResult(
            transactionHash: hash,
            estimatedNetworkFeeICP: preview.estimatedNetworkFeeICP,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: normalizedOwner, transactionHash: hash)
        )
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async throws -> ICPSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidICPAddress(normalizedOwner),
              AddressValidation.isValidICPAddress(normalizedDestination) else {
            throw ICPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw ICPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let amountE8s = try scaledUnsignedAmount(amount, decimals: 8)
        let balanceICP = try await ICPBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceICP + 0.00000001 >= amount + preview.estimatedNetworkFeeICP else {
            throw ICPWalletEngineError.insufficientBalance
        }

        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .internetComputer)
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw ICPWalletEngineError.invalidAddress
        }

        let signedTransaction = try signTransaction(
            privateKey: material.privateKeyData,
            destinationAddress: normalizedDestination,
            amountE8s: amountE8s
        )
        let hash = try await ICPBalanceService.submitSignedTransaction(signedTransaction.hexEncodedString())
        return ICPSendResult(
            transactionHash: hash,
            estimatedNetworkFeeICP: preview.estimatedNetworkFeeICP,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: normalizedOwner, transactionHash: hash)
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
        let result = await ICPBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        if result.snapshots.contains(where: { $0.transactionHash.lowercased() == normalizedHash }) {
            return .verified
        }
        if let error = result.diagnostics.error, !error.isEmpty {
            return .failed(error)
        }
        return .deferred
    }

    private static func signTransaction(
        privateKey: Data,
        destinationAddress: String,
        amountE8s: UInt64
    ) throws -> Data {
        var transaction = InternetComputerTransaction()
        transaction.transfer = InternetComputerTransaction.Transfer.with {
            $0.toAccountIdentifier = destinationAddress
            $0.amount = amountE8s
            $0.memo = defaultMemo
            $0.currentTimestampNanos = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
            $0.permittedDrift = permittedDriftNanos
        }

        let input = InternetComputerSigningInput.with {
            $0.privateKey = privateKey
            $0.transaction = transaction
        }

        let output: InternetComputerSigningOutput = AnySigner.sign(input: input, coin: .internetComputer)
        guard output.error == .ok else {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw ICPWalletEngineError.signingFailed(message)
        }
        guard !output.signedTransaction.isEmpty else {
            throw ICPWalletEngineError.signingFailed("WalletCore returned an empty signed ICP transaction.")
        }
        return output.signedTransaction
    }

    private static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw ICPWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base).rounding(accordingToBehavior: nil)
        if scaled == NSDecimalNumber.notANumber || scaled.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw ICPWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard scaled.compare(maxValue) != .orderedDescending else {
            throw ICPWalletEngineError.invalidAmount
        }
        return scaled.uint64Value
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
