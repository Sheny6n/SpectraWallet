import Foundation
import CryptoKit
import WalletCore

enum TronWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case unsupportedTokenContract
    case createTransactionFailed(String)
    case signFailed(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Tron")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Tron")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Tron")
        case .unsupportedTokenContract:
            return NSLocalizedString("Only official USDT (TRC-20) on Tron is supported.", comment: "")
        case .createTransactionFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .signFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .broadcastFailed(let message):
            return NSLocalizedString(message, comment: "")
        }
    }
}

struct TronSendPreview: Equatable {
    let estimatedNetworkFeeTRX: Double
    let feeLimitSun: Int64
    let simulationUsed: Bool
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct TronSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeTRX: Double
    let signedTransactionJSON: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum TronWalletEngine {
    private static let tronGridBaseURLs = ChainBackendRegistry.TronRuntimeEndpoints.tronGridBroadcastBaseURLs
    private static let endpointReliabilityNamespace = "tron.trongrid"
    private static let usdtDecimals: Int64 = 6

    private static func isSupportedUSDTContract(_ contractAddress: String) -> Bool {
        contractAddress.caseInsensitiveCompare(TronBalanceService.usdtTronContract) == .orderedSame
    }
    private static let defaultTRXFeeTRX = 1.0
    private static let defaultTRC20FeeTRX = 30.0
    private static let defaultEnergyPriceSun = 420.0
    private static let defaultBandwidthFeeTRX = 0.30

    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        symbol: String,
        amount: Double,
        contractAddress: String?
    ) async throws -> TronSendPreview {
        guard AddressValidation.isValidTronAddress(ownerAddress),
              AddressValidation.isValidTronAddress(destinationAddress) else {
            throw TronWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        if symbol == "TRX" {
            let balances = try await TronBalanceService.fetchBalances(for: ownerAddress)
            let maxSendable = max(0, balances.trxBalance - defaultTRXFeeTRX)
            return TronSendPreview(
                estimatedNetworkFeeTRX: defaultTRXFeeTRX,
                feeLimitSun: 0,
                simulationUsed: false,
                spendableBalance: maxSendable,
                feeRateDescription: nil,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: maxSendable
            )
        }

        guard symbol == "USDT", let contractAddress else {
            throw TronWalletEngineError.invalidAmount
        }
        guard isSupportedUSDTContract(contractAddress) else {
            throw TronWalletEngineError.unsupportedTokenContract
        }

        let amountRaw = try scaledSignedAmount(amount, decimals: Int(usdtDecimals))
        guard amountRaw > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let parameter = try makeTRC20TransferParameter(to: destinationAddress, amountRaw: amountRaw)
        let simulation = try await simulateTRC20Transfer(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter
        )

        let estimatedFeeTRX: Double
        if let usedEnergy = simulation.energyUsed {
            let energyFeeTRX = (Double(usedEnergy) * defaultEnergyPriceSun) / 1_000_000.0
            estimatedFeeTRX = max(defaultBandwidthFeeTRX, energyFeeTRX + defaultBandwidthFeeTRX)
        } else {
            estimatedFeeTRX = defaultTRC20FeeTRX
        }

        let balances = try await TronBalanceService.fetchBalances(for: ownerAddress)
        let tokenBalance = balances.tokenBalances.first(where: { $0.symbol == symbol })?.balance ?? 0
        return TronSendPreview(
            estimatedNetworkFeeTRX: estimatedFeeTRX,
            feeLimitSun: simulation.feeLimitSun,
            simulationUsed: simulation.energyUsed != nil,
            spendableBalance: tokenBalance,
            feeRateDescription: simulation.energyUsed.map { "\($0) energy" },
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: tokenBalance
        )
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .tron)
        guard AddressValidation.isValidTronAddress(material.address) else {
            throw TronWalletEngineError.invalidAddress
        }
        return material.address
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        symbol: String,
        amount: Double,
        contractAddress: String?,
        derivationAccount: UInt32 = 0
    ) async throws -> TronSendResult {
        guard AddressValidation.isValidTronAddress(ownerAddress),
              AddressValidation.isValidTronAddress(destinationAddress) else {
            throw TronWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .tron,
            account: derivationAccount
        )
        guard !material.privateKeyData.isEmpty else {
            throw TronWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw TronWalletEngineError.invalidAddress
        }

        if symbol == "TRX" {
            let amountSun = try scaledSignedAmount(amount, decimals: 6)
            guard amountSun > 0 else {
                throw TronWalletEngineError.invalidAmount
            }
            let unsignedTx = try await createTRXTransferTransaction(
                ownerAddress: ownerAddress,
                destinationAddress: destinationAddress,
                amountSun: amountSun
            )
            let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
            let txid = try await broadcastSignedTransaction(signedTransaction)
            let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid)
            return TronSendResult(
                transactionHash: txid,
                estimatedNetworkFeeTRX: defaultTRXFeeTRX,
                signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
                verificationStatus: verificationStatus
            )
        }

        guard symbol == "USDT", let contractAddress else {
            throw TronWalletEngineError.invalidAmount
        }
        guard isSupportedUSDTContract(contractAddress) else {
            throw TronWalletEngineError.unsupportedTokenContract
        }

        let amountRaw = try scaledSignedAmount(amount, decimals: Int(usdtDecimals))
        guard amountRaw > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let parameter = try makeTRC20TransferParameter(to: destinationAddress, amountRaw: amountRaw)
        let simulation = try await simulateTRC20Transfer(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter
        )

        let unsignedTx = try await createTRC20TransferTransaction(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter,
            feeLimitSun: simulation.feeLimitSun
        )
        let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
        let txid = try await broadcastSignedTransaction(signedTransaction)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid)

        let estimatedFeeTRX: Double
        if let usedEnergy = simulation.energyUsed {
            let energyFeeTRX = (Double(usedEnergy) * defaultEnergyPriceSun) / 1_000_000.0
            estimatedFeeTRX = max(defaultBandwidthFeeTRX, energyFeeTRX + defaultBandwidthFeeTRX)
        } else {
            estimatedFeeTRX = defaultTRC20FeeTRX
        }

        return TronSendResult(
            transactionHash: txid,
            estimatedNetworkFeeTRX: estimatedFeeTRX,
            signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
            verificationStatus: verificationStatus
        )
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        symbol: String,
        amount: Double,
        contractAddress: String?
    ) async throws -> TronSendResult {
        guard AddressValidation.isValidTronAddress(ownerAddress),
              AddressValidation.isValidTronAddress(destinationAddress) else {
            throw TronWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .tron)
        guard !material.privateKeyData.isEmpty else {
            throw TronWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw TronWalletEngineError.invalidAddress
        }

        if symbol == "TRX" {
            let amountSun = try scaledSignedAmount(amount, decimals: 6)
            guard amountSun > 0 else {
                throw TronWalletEngineError.invalidAmount
            }
            let unsignedTx = try await createTRXTransferTransaction(
                ownerAddress: ownerAddress,
                destinationAddress: destinationAddress,
                amountSun: amountSun
            )
            let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
            let txid = try await broadcastSignedTransaction(signedTransaction)
            let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid)
            return TronSendResult(
                transactionHash: txid,
                estimatedNetworkFeeTRX: defaultTRXFeeTRX,
                signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
                verificationStatus: verificationStatus
            )
        }

        guard symbol == "USDT", let contractAddress else {
            throw TronWalletEngineError.invalidAmount
        }
        guard isSupportedUSDTContract(contractAddress) else {
            throw TronWalletEngineError.unsupportedTokenContract
        }

        let amountRaw = try scaledSignedAmount(amount, decimals: Int(usdtDecimals))
        guard amountRaw > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let parameter = try makeTRC20TransferParameter(to: destinationAddress, amountRaw: amountRaw)
        let simulation = try await simulateTRC20Transfer(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter
        )

        let unsignedTx = try await createTRC20TransferTransaction(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter,
            feeLimitSun: simulation.feeLimitSun
        )
        let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
        let txid = try await broadcastSignedTransaction(signedTransaction)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid)

        let estimatedFeeTRX: Double
        if let usedEnergy = simulation.energyUsed {
            let energyFeeTRX = (Double(usedEnergy) * defaultEnergyPriceSun) / 1_000_000.0
            estimatedFeeTRX = max(defaultBandwidthFeeTRX, energyFeeTRX + defaultBandwidthFeeTRX)
        } else {
            estimatedFeeTRX = defaultTRC20FeeTRX
        }

        return TronSendResult(
            transactionHash: txid,
            estimatedNetworkFeeTRX: estimatedFeeTRX,
            signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionJSON: String,
        expectedTransactionHash: String? = nil
    ) async throws -> TronSendResult {
        guard let data = signedTransactionJSON.data(using: .utf8),
              let signedTransaction = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TronWalletEngineError.broadcastFailed("Invalid signed Tron transaction payload.")
        }
        let txid = try await broadcastSignedTransaction(signedTransaction)
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : txid
        return TronSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeTRX: 0,
            signedTransactionJSON: signedTransactionJSON,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(txid: transactionHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(txid: String) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if try await transactionExists(txid: txid) {
                    return .verified
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

    private static func transactionExists(txid: String) async throws -> Bool {
        var lastError: Error?
        for baseURL in orderedBroadcastBaseURLs() {
            guard let url = URL(string: baseURL + "/walletsolidity/gettransactioninfobyid") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["value": txid], options: [])

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw TronWalletEngineError.broadcastFailed("Tron verification failed with HTTP \(code).")
                }

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw TronWalletEngineError.broadcastFailed("Invalid Tron verification payload.")
                }

                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: true)
                if object.isEmpty {
                    return false
                }
                if let id = object["id"] as? String, !id.isEmpty {
                    return true
                }
                if let receipt = object["receipt"] as? [String: Any], !receipt.isEmpty {
                    return true
                }
                return false
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: false)
            }
        }
        throw lastError ?? TronWalletEngineError.broadcastFailed("Invalid Tron verification payload.")
    }

    private struct TRC20SimulationResult {
        let energyUsed: Int64?
        let feeLimitSun: Int64
    }

    private static func createTRXTransferTransaction(
        ownerAddress: String,
        destinationAddress: String,
        amountSun: Int64
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "owner_address": ownerAddress,
            "to_address": destinationAddress,
            "amount": amountSun,
            "visible": true
        ]
        return try await postJSON(
            path: "/wallet/createtransaction",
            payload: payload,
            profile: .chainWrite,
            expectedKey: "txID",
            errorPrefix: "Tron create transaction failed"
        )
    }

    private static func createTRC20TransferTransaction(
        ownerAddress: String,
        contractAddress: String,
        parameter: String,
        feeLimitSun: Int64
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "owner_address": ownerAddress,
            "contract_address": contractAddress,
            "function_selector": "transfer(address,uint256)",
            "parameter": parameter,
            "fee_limit": feeLimitSun,
            "call_value": 0,
            "visible": true
        ]

        let response = try await postJSON(
            path: "/wallet/triggersmartcontract",
            payload: payload,
            profile: .chainWrite,
            expectedKey: "result",
            errorPrefix: "Tron trigger smart contract failed"
        )

        if let result = response["result"] as? [String: Any],
           let ok = result["result"] as? Bool,
           !ok {
            let message = (result["message"] as? String) ?? "unknown trigger error"
            throw TronWalletEngineError.createTransactionFailed("Tron trigger smart contract failed: \(message)")
        }

        guard let transaction = response["transaction"] as? [String: Any],
              transaction["txID"] as? String != nil else {
            throw TronWalletEngineError.createTransactionFailed("Tron trigger smart contract did not return a transaction payload.")
        }
        return transaction
    }

    private static func simulateTRC20Transfer(
        ownerAddress: String,
        contractAddress: String,
        parameter: String
    ) async throws -> TRC20SimulationResult {
        let payload: [String: Any] = [
            "owner_address": ownerAddress,
            "contract_address": contractAddress,
            "function_selector": "transfer(address,uint256)",
            "parameter": parameter,
            "visible": true
        ]

        let response = try await postJSON(
            path: "/wallet/triggerconstantcontract",
            payload: payload,
            profile: .chainRead,
            expectedKey: "result",
            errorPrefix: "Tron transfer simulation failed"
        )

        var feeLimitSun: Int64 = Int64(defaultTRC20FeeTRX * 1_000_000.0)
        if let energyUsed = (response["energy_used"] as? NSNumber)?.int64Value {
            let estimatedEnergyFeeSun = Int64(Double(energyUsed) * defaultEnergyPriceSun)
            feeLimitSun = max(feeLimitSun, estimatedEnergyFeeSun + 2_000_000)
            return TRC20SimulationResult(energyUsed: energyUsed, feeLimitSun: feeLimitSun)
        }

        if let energyFee = (response["energy_fee"] as? NSNumber)?.int64Value {
            feeLimitSun = max(feeLimitSun, energyFee + 2_000_000)
        }

        return TRC20SimulationResult(energyUsed: nil, feeLimitSun: feeLimitSun)
    }

    private static func signRawTransaction(_ transaction: [String: Any], privateKey: Data) throws -> [String: Any] {
        guard let txID = transaction["txID"] as? String, !txID.isEmpty else {
            throw TronWalletEngineError.signFailed("Unsigned Tron transaction is missing txID.")
        }

        var input = TronSigningInput()
        input.privateKey = privateKey
        input.txID = txID
        let output: TronSigningOutput = AnySigner.sign(input: input, coin: .tron)

        if output.error.rawValue != 0 {
            let message = output.errorMessage.isEmpty ? "WalletCore Tron signer returned error code \(output.error.rawValue)." : output.errorMessage
            throw TronWalletEngineError.signFailed(message)
        }
        guard !output.signature.isEmpty else {
            throw TronWalletEngineError.signFailed("WalletCore Tron signer returned an empty signature.")
        }

        var signed = transaction
        signed["signature"] = [output.signature.hexEncodedString()]
        return signed
    }

    private static func broadcastSignedTransaction(_ signedTransaction: [String: Any]) async throws -> String {
        let response = try await postJSON(
            path: "/wallet/broadcasttransaction",
            payload: signedTransaction,
            profile: .chainWrite,
            expectedKey: "result",
            errorPrefix: "Tron broadcast failed"
        )

        if let success = response["result"] as? Bool, success {
            if let txid = response["txid"] as? String, !txid.isEmpty {
                return txid
            }
            if let txid = signedTransaction["txID"] as? String, !txid.isEmpty {
                return txid
            }
            throw TronWalletEngineError.broadcastFailed("Tron broadcast succeeded but no transaction hash was returned.")
        }

        if let providerMessage = bestProviderMessage(from: response), !providerMessage.isEmpty {
            if classifySendBroadcastFailure(providerMessage) == .alreadyBroadcast {
                if let txid = response["txid"] as? String, !txid.isEmpty {
                    return txid
                }
                if let txid = signedTransaction["txID"] as? String, !txid.isEmpty {
                    return txid
                }
            }
            throw TronWalletEngineError.broadcastFailed("Tron broadcast failed: \(providerMessage)")
        }
        throw TronWalletEngineError.broadcastFailed("Tron broadcast failed with unknown provider response.")
    }

    private static func postJSON(
        path: String,
        payload: [String: Any],
        profile: NetworkRetryProfile,
        expectedKey: String,
        errorPrefix: String
    ) async throws -> [String: Any] {
        var lastError: Error?
        for baseURL in orderedBroadcastBaseURLs() {
            guard let url = URL(string: baseURL + path) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: profile)

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): invalid JSON payload.")
                }

                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if let providerMessage = bestProviderMessage(from: object), !providerMessage.isEmpty {
                        throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): HTTP \(statusCode) (\(providerMessage))")
                    }
                    throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): HTTP \(statusCode)")
                }

                if object[expectedKey] == nil {
                    if let providerMessage = bestProviderMessage(from: object), !providerMessage.isEmpty {
                        throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): \(providerMessage)")
                    }
                    throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): missing expected field \(expectedKey).")
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: true)
                return object
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: false)
            }
        }
        throw lastError ?? TronWalletEngineError.createTransactionFailed("\(errorPrefix): all providers failed.")
    }

    private static func orderedBroadcastBaseURLs() -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: tronGridBaseURLs
        )
    }

    private static func bestProviderMessage(from object: [String: Any]) -> String? {
        if let message = normalizedProviderMessage(object["message"]) {
            return message
        }
        if let error = normalizedProviderMessage(object["Error"]) {
            return error
        }
        if let code = normalizedProviderMessage(object["code"]) {
            return code
        }
        if let result = object["result"] as? [String: Any] {
            if let message = normalizedProviderMessage(result["message"]) {
                return message
            }
            if let code = normalizedProviderMessage(result["code"]) {
                return code
            }
        }
        return nil
    }

    private static func normalizedProviderMessage(_ value: Any?) -> String? {
        guard let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let decoded = decodeHexASCIIIfNeeded(trimmed), !decoded.isEmpty {
                return decoded
            }
            return trimmed
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if JSONSerialization.isValidJSONObject(["v": value]),
           let encoded = try? JSONSerialization.data(withJSONObject: ["v": value], options: []),
           let json = String(data: encoded, encoding: .utf8) {
            return json
        }

        return nil
    }

    private static func encodedSignedTransactionJSON(_ signedTransaction: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(signedTransaction),
              let data = try? JSONSerialization.data(withJSONObject: signedTransaction, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    private static func decodeHexASCIIIfNeeded(_ string: String) -> String? {
        let candidate = string.hasPrefix("0x") ? String(string.dropFirst(2)) : string
        guard candidate.count >= 2, candidate.count % 2 == 0,
              candidate.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        var bytes = Data()
        bytes.reserveCapacity(candidate.count / 2)
        var index = candidate.startIndex
        while index < candidate.endIndex {
            let next = candidate.index(index, offsetBy: 2)
            guard let byte = UInt8(candidate[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }

        guard let decoded = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !decoded.isEmpty,
              decoded.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value != 127 }) else {
            return nil
        }
        return decoded
    }

    private static func makeTRC20TransferParameter(to destinationAddress: String, amountRaw: Int64) throws -> String {
        guard let tronAddressPayload = base58CheckDecode(destinationAddress), tronAddressPayload.count == 21 else {
            throw TronWalletEngineError.invalidAddress
        }
        let evmAddress = tronAddressPayload.dropFirst()
        guard evmAddress.count == 20 else {
            throw TronWalletEngineError.invalidAddress
        }
        let addressSlot = Data(repeating: 0, count: 12) + evmAddress

        var amountBytes = withUnsafeBytes(of: amountRaw.bigEndian, Array.init)
        while amountBytes.first == 0, amountBytes.count > 1 {
            amountBytes.removeFirst()
        }
        if amountBytes.count > 32 {
            throw TronWalletEngineError.invalidAmount
        }
        let amountSlot = Data(repeating: 0, count: 32 - amountBytes.count) + Data(amountBytes)

        return (addressSlot + amountSlot).hexEncodedString()
    }

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

    private static func scaledSignedAmount(_ amount: Double, decimals: Int) throws -> Int64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw TronWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        guard rounded != NSDecimalNumber.notANumber,
              rounded.compare(NSDecimalNumber.zero) == .orderedDescending else {
            throw TronWalletEngineError.invalidAmount
        }

        let maxValue = NSDecimalNumber(value: Int64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw TronWalletEngineError.invalidAmount
        }

        let value = rounded.int64Value
        guard value > 0 else {
            throw TronWalletEngineError.invalidAmount
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

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
