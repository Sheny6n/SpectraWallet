// MARK: - File Overview
// Aptos wallet engine for mnemonic/private-key derivation, transaction building, signing, and broadcast.
//
// Responsibilities:
// - Derives Aptos addresses and signing keys from local wallet secrets.
// - Builds, signs, and submits Aptos transfers while surfacing verification state.

import Foundation
import SwiftProtobuf
import WalletCore

enum AptosWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case insufficientBalance
    case networkError(String)
    case signingFailed(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The Aptos address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The amount is not valid for this Aptos transfer.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The Aptos seed phrase is invalid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The Aptos provider response was invalid.", comment: "")
        case .insufficientBalance:
            return NSLocalizedString("Insufficient APT balance to cover amount and network fee.", comment: "")
        case .networkError(let message):
            let format = NSLocalizedString("Aptos network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .signingFailed(let message):
            let format = NSLocalizedString("Failed to sign Aptos transaction: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("Aptos broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct AptosSendPreview: Equatable {
    let estimatedNetworkFeeAPT: Double
    let maxGasAmount: UInt64
    let gasUnitPriceOctas: UInt64
}

struct AptosSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeAPT: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum AptosWalletEngine {
    private static let endpoint = ChainBackendRegistry.AptosRuntimeEndpoints.primaryRPCURL
    private static let chainID: UInt64 = 1
    private static let defaultMaxGasAmount: UInt64 = 2_000
    private static let expirationWindowSeconds: UInt64 = 600

    private struct GasEstimate: Decodable {
        let gasEstimate: String?

        enum CodingKeys: String, CodingKey {
            case gasEstimate = "gas_estimate"
        }
    }

    private struct AccountSnapshot: Decodable {
        let sequenceNumber: String?

        enum CodingKeys: String, CodingKey {
            case sequenceNumber = "sequence_number"
        }
    }

    private struct SubmitResponse: Decodable {
        let hash: String?
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .aptos,
            derivationPath: "m/44'/637'/\(account)'/0'/0'"
        )
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidAptosAddress(normalized) else {
            throw AptosWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .aptos)
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidAptosAddress(normalized) else {
            throw AptosWalletEngineError.invalidAddress
        }
        return normalized
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> AptosSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidAptosAddress(normalizedOwner),
              AddressValidation.isValidAptosAddress(normalizedDestination) else {
            throw AptosWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw AptosWalletEngineError.invalidAmount
        }

        let gasUnitPrice = try await fetchGasUnitPrice()
        let estimatedFee = Double(defaultMaxGasAmount * gasUnitPrice) / 100_000_000.0
        return AptosSendPreview(
            estimatedNetworkFeeAPT: estimatedFee,
            maxGasAmount: defaultMaxGasAmount,
            gasUnitPriceOctas: gasUnitPrice
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationAccount: UInt32 = 0
    ) async throws -> AptosSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidAptosAddress(normalizedOwner),
              AddressValidation.isValidAptosAddress(normalizedDestination) else {
            throw AptosWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw AptosWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let amountOctas = try scaledUnsignedAmount(amount, decimals: 8)
        let balanceAPT = try await AptosBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceAPT + 0.00000001 >= amount + preview.estimatedNetworkFeeAPT else {
            throw AptosWalletEngineError.insufficientBalance
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .aptos,
            derivationPath: "m/44'/637'/\(derivationAccount)'/0'/0'"
        )
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw AptosWalletEngineError.invalidAddress
        }

        let sequenceNumber = try await fetchSequenceNumber(for: normalizedOwner)
        let expiration = UInt64(Date().timeIntervalSince1970) + expirationWindowSeconds

        let input = AptosSigningInput.with {
            $0.privateKey = material.privateKeyData
            $0.sender = normalizedOwner
            $0.sequenceNumber = Int64(sequenceNumber)
            $0.maxGasAmount = preview.maxGasAmount
            $0.gasUnitPrice = preview.gasUnitPriceOctas
            $0.expirationTimestampSecs = expiration
            $0.chainID = UInt32(chainID)
            $0.transfer = AptosTransferMessage.with {
                $0.to = normalizedDestination
                $0.amount = amountOctas
            }
        }

        let output: AptosSigningOutput = AnySigner.sign(input: input, coin: .aptos)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw AptosWalletEngineError.signingFailed(message)
        }
        guard !output.json.isEmpty else {
            throw AptosWalletEngineError.signingFailed("WalletCore returned empty Aptos transaction JSON.")
        }

        let digest = try await submitTransaction(jsonPayload: output.json)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(transactionHash: digest)
        return AptosSendResult(
            transactionHash: digest,
            estimatedNetworkFeeAPT: preview.estimatedNetworkFeeAPT,
            verificationStatus: verificationStatus
        )
    }

    private struct TransactionLookupResponse: Decodable {
        let hash: String?
        let success: Bool?
        let vmStatus: String?

        enum CodingKeys: String, CodingKey {
            case hash
            case success
            case vmStatus = "vm_status"
        }
    }

    private static func verifyBroadcastedTransactionIfAvailable(transactionHash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else { return .deferred }

        var lastError: Error?
        for attempt in 0 ..< 3 {
            for endpoint in AptosBalanceService.endpointCatalog() {
                do {
                    guard let url = URL(string: endpoint)?.appendingPathComponent("transactions/by_hash/\(normalizedHash)") else {
                        continue
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    let result: TransactionLookupResponse = try await get(request)
                    if result.success == false {
                        return .failed(result.vmStatus ?? "Aptos transaction execution failed.")
                    }
                    if result.hash?.caseInsensitiveCompare(normalizedHash) == .orderedSame || result.success == true {
                        return .verified
                    }
                } catch let error as AptosWalletEngineError {
                    if case .networkError(let message) = error, message.contains("HTTP 404") {
                        continue
                    }
                    lastError = error
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

    private static func fetchGasUnitPrice() async throws -> UInt64 {
        var request = URLRequest(url: endpoint.appendingPathComponent("estimate_gas_price"))
        request.httpMethod = "GET"
        let result: GasEstimate = try await get(request)
        guard let value = result.gasEstimate, let parsed = UInt64(value), parsed > 0 else {
            throw AptosWalletEngineError.invalidResponse
        }
        return parsed
    }

    private static func fetchSequenceNumber(for address: String) async throws -> UInt64 {
        var request = URLRequest(url: endpoint.appendingPathComponent("accounts/\(address)"))
        request.httpMethod = "GET"
        let result: AccountSnapshot = try await get(request)
        guard let value = result.sequenceNumber, let parsed = UInt64(value) else {
            throw AptosWalletEngineError.invalidResponse
        }
        return parsed
    }

    private static func submitTransaction(jsonPayload: String) async throws -> String {
        guard let data = jsonPayload.data(using: .utf8) else {
            throw AptosWalletEngineError.signingFailed("WalletCore returned non-UTF8 Aptos transaction JSON.")
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("transactions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let result: SubmitResponse = try await send(request)
        guard let hash = result.hash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty else {
            throw AptosWalletEngineError.broadcastFailed("Missing Aptos transaction hash from submit response.")
        }
        return hash
    }

    private static func get<ResultType: Decodable>(_ request: URLRequest) async throws -> ResultType {
        do {
            let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw AptosWalletEngineError.networkError("HTTP \(code)")
            }
            return try JSONDecoder().decode(ResultType.self, from: data)
        } catch let error as AptosWalletEngineError {
            throw error
        } catch {
            throw AptosWalletEngineError.networkError(error.localizedDescription)
        }
    }

    private static func send<ResultType: Decodable>(_ request: URLRequest) async throws -> ResultType {
        do {
            let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainWrite)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw AptosWalletEngineError.broadcastFailed("HTTP \(code)")
            }
            return try JSONDecoder().decode(ResultType.self, from: data)
        } catch let error as AptosWalletEngineError {
            throw error
        } catch {
            throw AptosWalletEngineError.broadcastFailed(error.localizedDescription)
        }
    }

    private static func normalizeAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw AptosWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base).rounding(accordingToBehavior: nil)
        if scaled == NSDecimalNumber.notANumber || scaled.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw AptosWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard scaled.compare(maxValue) != .orderedDescending else {
            throw AptosWalletEngineError.invalidAmount
        }
        let value = scaled.uint64Value
        guard value > 0 else {
            throw AptosWalletEngineError.invalidAmount
        }
        return value
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }
}
