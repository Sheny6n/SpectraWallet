import Foundation
import WalletCore

extension DogecoinWalletEngine {
    static func walletCoreSignTransaction(
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

    static func buildWalletCoreSigningInput(
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

    static func walletCoreUnspentTransaction(
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

    static func signWithWalletCore(input: BitcoinSigningInput) throws -> DogecoinWalletCoreSigningResult {
        let output: BitcoinSigningOutput = AnySigner.sign(input: input, coin: .dogecoin)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            throw DogecoinWalletEngineError.transactionSignFailed
        }
        return DogecoinWalletCoreSigningResult(
            encodedTransaction: output.encoded,
            transactionHash: output.transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func buildSpendPlan(
        from utxos: [DogecoinUTXO],
        amountDOGE: Double,
        feeRateDOGEPerKB: Double,
        maxInputCount: Int?
    ) throws -> DogecoinSpendPlan {
        guard amountDOGE >= dustThresholdDOGE else {
            throw DogecoinWalletEngineError.amountBelowDustThreshold
        }

        let targetKoinu = UInt64((amountDOGE * koinuPerDOGE).rounded())
        guard let spendPlan = UTXOSpendPlanner.buildPlan(
            from: utxos,
            targetValue: targetKoinu,
            dustThreshold: feePolicy.dustThreshold,
            maxInputCount: maxInputCount,
            sortBy: {
                if $0.value != $1.value { return $0.value > $1.value }
                if $0.transactionHash != $1.transactionHash { return $0.transactionHash < $1.transactionHash }
                return $0.index < $1.index
            },
            value: \.value,
            feeForLayout: { inputCount, outputCount in
                feePolicy.estimatedFeeBaseUnits(
                    estimatedBytes: UTXOSpendPlanner.estimateTransactionBytes(
                        inputCount: inputCount,
                        outputCount: outputCount
                    ),
                    feeRatePerKB: feeRateDOGEPerKB
                )
            }
        ) else {
            throw DogecoinWalletEngineError.insufficientFunds
        }
        return spendPlan
    }

    static func estimateTransactionBytes(inputCount: Int, outputCount: Int) -> Int {
        UTXOSpendPlanner.estimateTransactionBytes(inputCount: inputCount, outputCount: outputCount)
    }

    static func estimateNetworkFeeDOGE(estimatedBytes: Int, feeRateDOGEPerKB: Double) -> Double {
        Double(
            feePolicy.estimatedFeeBaseUnits(
                estimatedBytes: estimatedBytes,
                feeRatePerKB: feeRateDOGEPerKB
            )
        ) / koinuPerDOGE
    }

    static func broadcastRawTransaction(
        _ rawHex: String,
        networkMode: DogecoinNetworkMode
    ) throws {
        let maxAttempts = 2
        for attempt in 0 ..< maxAttempts {
            do {
                try broadcastRawTransactionViaBlockCypher(rawHex, networkMode: networkMode)
                return
            } catch {
                let errorDescription = error.localizedDescription
                if isAlreadyBroadcastedError(errorDescription) {
                    return
                }

                let shouldRetry = attempt < maxAttempts - 1 && isRetryableBroadcastError(errorDescription)
                if shouldRetry {
                    usleep(UInt32(250_000 * (attempt + 1)))
                    continue
                }

                throw DogecoinWalletEngineError.broadcastFailed(errorDescription)
            }
        }
        throw DogecoinWalletEngineError.broadcastFailed("BlockCypher did not accept the transaction.")
    }

    static func broadcastRawTransactionViaBlockCypher(
        _ rawHex: String,
        networkMode: DogecoinNetworkMode
    ) throws {
        guard let url = blockcypherURL(path: "/txs/push", networkMode: networkMode) else {
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

    static func isAlreadyBroadcastedError(_ message: String) -> Bool {
        if classifySendBroadcastFailure(message) == .alreadyBroadcast {
            return true
        }
        let normalized = message.lowercased()
        return normalized.contains("already in blockchain")
            || normalized.contains("already in block chain")
            || normalized.contains("txn-already")
            || normalized.contains("already spent")
    }

    static func isRetryableBroadcastError(_ message: String) -> Bool {
        if classifySendBroadcastFailure(message) == .retryable {
            return true
        }
        return message.lowercased().contains("network")
    }

    static func verifyBroadcastedTransactionIfAvailable(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) -> PostBroadcastVerificationStatus {
        let maxAttempts = 3
        for attempt in 0 ..< maxAttempts {
            let status = verifyPresenceOnlyIfAvailable(txid: txid, networkMode: networkMode)
            if status == .verified {
                return .verified
            }
            if attempt < maxAttempts - 1 {
                usleep(UInt32(350_000 * (attempt + 1)))
            }
        }
        return .deferred
    }

    static func verifyPresenceOnlyIfAvailable(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) -> PostBroadcastVerificationStatus {
        if (try? fetchBlockCypherTransactionHash(txid: txid, networkMode: networkMode)) != nil { return .verified }
        return .deferred
    }

    static func fetchBlockCypherTransactionHash(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) throws -> String? {
        guard let payload = try fetchBlockCypherTransaction(txid: txid, networkMode: networkMode),
              let txHash = payload.hash,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    static func fetchBlockCypherTransaction(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) throws -> BlockCypherProvider.TransactionHashResponse? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/txs/\(encodedTXID)", networkMode: networkMode) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher Dogecoin transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(request, timeout: networkTimeoutSeconds, retries: 0)

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = object["error"] as? String,
           !errorMessage.isEmpty {
            if errorMessage.lowercased().contains("not found") {
                return nil
            }
            throw DogecoinWalletEngineError.networkFailure("BlockCypher transaction lookup failed: \(errorMessage)")
        }

        return try JSONDecoder().decode(BlockCypherProvider.TransactionHashResponse.self, from: data)
    }
}
