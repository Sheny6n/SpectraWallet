import Foundation
import SolanaSwift
import WalletCore

enum SolanaWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case signingFailed(String)
    case rpcFailed(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Solana")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Solana")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Solana")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Solana", message: message)
        case .rpcFailed(let message):
            let format = NSLocalizedString("Solana RPC failed: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Solana", message: message)
        }
    }
}

struct SolanaSendPreview: Equatable {
    let estimatedNetworkFeeSOL: Double
}

struct SolanaSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeSOL: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum SolanaWalletEngine {
    static let estimatedFeeSOL = 0.000005
    // Primary Solana wallet path used by major wallets.
    private static let primaryDerivationPath = "m/44'/501'/0'/0'"

    enum DerivationPreference {
        case standard
        case legacy
    }

    private static let solanaRPCBases = ChainBackendRegistry.SolanaRuntimeEndpoints.sendRPCBaseURLs

    private static func rpcClient(baseURL: String) -> SolanaAPIClient {
        JSONRPCAPIClient(endpoint: APIEndPoint(address: baseURL, network: .mainnetBeta))
    }

    private static func withRPCClient<T>(_ operation: (SolanaAPIClient) async throws -> T) async throws -> T {
        var lastError: Error?
        for baseURL in solanaRPCBases {
            do {
                return try await operation(rpcClient(baseURL: baseURL))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SolanaWalletEngineError.rpcFailed("No Solana RPC endpoint was reachable.")
    }

    static func derivedAddress(
        for seedPhrase: String,
        preference: DerivationPreference = .standard,
        account: UInt32 = 0
    ) throws -> String {
        let preferredPath = preferredSolanaPath(preference: preference, account: account)
        let resolved = try resolvedSolanaKeyMaterial(
            seedPhrase: seedPhrase,
            ownerAddress: nil,
            preferredDerivationPath: preferredPath,
            account: account
        )
        let address = resolved.address
        guard AddressValidation.isValidSolanaAddress(address) else {
            throw SolanaWalletEngineError.invalidSeedPhrase
        }
        return address
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) throws -> SolanaSendPreview {
        guard AddressValidation.isValidSolanaAddress(ownerAddress), AddressValidation.isValidSolanaAddress(destinationAddress) else {
            throw SolanaWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }
        return SolanaSendPreview(estimatedNetworkFeeSOL: estimatedFeeSOL)
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        preference: DerivationPreference = .standard,
        account: UInt32 = 0
    ) async throws -> SolanaSendResult {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard AddressValidation.isValidSolanaAddress(normalizedOwner),
              AddressValidation.isValidSolanaAddress(normalizedDestination) else {
            throw SolanaWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let lamports = try scaledUnsignedAmount(amount, decimals: 9)
        guard lamports > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let resolvedKey = try resolvedSolanaKeyMaterial(
            seedPhrase: seedPhrase,
            ownerAddress: normalizedOwner,
            preferredDerivationPath: preferredSolanaPath(preference: preference, account: account),
            account: account
        )
        let privateKey = resolvedKey.privateKeyData

        let latestBlockhash = try await fetchLatestBlockhash()

        var transfer = SolanaTransfer()
        transfer.recipient = normalizedDestination
        transfer.value = lamports

        var input = SolanaSigningInput()
        input.privateKey = privateKey
        input.recentBlockhash = latestBlockhash
        input.sender = normalizedOwner
        input.transferTransaction = transfer
        input.txEncoding = .base64

        let output: SolanaSigningOutput = AnySigner.sign(input: input, coin: .solana)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw SolanaWalletEngineError.signingFailed(message)
        }
        let encodedTransaction = output.encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encodedTransaction.isEmpty else {
            throw SolanaWalletEngineError.signingFailed("WalletCore returned an empty transaction payload.")
        }

        let txHash = try await broadcastSignedTransaction(encodedTransaction)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(signature: txHash)
        return SolanaSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeSOL: estimatedFeeSOL,
            verificationStatus: verificationStatus
        )
    }

    static func sendTokenInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        mintAddress: String,
        decimals: Int,
        amount: Double,
        sourceTokenAccountAddress: String?,
        preference: DerivationPreference = .standard,
        account: UInt32 = 0
    ) async throws -> SolanaSendResult {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMint = mintAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard AddressValidation.isValidSolanaAddress(normalizedOwner),
              AddressValidation.isValidSolanaAddress(normalizedDestination),
              AddressValidation.isValidSolanaAddress(normalizedMint) else {
            throw SolanaWalletEngineError.invalidAddress
        }
        guard amount > 0, decimals >= 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let rawAmount = try scaledUnsignedAmount(amount, decimals: decimals)
        guard rawAmount > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let ownerPublicKey = try PublicKey(string: normalizedOwner)
        let destinationPublicKey = try PublicKey(string: normalizedDestination)
        let mintPublicKey = try PublicKey(string: normalizedMint)

        let resolvedSourceTokenAccount: String
        if let sourceTokenAccountAddress,
           AddressValidation.isValidSolanaAddress(sourceTokenAccountAddress) {
            resolvedSourceTokenAccount = sourceTokenAccountAddress
        } else {
            resolvedSourceTokenAccount = try PublicKey.associatedTokenAddress(
                walletAddress: ownerPublicKey,
                tokenMintAddress: mintPublicKey,
                tokenProgramId: TokenProgram.id
            ).base58EncodedString
        }

        let destinationTokenAccount = try PublicKey.associatedTokenAddress(
            walletAddress: destinationPublicKey,
            tokenMintAddress: mintPublicKey,
            tokenProgramId: TokenProgram.id
        ).base58EncodedString

        let resolvedKey = try resolvedSolanaKeyMaterial(
            seedPhrase: seedPhrase,
            ownerAddress: normalizedOwner,
            preferredDerivationPath: preferredSolanaPath(preference: preference, account: account),
            account: account
        )
        let privateKey = resolvedKey.privateKeyData
        let latestBlockhash = try await fetchLatestBlockhash()

        var message = SolanaCreateAndTransferToken()
        message.recipientMainAddress = normalizedDestination
        message.tokenMintAddress = normalizedMint
        message.recipientTokenAddress = destinationTokenAccount
        message.senderTokenAddress = resolvedSourceTokenAccount
        message.amount = rawAmount
        message.decimals = UInt32(decimals)

        var input = SolanaSigningInput()
        input.privateKey = privateKey
        input.recentBlockhash = latestBlockhash
        input.sender = normalizedOwner
        input.createAndTransferTokenTransaction = message
        input.txEncoding = .base64

        let output: SolanaSigningOutput = AnySigner.sign(input: input, coin: .solana)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw SolanaWalletEngineError.signingFailed(message)
        }
        let encodedTransaction = output.encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encodedTransaction.isEmpty else {
            throw SolanaWalletEngineError.signingFailed("WalletCore returned an empty token transaction payload.")
        }

        let txHash = try await broadcastSignedTransaction(encodedTransaction)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(signature: txHash)
        return SolanaSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeSOL: estimatedFeeSOL,
            verificationStatus: verificationStatus
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(signature: String) async -> SendBroadcastVerificationStatus {
        let normalizedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSignature.isEmpty else { return .deferred }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignatureStatuses",
            "params": [
                [normalizedSignature],
                ["searchTransactionHistory": true]
            ]
        ]

        var lastError: Error?
        for attempt in 0 ..< 3 {
            for baseURL in solanaRPCBases {
                do {
                    guard let url = URL(string: baseURL) else { continue }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 20
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

                    let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
                    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                        throw SolanaWalletEngineError.rpcFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = object["result"] as? [String: Any],
                          let values = result["value"] as? [Any],
                          let first = values.first else {
                        throw SolanaWalletEngineError.rpcFailed("Invalid signature status payload.")
                    }

                    if first is NSNull {
                        continue
                    }
                    guard let status = first as? [String: Any] else {
                        throw SolanaWalletEngineError.rpcFailed("Invalid signature status entry.")
                    }
                    if let err = status["err"], !(err is NSNull) {
                        return .failed("Solana reported transaction error: \(err)")
                    }
                    if status["confirmationStatus"] != nil || status["confirmations"] != nil || status["slot"] != nil {
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

    private static func fetchLatestBlockhash() async throws -> String {
        let hash = try await withRPCClient { client in
            try await client.getRecentBlockhash(commitment: "confirmed")
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw SolanaWalletEngineError.rpcFailed("Latest blockhash was empty.")
        }
        return hash
    }

    private static func broadcastSignedTransaction(_ encodedTransactionBase64: String) async throws -> String {
        guard let config = RequestConfiguration(
            commitment: "confirmed",
            encoding: "base64",
            skipPreflight: false,
            preflightCommitment: "confirmed"
        ) else {
            throw SolanaWalletEngineError.broadcastFailed("Failed to build Solana transaction config.")
        }
        let signature = try await withRPCClient { client in
            try await client.sendTransaction(
                transaction: encodedTransactionBase64,
                configs: config
            )
        }
        let txHash = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txHash.isEmpty else {
            throw SolanaWalletEngineError.broadcastFailed("Provider did not return a transaction hash.")
        }
        return txHash
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let amountDecimal = NSDecimalNumber(value: amount)
        let scaled = amountDecimal.multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        if rounded == NSDecimalNumber.notANumber || rounded.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw SolanaWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw SolanaWalletEngineError.invalidAmount
        }
        let value = rounded.uint64Value
        guard value > 0 else {
            throw SolanaWalletEngineError.invalidAmount
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

    private struct SolanaKeyMaterial {
        let address: String
        let privateKeyData: Data
        let derivationPath: String
    }

    private static func resolvedSolanaKeyMaterial(
        seedPhrase: String,
        ownerAddress: String?,
        preferredDerivationPath: String? = nil,
        account: UInt32 = 0
    ) throws -> SolanaKeyMaterial {
        let normalizedMnemonic = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        guard let wallet = HDWallet(mnemonic: normalizedMnemonic, passphrase: "") else {
            throw SolanaWalletEngineError.invalidSeedPhrase
        }

        let normalizedOwner = ownerAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var firstValid: SolanaKeyMaterial?
        let accountScopedPaths = supportedDerivationPaths(for: account)
        let derivationPathsToTry: [String] = {
            guard let preferredDerivationPath else { return accountScopedPaths }
            var ordered = [preferredDerivationPath]
            for path in accountScopedPaths where path != preferredDerivationPath {
                ordered.append(path)
            }
            return ordered
        }()

        for path in derivationPathsToTry {
            let key = wallet.getKey(coin: .solana, derivationPath: path)
            let address = CoinType.solana.deriveAddress(privateKey: key)
            guard AddressValidation.isValidSolanaAddress(address) else { continue }
            let candidate = SolanaKeyMaterial(
                address: address,
                privateKeyData: key.data,
                derivationPath: path
            )
            if firstValid == nil {
                firstValid = candidate
            }
            if let normalizedOwner, address.lowercased() == normalizedOwner {
                return candidate
            }
        }

        if let firstValid, normalizedOwner == nil {
            return firstValid
        }
        if let firstValid, let normalizedOwner, firstValid.address.lowercased() == normalizedOwner {
            return firstValid
        }

        throw SolanaWalletEngineError.invalidSeedPhrase
    }

    private static func supportedDerivationPaths(for account: UInt32) -> [String] {
        [
            "m/44'/501'/\(account)'/0'",
            "m/44'/501'/\(account)'"
        ]
    }

    private static func preferredSolanaPath(preference: DerivationPreference, account: UInt32) -> String {
        switch preference {
        case .standard:
            return "m/44'/501'/\(account)'/0'"
        case .legacy:
            return "m/44'/501'/\(account)'"
        }
    }
}
