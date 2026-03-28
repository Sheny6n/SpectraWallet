// MARK: - File Overview
// TON wallet engine for local key derivation, transfer construction, signing, and submission.
//
// Responsibilities:
// - Derives TON wallet addresses from seed material and private keys.
// - Builds, signs, broadcasts, and verifies TON send transactions.

import Foundation
import SwiftProtobuf
import WalletCore

enum TONWalletEngineError: LocalizedError {
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
            return NSLocalizedString("The TON address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The amount is not valid for this TON transfer.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The TON seed phrase is invalid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The TON provider response was invalid.", comment: "")
        case .insufficientBalance:
            return NSLocalizedString("Insufficient TON balance to cover amount and network fee.", comment: "")
        case .signingFailed(let message):
            let format = NSLocalizedString("Failed to sign TON transaction: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .networkError(let message):
            let format = NSLocalizedString("TON network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("TON broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct TONSendPreview: Equatable {
    let estimatedNetworkFeeTON: Double
    let sequenceNumber: UInt32
}

struct TONSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeTON: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum TONWalletEngine {
    private static let endpoint = ChainBackendRegistry.TONRuntimeEndpoints.primaryAPIv2URL
    private static let tonDivisor = Decimal(string: "1000000000")!
    private static let fallbackFeeTON = 0.005
    private static let expirationWindowSeconds: UInt32 = 600

    private struct WalletInformationEnvelope: Decodable {
        let ok: Bool?
        let result: WalletInformationResult?
        let error: String?
    }

    private struct WalletInformationResult: Decodable {
        let balance: String?
        let seqno: UInt32?
    }

    private struct SendBocEnvelope: Decodable {
        let ok: Bool?
        let result: SendBocResult?
        let error: String?
    }

    private struct SendBocResult: Decodable {
        let hash: String?
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .ton,
            derivationPath: "m/44'/607'/\(account)'/0/0"
        )
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidTONAddress(normalized) else {
            throw TONWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .ton)
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidTONAddress(normalized) else {
            throw TONWalletEngineError.invalidAddress
        }
        return normalized
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> TONSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidTONAddress(normalizedOwner),
              AddressValidation.isValidTONAddress(normalizedDestination) else {
            throw TONWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TONWalletEngineError.invalidAmount
        }

        let info = try await fetchWalletInformation(for: normalizedOwner)
        return TONSendPreview(
            estimatedNetworkFeeTON: fallbackFeeTON,
            sequenceNumber: info.seqno ?? 0
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationAccount: UInt32 = 0
    ) async throws -> TONSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidTONAddress(normalizedOwner),
              AddressValidation.isValidTONAddress(normalizedDestination) else {
            throw TONWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TONWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .ton,
            derivationPath: "m/44'/607'/\(derivationAccount)'/0/0"
        )
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw TONWalletEngineError.invalidAddress
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let balanceTON = try await TONBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceTON + 0.000000001 >= amount + preview.estimatedNetworkFeeTON else {
            throw TONWalletEngineError.insufficientBalance
        }

        guard let privateKey = PrivateKey(data: material.privateKeyData) else {
            throw TONWalletEngineError.signingFailed("WalletCore returned an invalid TON private key.")
        }
        let publicKeyData = privateKey.getPublicKeyEd25519().data

        let sendMode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue)
        let amountNano = try scaledUnsignedAmount(amount, decimals: 9)
        let output: TheOpenNetworkSigningOutput = AnySigner.sign(
            input: TheOpenNetworkSigningInput.with {
                $0.privateKey = material.privateKeyData
                $0.publicKey = publicKeyData
                $0.sequenceNumber = preview.sequenceNumber
                $0.expireAt = UInt32(Date().timeIntervalSince1970) + expirationWindowSeconds
                $0.walletVersion = .walletV4R2
                $0.messages = [
                    TheOpenNetworkTransfer.with {
                        $0.dest = normalizedDestination
                        $0.amount = amountNano
                        $0.mode = sendMode
                        $0.bounceable = false
                    }
                ]
            },
            coin: .ton
        )
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned TON signing error code \(output.error.rawValue)." : output.errorMessage
            throw TONWalletEngineError.signingFailed(message)
        }
        guard !output.encoded.isEmpty else {
            throw TONWalletEngineError.signingFailed("WalletCore returned an empty TON payload.")
        }

        let transactionHash = try await submitBOC(output.encoded)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            ownerAddress: normalizedOwner,
            transactionHash: transactionHash
        )
        return TONSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeTON: preview.estimatedNetworkFeeTON,
            verificationStatus: verificationStatus
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else { return .deferred }

        var lastError: Error?
        for attempt in 0 ..< 3 {
            do {
                let (snapshots, diagnostics) = await TONBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
                if snapshots.contains(where: { $0.transactionHash.caseInsensitiveCompare(normalizedHash) == .orderedSame }) {
                    return .verified
                }
                if let error = diagnostics.error, !error.isEmpty {
                    lastError = TONWalletEngineError.networkError(error)
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

    private static func fetchWalletInformation(for address: String) async throws -> WalletInformationResult {
        var components = URLComponents(url: endpoint.appendingPathComponent("getWalletInformation"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "address", value: address)]
        guard let url = components?.url else {
            throw TONWalletEngineError.invalidResponse
        }

        let (data, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TONWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let decoded = try JSONDecoder().decode(WalletInformationEnvelope.self, from: data)
        guard decoded.ok == true, let result = decoded.result else {
            throw TONWalletEngineError.networkError(decoded.error ?? "TON wallet information unavailable.")
        }
        return result
    }

    private static func submitBOC(_ encoded: String) async throws -> String {
        var request = URLRequest(url: endpoint.appendingPathComponent("sendBocReturnHash"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["boc": encoded], options: [])

        let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainWrite)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TONWalletEngineError.broadcastFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let decoded = try JSONDecoder().decode(SendBocEnvelope.self, from: data)
        guard decoded.ok == true else {
            throw TONWalletEngineError.broadcastFailed(decoded.error ?? "TON broadcast rejected.")
        }
        if let hash = decoded.result?.hash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
            return hash
        }
        if let hash = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
            return hash
        }
        throw TONWalletEngineError.invalidResponse
    }

    private static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw TONWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base).rounding(accordingToBehavior: nil)
        if scaled == NSDecimalNumber.notANumber || scaled.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw TONWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard scaled.compare(maxValue) != .orderedDescending else {
            throw TONWalletEngineError.invalidAmount
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
