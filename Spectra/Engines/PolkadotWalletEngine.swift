import Foundation
import SwiftProtobuf
import WalletCore

enum PolkadotWalletEngineError: LocalizedError {
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
            return NSLocalizedString("The Polkadot address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The amount is not valid for this Polkadot transfer.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The Polkadot seed phrase is invalid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The Polkadot provider response was invalid.", comment: "")
        case .signingFailed(let message):
            let format = NSLocalizedString("Failed to sign Polkadot transaction: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .networkError(let message):
            let format = NSLocalizedString("Polkadot network request failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            let format = NSLocalizedString("Polkadot broadcast failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct PolkadotSendPreview: Equatable {
    let estimatedNetworkFeeDOT: Double
}

struct PolkadotSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeDOT: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum PolkadotWalletEngine {
    private static let dotDivisor = Decimal(string: "10000000000")!

    static func derivedAddress(for seedPhrase: String, derivationPath: String = "m/44'/354'/0'") throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .polkadot,
            derivationPath: derivationPath
        )
        let normalized = material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidPolkadotAddress(normalized) else {
            throw PolkadotWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func estimateSendPreview(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/44'/354'/0'"
    ) async throws -> PolkadotSendPreview {
        let prepared = try await prepareSignedExtrinsic(
            seedPhrase: seedPhrase,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            derivationPath: derivationPath
        )
        let fee = try await fetchFeeEstimate(for: prepared.encodedExtrinsicHex)
        return PolkadotSendPreview(estimatedNetworkFeeDOT: fee)
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/44'/354'/0'"
    ) async throws -> PolkadotSendResult {
        let prepared = try await prepareSignedExtrinsic(
            seedPhrase: seedPhrase,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            derivationPath: derivationPath
        )
        let fee = (try? await fetchFeeEstimate(for: prepared.encodedExtrinsicHex)) ?? 0
        let transactionHash = try await broadcastExtrinsic(prepared.encodedExtrinsicHex)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            ownerAddress: ownerAddress,
            transactionHash: transactionHash
        )
        return PolkadotSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeDOT: fee,
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
            let (snapshots, diagnostics) = await PolkadotBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 40)
            if snapshots.contains(where: { $0.transactionHash.caseInsensitiveCompare(normalizedHash) == .orderedSame }) {
                return .verified
            }
            if let error = diagnostics.error, !error.isEmpty {
                lastError = PolkadotWalletEngineError.networkError(error)
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private struct PreparedExtrinsic {
        let encodedExtrinsicHex: String
    }

    private struct TransactionMaterial: Decodable {
        struct At: Decodable {
            let hash: String
            let height: String
        }

        let at: At
        let genesisHash: String
        let specVersion: String
        let txVersion: String
    }

    private struct SidecarBalanceInfo: Decodable {
        let nonce: Int?
    }

    private struct FeeEstimateEnvelope: Decodable {
        let estimatedFee: String?
        let partialFee: String?
        let inclusionFee: FeeComponent?

        struct FeeComponent: Decodable {
            let baseFee: String?
            let lenFee: String?
            let adjustedWeightFee: String?
        }
    }

    private struct BroadcastEnvelope: Decodable {
        let hash: String?
        let txHash: String?
    }

    private static func prepareSignedExtrinsic(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String
    ) async throws -> PreparedExtrinsic {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidPolkadotAddress(normalizedOwner),
              AddressValidation.isValidPolkadotAddress(normalizedDestination) else {
            throw PolkadotWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw PolkadotWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .polkadot,
            derivationPath: derivationPath
        )
        guard !material.privateKeyData.isEmpty else {
            throw PolkadotWalletEngineError.invalidSeedPhrase
        }
        guard material.address == normalizedOwner else {
            throw PolkadotWalletEngineError.invalidAddress
        }

        let txMaterial = try await fetchTransactionMaterial()
        let nonce = try await fetchNonce(for: normalizedOwner)
        let blockNumber = UInt64(txMaterial.at.height) ?? 0
        guard let privateKey = PrivateKey(data: material.privateKeyData) else {
            throw PolkadotWalletEngineError.invalidSeedPhrase
        }
        let value = try planckData(fromDOT: amount)

        let input = PolkadotSigningInput.with {
            $0.genesisHash = Data(hexString: txMaterial.genesisHash) ?? Data()
            $0.blockHash = Data(hexString: txMaterial.at.hash) ?? Data()
            $0.nonce = UInt64(max(nonce, 0))
            $0.specVersion = UInt32(txMaterial.specVersion) ?? 0
            $0.network = CoinType.polkadot.ss58Prefix
            $0.transactionVersion = UInt32(txMaterial.txVersion) ?? 0
            $0.privateKey = privateKey.data
            $0.era = PolkadotEra.with {
                $0.blockNumber = blockNumber
                $0.period = 64
            }
            $0.balanceCall.transfer = PolkadotBalance.Transfer.with {
                $0.toAddress = normalizedDestination
                $0.value = value
            }
        }

        let output: PolkadotSigningOutput = AnySigner.sign(input: input, coin: .polkadot)
        guard output.error == .ok else {
            let message = output.errorMessage.isEmpty ? String(describing: output.error) : output.errorMessage
            throw PolkadotWalletEngineError.signingFailed(message)
        }
        guard !output.encoded.isEmpty else {
            throw PolkadotWalletEngineError.signingFailed("WalletCore returned an empty extrinsic.")
        }

        return PreparedExtrinsic(encodedExtrinsicHex: "0x" + output.encoded.hexString)
    }

    private static func fetchTransactionMaterial() async throws -> TransactionMaterial {
        var lastError: Error?
        for endpoint in PolkadotBalanceService.sidecarEndpointCatalog() {
            guard let url = URL(string: "\(endpoint)/transaction/material") else { continue }
            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                return try JSONDecoder().decode(TransactionMaterial.self, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PolkadotWalletEngineError.invalidResponse
    }

    private static func fetchNonce(for address: String) async throws -> Int {
        var lastError: Error?
        for endpoint in PolkadotBalanceService.sidecarEndpointCatalog() {
            guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(endpoint)/accounts/\(encoded)/balance-info") else { continue }
            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let info = try JSONDecoder().decode(SidecarBalanceInfo.self, from: data)
                return info.nonce ?? 0
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PolkadotWalletEngineError.invalidResponse
    }

    private static func fetchFeeEstimate(for extrinsicHex: String) async throws -> Double {
        let payload = try JSONSerialization.data(withJSONObject: ["tx": extrinsicHex], options: [])
        var lastError: Error?
        for endpoint in PolkadotBalanceService.sidecarEndpointCatalog() {
            guard let url = URL(string: "\(endpoint)/transaction/fee-estimate") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let envelope = try JSONDecoder().decode(FeeEstimateEnvelope.self, from: data)
                if let feeText = envelope.estimatedFee ?? envelope.partialFee,
                   let fee = Decimal(string: feeText) {
                    return decimalToDouble(fee / dotDivisor)
                }
                if let inclusion = envelope.inclusionFee {
                    let base = Decimal(string: inclusion.baseFee ?? "0") ?? 0
                    let len = Decimal(string: inclusion.lenFee ?? "0") ?? 0
                    let adjusted = Decimal(string: inclusion.adjustedWeightFee ?? "0") ?? 0
                    let total = base + len + adjusted
                    if total > 0 {
                        return decimalToDouble(total / dotDivisor)
                    }
                }
                throw PolkadotWalletEngineError.invalidResponse
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PolkadotWalletEngineError.invalidResponse
    }

    private static func broadcastExtrinsic(_ extrinsicHex: String) async throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["tx": extrinsicHex], options: [])
        var lastError: Error?
        for endpoint in PolkadotBalanceService.sidecarEndpointCatalog() {
            guard let url = URL(string: "\(endpoint)/transaction") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                if let envelope = try? JSONDecoder().decode(BroadcastEnvelope.self, from: data),
                   let hash = envelope.hash ?? envelope.txHash,
                   !hash.isEmpty {
                    return hash
                }
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let hash = object["hash"] as? String ?? object["txHash"] as? String,
                   !hash.isEmpty {
                    return hash
                }
                throw PolkadotWalletEngineError.invalidResponse
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PolkadotWalletEngineError.broadcastFailed("All Polkadot broadcast endpoints failed.")
    }

    private static func planckData(fromDOT amount: Double) throws -> Data {
        guard amount > 0 else {
            throw PolkadotWalletEngineError.invalidAmount
        }
        let amountText = String(format: "%.10f", amount)
        guard let dot = Decimal(string: amountText) else {
            throw PolkadotWalletEngineError.invalidAmount
        }
        let planckDecimal = dot * dotDivisor
        let rounded = NSDecimalNumber(decimal: planckDecimal).rounding(accordingToBehavior: nil)
        guard let integer = UInt64(exactly: rounded) else {
            throw PolkadotWalletEngineError.invalidAmount
        }
        return littleEndianUnsignedIntegerData(integer)
    }

    private static func littleEndianUnsignedIntegerData(_ value: UInt64) -> Data {
        if value == 0 { return Data([0]) }
        var little = value.littleEndian
        let data = withUnsafeBytes(of: &little) { Data($0) }
        if let lastNonZero = data.lastIndex(where: { $0 != 0 }) {
            return data.prefix(through: lastNonZero)
        }
        return Data([0])
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
