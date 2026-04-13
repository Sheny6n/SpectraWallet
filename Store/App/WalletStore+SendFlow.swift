import Foundation
import SwiftUI
import LocalAuthentication
import os
#if canImport(Network)
import Network
#endif
@MainActor
extension WalletStore {
    private func clearAllChainSendState() {
        bitcoinSendPreview = nil; bitcoinCashSendPreview = nil; bitcoinSVSendPreview = nil
        litecoinSendPreview = nil; dogecoinSendPreview = nil; ethereumSendPreview = nil
        tronSendPreview = nil; solanaSendPreview = nil; xrpSendPreview = nil
        stellarSendPreview = nil; moneroSendPreview = nil; cardanoSendPreview = nil
        suiSendPreview = nil; aptosSendPreview = nil; tonSendPreview = nil
        icpSendPreview = nil; nearSendPreview = nil; polkadotSendPreview = nil
        isSendingBitcoin = false; isSendingBitcoinCash = false; isSendingBitcoinSV = false
        isSendingLitecoin = false; isSendingDogecoin = false; isSendingEthereum = false
        isSendingTron = false; isSendingSolana = false; isSendingXRP = false
        isSendingStellar = false; isSendingMonero = false; isSendingCardano = false
        isSendingSui = false; isSendingAptos = false; isSendingTON = false
        isSendingICP = false; isSendingNear = false; isSendingPolkadot = false
        isPreparingEthereumSend = false; isPreparingDogecoinSend = false; isPreparingTronSend = false
        isPreparingSolanaSend = false; isPreparingXRPSend = false; isPreparingStellarSend = false
        isPreparingMoneroSend = false; isPreparingCardanoSend = false; isPreparingSuiSend = false
        isPreparingAptosSend = false; isPreparingTONSend = false; isPreparingICPSend = false
        isPreparingNearSend = false; isPreparingPolkadotSend = false
        pendingDogecoinSelfSendConfirmation = nil
        clearHighRiskSendConfirmation()
    }
    func beginSend() {
        guard let firstWallet = sendEnabledWallets.first else { return }
        sendWalletID = firstWallet.id.uuidString
        sendHoldingKey = availableSendCoins(for: sendWalletID).first?.holdingKey ?? ""
        sendAmount = ""; sendAddress = ""; sendError = nil
        sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false; sendUTXOMaxInputCount = 0; sendEnableRBF = true; sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange; ethereumManualNonceEnabled = false; ethereumManualNonce = ""
        lastSentTransaction = nil
        clearAllChainSendState()
        syncSendAssetSelection()
        isShowingSendSheet = true
    }
    func syncSendAssetSelection() {
        let availableHoldingKeys = availableSendCoins(for: sendWalletID).map(\.holdingKey)
        if !availableHoldingKeys.contains(sendHoldingKey) { sendHoldingKey = availableHoldingKeys.first ?? "" }
        if selectedSendCoin?.chainName != "Ethereum" {
            useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = ""
            ethereumManualNonceEnabled = false; ethereumManualNonce = ""
        }
        if selectedSendCoin?.chainName != "Litecoin" { sendLitecoinChangeStrategy = .derivedChange }
        lastSentTransaction = nil
        clearAllChainSendState()
        sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = false
    }
    func cancelSend() {
        isShowingSendSheet = false
        sendAmount = ""; sendAddress = ""; sendError = nil
        sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false; sendUTXOMaxInputCount = 0; sendEnableRBF = true; sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange; ethereumManualNonceEnabled = false; ethereumManualNonce = ""
        lastSentTransaction = nil
        clearAllChainSendState()
    }
    var selectedSendCoin: Coin? {
        availableSendCoins(for: sendWalletID).first(where: { $0.holdingKey == sendHoldingKey })
    }
    func sendPreviewDetails(for coin: Coin) -> SendPreviewDetails? {
        typealias T = (Double?, String, Int?, Int?, Bool?, Double?, Double?)
        let d: T? switch coin.chainName {
        case "Bitcoin": guard let p = bitcoinSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, p.estimatedTransactionBytes, p.selectedInputCount, p.usesChangeOutput, p.maxSendable, p.estimatedNetworkFeeBTC)
        case "Bitcoin Cash": guard let p = bitcoinCashSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, p.estimatedTransactionBytes, p.selectedInputCount, p.usesChangeOutput, p.maxSendable, p.estimatedNetworkFeeBTC)
        case "Bitcoin SV": guard let p = bitcoinSVSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, p.estimatedTransactionBytes, p.selectedInputCount, p.usesChangeOutput, p.maxSendable, p.estimatedNetworkFeeBTC)
        case "Litecoin": guard let p = litecoinSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, p.estimatedTransactionBytes, p.selectedInputCount, p.usesChangeOutput, p.maxSendable, p.estimatedNetworkFeeBTC)
        case "Dogecoin": guard let p = dogecoinSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, p.estimatedTransactionBytes, p.selectedInputCount, p.usesChangeOutput, p.maxSendable, nil)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": guard let p = ethereumSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Tron": guard let p = tronSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Solana": guard let p = solanaSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "XRP Ledger": guard let p = xrpSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Stellar": guard let p = stellarSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Monero": guard let p = moneroSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Cardano": guard let p = cardanoSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Sui": guard let p = suiSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Aptos": guard let p = aptosSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "TON": guard let p = tonSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Internet Computer": guard let p = icpSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "NEAR": guard let p = nearSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, nil, nil, nil, p.maxSendable, nil)
        case "Polkadot": guard let p = polkadotSendPreview else { return nil }; d = (p.spendableBalance, p.feeRateDescription, p.estimatedTransactionBytes, nil, nil, p.maxSendable, nil)
        default: return nil
        }
        guard let d else { return nil }
        let fallback = d.6.map { max(0, coin.amount - $0) }
        return SendPreviewDetails(
            spendableBalance: d.0 ?? fallback, feeRateDescription: d.1, estimatedTransactionBytes: d.2, selectedInputCount: d.3, usesChangeOutput: d.4, maxSendable: d.5 ?? fallback
        )
    }
    var customEthereumFeeValidationError: String? {
        guard useCustomEthereumFees, selectedSendCoin?.chainName == "Ethereum" else { return nil }
        let trimmedMaxFee = customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPriorityFee = customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let maxFee = Double(trimmedMaxFee), maxFee > 0 else { return localizedStoreString("Enter a valid Max Fee in gwei.") }
        guard let priorityFee = Double(trimmedPriorityFee), priorityFee > 0 else { return localizedStoreString("Enter a valid Priority Fee in gwei.") }
        guard maxFee >= priorityFee else { return localizedStoreString("Max Fee must be greater than or equal to Priority Fee.") }
        return nil
    }
    func customEthereumFeeConfiguration() -> EthereumCustomFeeConfiguration? {
        guard useCustomEthereumFees else { return nil }
        guard customEthereumFeeValidationError == nil else { return nil }
        guard let maxFee = Double(customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)), let priorityFee = Double(customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return EthereumCustomFeeConfiguration(maxFeePerGasGwei: maxFee, maxPriorityFeePerGasGwei: priorityFee)
    }
    var customEthereumNonceValidationError: String? {
        guard ethereumManualNonceEnabled else { return nil }
        let trimmedNonce = ethereumManualNonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNonce.isEmpty else { return localizedStoreString("Enter a nonce value for manual nonce mode.") }
        guard let nonceValue = Int(trimmedNonce), nonceValue >= 0 else { return localizedStoreString("Nonce must be a non-negative integer.") }
        if nonceValue > Int(Int32.max) { return localizedStoreString("Nonce value is too large.") }
        return nil
    }
    func explicitEthereumNonce() -> Int? {
        guard ethereumManualNonceEnabled else { return nil }
        guard customEthereumNonceValidationError == nil else { return nil }
        return Int(ethereumManualNonce.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func selectedWalletForSend() -> ImportedWallet? { wallet(for: sendWalletID) }
    func selectedPendingEthereumSendTransaction() -> TransactionRecord? {
        guard let wallet = selectedWalletForSend() else { return nil }
        return transactions.first { record in
            record.walletID == wallet.id
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }}
    func pendingEthereumSendTransaction(with transactionID: UUID) -> TransactionRecord? {
        transactions.first { record in
            record.id == transactionID
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }}
    func prepareEthereumReplacementContext(cancel: Bool) async {
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
    }
    func openEthereumReplacementComposer(for transactionID: UUID, cancel: Bool) async -> String? {
        guard let pendingTransaction = pendingEthereumSendTransaction(with: transactionID) else {
            let message = localizedStoreString("This Ethereum transaction is no longer pending, so replacement/cancel is unavailable.")
            sendError = message
            return message
        }
        guard let walletID = pendingTransaction.walletID, wallets.contains(where: { $0.id == walletID }) else {
            let message = localizedStoreString("The wallet for this pending transaction is not available.")
            sendError = message
            return message
        }
        sendWalletID = walletID.uuidString
        if let ethereumHolding = availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" && $0.symbol == "ETH" })
            ?? availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" }) {
            sendHoldingKey = ethereumHolding.holdingKey
        }
        syncSendAssetSelection()
        selectedMainTab = .home
        await Task.yield()
        isShowingSendSheet = true
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
        return sendError
    }
    func prepareEthereumReplacementContext(pendingTransaction: TransactionRecord, cancel: Bool) async {
        guard let txHash = pendingTransaction.transactionHash else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        isPreparingEthereumReplacementContext = true
        defer { isPreparingEthereumReplacementContext = false }
        do {
            let nonce = try await WalletServiceBridge.shared.fetchEVMTxNonce(chainId: SpectraChainID.ethereum, txHash: txHash)
            guard let walletID = pendingTransaction.walletID, let wallet = wallets.first(where: { $0.id == walletID }) else {
                sendError = localizedStoreString("Select a wallet first.")
                return
            }
            let selfAddress = wallet.ethereumAddress ?? ""
            sendAddress = cancel ? selfAddress : pendingTransaction.address
            sendAmount = cancel ? "0" : String(format: "%.8f", pendingTransaction.amount)
            ethereumManualNonceEnabled = true
            ethereumManualNonce = String(nonce)
            useCustomEthereumFees = true
            if customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customEthereumMaxFeeGwei = "4.0"
                customEthereumPriorityFeeGwei = "2.0"
            } else {
                let maxFee = (Double(customEthereumMaxFeeGwei) ?? 4.0) * 1.2
                let priority = (Double(customEthereumPriorityFeeGwei) ?? 2.0) * 1.2
                customEthereumMaxFeeGwei = String(format: "%.3f", max(maxFee, 0.1))
                customEthereumPriorityFeeGwei = String(format: "%.3f", max(priority, 0.1))
            }
            sendError = cancel
                ? localizedStoreString("Cancellation context loaded. Review fees and tap Send.")
                : localizedStoreString("Replacement context loaded. Review fees and tap Send.")
            await refreshSendPreview()
        } catch {
            sendError = localizedStoreFormat("Unable to prepare replacement context: %@", error.localizedDescription)
        }}
    func prepareEthereumSpeedUpContext() async { await prepareEthereumReplacementContext(cancel: false) }
    func prepareEthereumCancelContext() async { await prepareEthereumReplacementContext(cancel: true) }
    func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
    func mapEthereumSendError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("nonce too low") { return localizedStoreString("Nonce too low. A newer transaction from this wallet is already known. Refresh and retry.") }
        if message.contains("replacement transaction underpriced") { return localizedStoreString("Replacement transaction underpriced. Increase fees and retry.") }
        if message.contains("already known") { return localizedStoreString("This transaction is already in the mempool.") }
        if message.contains("insufficient funds") { return localizedStoreString("Insufficient ETH to cover value plus network fee.") }
        if message.contains("max fee per gas less than block base fee") { return localizedStoreString("Max fee is below current base fee. Increase Max Fee and retry.") }
        if message.contains("intrinsic gas too low") { return localizedStoreString("Gas limit is too low for this transaction.") }
        return error.localizedDescription
    }
    func evmChainContext(for chainName: String) -> EVMChainContext? {
        switch chainName {
        case "Ethereum": switch ethereumNetworkMode {
            case .mainnet: return .ethereum
            case .sepolia: return .ethereumSepolia
            case .hoodi: return .ethereumHoodi
            }
        case "Ethereum Classic": return .ethereumClassic
        case "Arbitrum": return .arbitrum
        case "Optimism": return .optimism
        case "BNB Chain": return .bnb
        case "Avalanche": return .avalanche
        case "Hyperliquid": return .hyperliquid
        default: return nil
        }}
    func isEVMChain(_ chainName: String) -> Bool { evmChainContext(for: chainName) != nil }
    func configuredEVMRPCEndpointURL(for chainName: String) -> URL? { chainName == "Ethereum" ? configuredEthereumRPCEndpointURL() : nil }
    func supportedEVMToken(for coin: Coin) -> EthereumSupportedToken? {
        guard let chain = evmChainContext(for: coin.chainName) else { return nil }
        if coin.chainName == "Ethereum", coin.symbol == "ETH" { return nil }
        if coin.chainName == "Ethereum Classic", coin.symbol == "ETC" { return nil }
        if coin.chainName == "Optimism", coin.symbol == "ETH" { return nil }
        if coin.chainName == "BNB Chain", coin.symbol == "BNB" { return nil }
        if coin.chainName == "Avalanche", coin.symbol == "AVAX" { return nil }
        if coin.chainName == "Hyperliquid", coin.symbol == "HYPE" { return nil }
        let chainTokens: [EthereumSupportedToken]
        if chain == .ethereum { chainTokens = enabledEthereumTrackedTokens() } else if chain == .bnb { chainTokens = enabledBNBTrackedTokens() } else if chain == .optimism { chainTokens = enabledOptimismTrackedTokens() } else if chain == .avalanche { chainTokens = enabledAvalancheTrackedTokens() } else { chainTokens = [] }
        if let contractAddress = coin.contractAddress {
            let normalizedContract = normalizeEVMAddress(contractAddress)
            return chainTokens.first { $0.symbol == coin.symbol && $0.contractAddress == normalizedContract }}
        return chainTokens.first { $0.symbol == coin.symbol }}
    func isValidDogecoinAddressForPolicy(_ address: String, networkMode: DogecoinNetworkMode? = nil) -> Bool { AddressValidation.isValidDogecoinAddress(address, networkMode: networkMode ?? dogecoinNetworkMode) }
    func isValidAddress(_ address: String, for chainName: String) -> Bool {
        let t = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        switch chainName {
        case "Bitcoin": return AddressValidation.isValidBitcoinAddress(t, networkMode: bitcoinNetworkMode)
        case "Bitcoin Cash": return AddressValidation.isValidBitcoinCashAddress(t)
        case "Bitcoin SV": return AddressValidation.isValidBitcoinSVAddress(t)
        case "Litecoin": return AddressValidation.isValidLitecoinAddress(t)
        case "Dogecoin": return isValidDogecoinAddressForPolicy(t)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return AddressValidation.isValidEthereumAddress(t)
        case "Tron": return AddressValidation.isValidTronAddress(t)
        case "Solana": return AddressValidation.isValidSolanaAddress(t)
        case "Cardano": return AddressValidation.isValidCardanoAddress(t)
        case "XRP Ledger": return AddressValidation.isValidXRPAddress(t)
        case "Stellar": return AddressValidation.isValidStellarAddress(t)
        case "Monero": return AddressValidation.isValidMoneroAddress(t)
        case "Sui": return AddressValidation.isValidSuiAddress(t)
        case "Aptos": return AddressValidation.isValidAptosAddress(t)
        case "TON": return AddressValidation.isValidTONAddress(t)
        case "Internet Computer": return AddressValidation.isValidICPAddress(t)
        case "NEAR": return AddressValidation.isValidNearAddress(t)
        case "Polkadot": return AddressValidation.isValidPolkadotAddress(t)
        default: return false
        }}
    func normalizedAddress(_ address: String, for chainName: String) -> String {
        let t = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEVMChain(chainName) { return normalizeEVMAddress(t) }
        if chainName == "Sui" || chainName == "Aptos" { let l = t.lowercased(); return l.hasPrefix("0x") ? l : "0x\(l)" }
        if chainName == "Internet Computer" || chainName == "NEAR" { return t.lowercased() }
        return t
    }
    func isENSNameCandidate(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasSuffix(".eth")
            && !normalized.contains(" ")
            && !normalized.hasPrefix("0x")
    }
    func resolveEVMRecipientAddress(input: String, for chainName: String) async throws -> (address: String, usedENS: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EthereumWalletEngineError.invalidAddress }
        if AddressValidation.isValidEthereumAddress(trimmed) { return (normalizeEVMAddress(trimmed), false) }
        guard chainName == "Ethereum", isENSNameCandidate(trimmed) else { throw EthereumWalletEngineError.invalidAddress }
        let cacheKey = trimmed.lowercased()
        if let cached = cachedResolvedENSAddresses[cacheKey] { return (cached, true) }
        guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmed) else { throw EthereumWalletEngineError.rpcFailure("Unable to resolve ENS name '\(trimmed)'.") }
        cachedResolvedENSAddresses[cacheKey] = resolved
        return (resolved, true)
    }
    func evmRecipientPreflightReasons(holding: Coin, chain: EVMChainContext, destinationAddress: String) async -> [String] {
        var reasons: [String] = []
        guard let chainId = SpectraChainID.id(for: holding.chainName) else { return reasons }
        do {
            let codeJSON = try await WalletServiceBridge.shared.fetchEVMCodeJSON(chainId: chainId, address: destinationAddress)
            let code = WalletSendLayer.rustField("code", from: codeJSON)
            if evmHasContractCode(code) { reasons.append(localizedStoreFormat("Recipient is a smart contract on %@. Confirm it can receive %@ safely.", holding.chainName, holding.symbol)) }
        } catch {
            reasons.append(localizedStoreFormat("Could not verify recipient contract state on %@. Review destination carefully.", holding.chainName))
        }
        if let token = supportedEVMToken(for: holding) {
            do {
                let codeJSON = try await WalletServiceBridge.shared.fetchEVMCodeJSON(
                    chainId: chainId, address: token.contractAddress
                )
                let code = WalletSendLayer.rustField("code", from: codeJSON)
                if !evmHasContractCode(code) { reasons.append(localizedStoreFormat("Token contract %@ appears missing on %@. This may be a wrong-network token selection.", token.symbol, holding.chainName)) }
            } catch {
                reasons.append(localizedStoreFormat("Could not verify %@ contract bytecode on %@.", token.symbol, holding.chainName))
            }}
        return reasons
    }
    func evaluateHighRiskSendReasons(wallet: ImportedWallet, holding: Coin, amount: Double, destinationAddress: String, destinationInput: String, usedENSResolution: Bool = false) -> [String] {
        let bookEntries = addressBook.map { ["chain_name": $0.chainName, "address": $0.address] }
        let txAddrs = Set(transactions.compactMap { $0.chainName == holding.chainName ? $0.address : nil })
        let txEntries = txAddrs.map { ["chain_name": holding.chainName, "address": $0] }
        let req: [String: Any] = [
            "chain_name": holding.chainName, "symbol": holding.symbol,
            "amount": amount, "holding_amount": holding.amount,
            "destination_address": destinationAddress, "destination_input": destinationInput,
            "used_ens_resolution": usedENSResolution,
            "wallet_selected_chain": wallet.selectedChain,
            "address_book": bookEntries, "tx_addresses": txEntries
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: req),
              let json = String(data: data, encoding: .utf8),
              let result = try? coreEvaluateHighRiskSendReasonsJson(requestJson: json),
              let wData = result.data(using: .utf8),
              let ws = try? JSONSerialization.jsonObject(with: wData) as? [[String: Any]]
        else { return [] }
        return ws.compactMap { w -> String? in
            switch w["code"] as? String {
            case "invalid_format": return localizedStoreFormat("The destination address format does not match %@.", w["chain"] as? String ?? "")
            case "new_address": return localizedStoreString("This is a new destination address with no prior history in this wallet.")
            case "ens_resolved": return localizedStoreFormat("ENS name '%@' resolved to %@. Confirm this resolved address before sending.", w["name"] as? String ?? "", w["address"] as? String ?? "")
            case "large_send":
                let pct = (w["percent"] as? Int) ?? 0
                let formatted = (Double(pct) / 100.0).formatted(.percent.precision(.fractionLength(0)))
                return localizedStoreFormat("This send is %@ of your %@ balance.", formatted, w["symbol"] as? String ?? "")
            case "non_evm_on_evm": return localizedStoreFormat("Destination appears to be a non-EVM address while sending on %@.", w["chain"] as? String ?? "")
            case "ens_on_l2": return localizedStoreFormat("ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", w["chain"] as? String ?? "")
            case "eth_on_utxo": return localizedStoreFormat("Destination appears to be an Ethereum-style address while sending on %@.", w["chain"] as? String ?? "")
            case "non_tron": return localizedStoreString("Destination appears to be non-Tron format while sending on Tron.")
            case "non_solana": return localizedStoreString("Destination appears to be non-Solana format while sending on Solana.")
            case "non_xrp": return localizedStoreString("Destination appears to be non-XRP format while sending on XRP Ledger.")
            case "non_monero": return localizedStoreString("Destination appears to be non-Monero format while sending on Monero.")
            case "chain_mismatch": return localizedStoreString("Wallet-chain context mismatch detected for this send.")
            default: return nil
            }
        }
    }
    func clearHighRiskSendConfirmation() {
        pendingHighRiskSendReasons = []
        isShowingHighRiskSendConfirmation = false
    }
    func confirmHighRiskSendAndSubmit() async {
        bypassHighRiskSendConfirmation = true
        isShowingHighRiskSendConfirmation = false
        await submitSend()
    }
    func addressBookAddressValidationMessage(for address: String, chainName: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAddress.isEmpty {
            switch chainName {
            case "Bitcoin": return localizedStoreString("Enter a Bitcoin address valid for the selected Bitcoin network mode.")
            case "Dogecoin": return localizedStoreString("Dogecoin addresses usually start with D, A, or 9.")
            case "Ethereum": return localizedStoreString("Ethereum addresses must start with 0x and include 40 hex characters.")
            case "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return localizedStoreFormat("%@ addresses use EVM format (0x + 40 hex characters).", chainName)
            case "Tron": return localizedStoreString("Tron addresses usually start with T and are Base58 encoded.")
            case "Solana": return localizedStoreString("Solana addresses are Base58 encoded and typically 32-44 characters.")
            case "Cardano": return localizedStoreString("Cardano addresses typically start with addr1 and use bech32 format.")
            case "XRP Ledger": return localizedStoreString("XRP Ledger addresses start with r and are Base58 encoded.")
            case "Stellar": return localizedStoreString("Stellar addresses start with G and are StrKey encoded.")
            case "Monero": return localizedStoreString("Monero addresses are Base58 encoded and usually start with 4 or 8.")
            case "Sui", "Aptos": return localizedStoreFormat("%@ addresses are hex and typically start with 0x.", chainName)
            case "TON": return localizedStoreString("TON addresses are usually user-friendly strings like UQ... or raw 0:<hex> addresses.")
            case "NEAR": return localizedStoreString("NEAR addresses can be named accounts or 64-character implicit account IDs.")
            case "Polkadot": return localizedStoreString("Polkadot addresses use SS58 encoding and usually start with 1.")
            default: return localizedStoreString("Enter an address for the selected chain.")
            }}
        return isValidAddress(trimmedAddress, for: chainName)
            ? localizedStoreFormat("Valid %@ address.", chainName)
            : {
                switch chainName {
                case "Bitcoin": return localizedStoreString("Enter a valid Bitcoin address for the selected Bitcoin network mode.")
                case "Dogecoin": return localizedStoreString("Enter a valid Dogecoin address beginning with D, A, or 9.")
                case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return localizedStoreFormat("Enter a valid %@ address (0x + 40 hex characters).", chainName)
                case "Tron": return localizedStoreString("Enter a valid Tron address (starts with T).")
                case "Solana": return localizedStoreString("Enter a valid Solana address (Base58 format).")
                case "Cardano": return localizedStoreString("Enter a valid Cardano address (starts with addr1).")
                case "XRP Ledger": return localizedStoreString("Enter a valid XRP address (starts with r).")
                case "Stellar": return localizedStoreString("Enter a valid Stellar address (starts with G).")
                case "Monero": return localizedStoreString("Enter a valid Monero address (starts with 4 or 8).")
                case "Sui", "Aptos": return localizedStoreFormat("Enter a valid %@ address (starts with 0x).", chainName)
                case "TON": return localizedStoreString("Enter a valid TON address.")
                case "NEAR": return localizedStoreString("Enter a valid NEAR account ID or implicit address.")
                case "Polkadot": return localizedStoreString("Enter a valid Polkadot SS58 address.")
                default: return localizedStoreFormat("Enter a valid %@ address.", chainName)
                }}()
    }
    func isDuplicateAddressBookAddress(_ address: String, chainName: String, excluding entryID: UUID? = nil) -> Bool {
        let normalizedAddress = normalizedAddress(address, for: chainName)
        guard !normalizedAddress.isEmpty else { return false }
        return addressBook.contains { entry in
            guard entry.id != entryID, entry.chainName == chainName else { return false }
            return entry.address.caseInsensitiveCompare(normalizedAddress) == .orderedSame
        }}
    func canSaveAddressBookEntry(name: String, address: String, chainName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, isValidAddress(address, for: chainName) else { return false }
        return !isDuplicateAddressBookAddress(address, chainName: chainName)
    }
    func addAddressBookEntry(name: String, address: String, chainName: String, note: String = "") {
        guard canSaveAddressBookEntry(name: name, address: address, chainName: chainName) else { return }
        let entry = AddressBookEntry(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), chainName: chainName, address: normalizedAddress(address, for: chainName), note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        addressBook.insert(entry, at: 0)
    }
    func canSaveLastSentRecipientToAddressBook() -> Bool {
        guard let lastSentTransaction, lastSentTransaction.kind == .send else { return false }
        return canSaveAddressBookEntry(
            name: "\(lastSentTransaction.symbol) Recipient", address: lastSentTransaction.address, chainName: lastSentTransaction.chainName
        )
    }
    func saveLastSentRecipientToAddressBook() {
        guard let lastSentTransaction, lastSentTransaction.kind == .send else { return }
        addAddressBookEntry(
            name: "\(lastSentTransaction.symbol) Recipient", address: lastSentTransaction.address, chainName: lastSentTransaction.chainName, note: "Saved from recent send"
        )
    }
    func renameAddressBookEntry(id: UUID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = addressBook.firstIndex(where: { $0.id == id }) else {
            return
        }
        let entry = addressBook[index]
        addressBook[index] = AddressBookEntry(
            id: entry.id, name: trimmedName, chainName: entry.chainName, address: entry.address, note: entry.note
        )
    }
    func removeAddressBookEntry(id: UUID) {
        addressBook.removeAll { $0.id == id }}
    private func runSyncSelfTests(
        running: WritableKeyPath<WalletStore, Bool>, results: WritableKeyPath<WalletStore, [ChainSelfTestResult]>, lastRun: WritableKeyPath<WalletStore, Date?>, suite: () -> [ChainSelfTestResult], chainName: String, abbrev: String
    ) {
        guard !self[keyPath: running] else { return }
        self[keyPath: running] = true
        self[keyPath: results] = suite()
        self[keyPath: lastRun] = Date()
        self[keyPath: running] = false
        let r = self[keyPath: results]
        let failedCount = r.filter { !$0.passed }.count
        appendChainOperationalEvent(failedCount == 0 ? .info : .warning, chainName: chainName, message: failedCount == 0 ? "\(abbrev) self-tests passed (\(r.count) checks)." : "\(abbrev) self-tests completed with \(failedCount) failure(s).")
    }
    func runBitcoinSelfTests() { runSyncSelfTests(running: \.isRunningBitcoinSelfTests, results: \.bitcoinSelfTestResults, lastRun: \.bitcoinSelfTestsLastRunAt, suite: BitcoinSelfTestSuite.runAll, chainName: "Bitcoin", abbrev: "BTC") }
    func runBitcoinCashSelfTests() { runSyncSelfTests(running: \.isRunningBitcoinCashSelfTests, results: \.bitcoinCashSelfTestResults, lastRun: \.bitcoinCashSelfTestsLastRunAt, suite: BitcoinCashSelfTestSuite.runAll, chainName: "Bitcoin Cash", abbrev: "BCH") }
    func runBitcoinSVSelfTests() { runSyncSelfTests(running: \.isRunningBitcoinSVSelfTests, results: \.bitcoinSVSelfTestResults, lastRun: \.bitcoinSVSelfTestsLastRunAt, suite: BitcoinSVSelfTestSuite.runAll, chainName: "Bitcoin SV", abbrev: "BSV") }
    func runLitecoinSelfTests() { runSyncSelfTests(running: \.isRunningLitecoinSelfTests, results: \.litecoinSelfTestResults, lastRun: \.litecoinSelfTestsLastRunAt, suite: LitecoinSelfTestSuite.runAll, chainName: "Litecoin", abbrev: "LTC") }
    func runDogecoinSelfTests() { runSyncSelfTests(running: \.isRunningDogecoinSelfTests, results: \.dogecoinSelfTestResults, lastRun: \.dogecoinSelfTestsLastRunAt, suite: DogecoinChainSelfTestSuite.runAll, chainName: "Dogecoin", abbrev: "DOGE") }
    func runEthereumSelfTests() async {
        guard !isRunningEthereumSelfTests else { return }
        isRunningEthereumSelfTests = true
        defer { isRunningEthereumSelfTests = false }
        var results = EthereumChainSelfTestSuite.runAll()
        let rpcLabel = configuredEthereumRPCEndpointURL()?.absoluteString ?? "default RPC pool"
        do {
            guard let rpcURL = configuredEthereumRPCEndpointURL() ?? URL(string: "https://ethereum.publicnode.com") else { throw URLError(.badURL) }
            let chainIDRequest = try EthereumRPCProvider.makeRequest(
                method: "eth_chainId", params: [String](), requestID: 1, endpoint: rpcURL
            )
            let blockRequest = try EthereumRPCProvider.makeRequest(
                method: "eth_blockNumber", params: [String](), requestID: 2, endpoint: rpcURL
            )
            let (chainIDData, _) = try await URLSession.shared.data(for: chainIDRequest)
            let (blockData, _) = try await URLSession.shared.data(for: blockRequest)
            let chainIDResp = try JSONDecoder().decode(EthereumRPCProvider.JSONRPCResponse.self, from: chainIDData)
            let blockResp = try JSONDecoder().decode(EthereumRPCProvider.JSONRPCResponse.self, from: blockData)
            let chainID = Int(chainIDResp.result?.dropFirst(2) ?? "", radix: 16) ?? 0
            let latestBlock = Int(blockResp.result?.dropFirst(2) ?? "", radix: 16) ?? 0
            let chainPass = chainID == 1
            results.append(
                ChainSelfTestResult(
                    name: "ETH RPC Chain ID", passed: chainPass, message: chainPass
                        ? "RPC reports Ethereum mainnet (chain id 1)."
                        : "RPC returned chain id \(chainID). Configure an Ethereum mainnet endpoint."
                )
            )
            results.append(
                ChainSelfTestResult(
                    name: "ETH RPC Latest Block", passed: latestBlock > 0, message: latestBlock > 0
                        ? "RPC latest block height: \(latestBlock) via \(rpcLabel)."
                        : "RPC returned an invalid latest block value."
                )
            )
        } catch {
            results.append(
                ChainSelfTestResult(
                    name: "ETH RPC Health", passed: false, message: "RPC health check failed for \(rpcLabel): \(error.localizedDescription)"
                )
            )
        }
        if let firstEthereumWallet = wallets.first(where: { $0.selectedChain == "Ethereum" }), let ethereumAddress = resolvedEthereumAddress(for: firstEthereumWallet) {
            do {
                _ = try await fetchEthereumPortfolio(for: ethereumAddress)
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe", passed: true, message: "Successfully fetched ETH/ERC-20 portfolio for \(firstEthereumWallet.name)."
                    )
                )
            } catch {
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe", passed: false, message: "Portfolio probe failed for \(firstEthereumWallet.name): \(error.localizedDescription)"
                    )
                )
            }
        } else {
            results.append(
                ChainSelfTestResult(
                    name: "ETH Portfolio Probe", passed: true, message: "Skipped: no imported wallet with Ethereum enabled."
                )
            )
        }
        let diagnosticsJSONResult: ChainSelfTestResult
        if let payload = ethereumDiagnosticsJSON(), let data = payload.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["history"] != nil, object["endpoints"] != nil {
            diagnosticsJSONResult = ChainSelfTestResult(
                name: "ETH Diagnostics JSON Shape", passed: true, message: "Diagnostics JSON contains expected top-level keys."
            )
        } else {
            diagnosticsJSONResult = ChainSelfTestResult(
                name: "ETH Diagnostics JSON Shape", passed: false, message: "Diagnostics JSON missing expected keys (history/endpoints)."
            )
        }
        results.append(diagnosticsJSONResult)
        ethereumSelfTestResults = results
        ethereumSelfTestsLastRunAt = Date()
        let failedCount = results.filter { !$0.passed }.count
        if failedCount == 0 { appendChainOperationalEvent(.info, chainName: "Ethereum", message: "ETH diagnostics passed (\(results.count) checks).") } else { appendChainOperationalEvent(.warning, chainName: "Ethereum", message: "ETH diagnostics completed with \(failedCount) failure(s).") }}
    func operationalEvents(for chainName: String) -> [ChainOperationalEvent] { chainOperationalEventsByChain[chainName] ?? [] }
    func feePriorityOption(for chainName: String) -> ChainFeePriorityOption {
        if chainName == "Bitcoin" { return mapBitcoinFeePriorityToChainOption(bitcoinFeePriority) }
        if chainName == "Dogecoin" { return mapDogecoinFeePriorityToChainOption(dogecoinFeePriority) }
        if let rawValue = selectedFeePriorityOptionRawByChain[chainName], let option = ChainFeePriorityOption(rawValue: rawValue) { return option }
        return .normal
    }
    func setFeePriorityOption(_ option: ChainFeePriorityOption, for chainName: String) {
        if chainName == "Bitcoin" {
            bitcoinFeePriority = mapChainOptionToBitcoinFeePriority(option)
            return
        }
        if chainName == "Dogecoin" {
            dogecoinFeePriority = mapChainOptionToDogecoinFeePriority(option)
            return
        }
        selectedFeePriorityOptionRawByChain[chainName] = option.rawValue
    }
    func bitcoinFeePriority(for chainName: String) -> BitcoinFeePriority { mapChainOptionToBitcoinFeePriority(feePriorityOption(for: chainName)) }
    func mapBitcoinFeePriorityToChainOption(_ priority: BitcoinFeePriority) -> ChainFeePriorityOption { ChainFeePriorityOption(rawValue: priority.rawValue) ?? .normal }
    func mapChainOptionToBitcoinFeePriority(_ option: ChainFeePriorityOption) -> BitcoinFeePriority { BitcoinFeePriority(rawValue: option.rawValue) ?? .normal }
    func mapDogecoinFeePriorityToChainOption(_ priority: DogecoinFeePriority) -> ChainFeePriorityOption { ChainFeePriorityOption(rawValue: priority.rawValue) ?? .normal }
    func mapChainOptionToDogecoinFeePriority(_ option: ChainFeePriorityOption) -> DogecoinFeePriority { DogecoinFeePriority(rawValue: option.rawValue) ?? .normal }
    func persistSelectedFeePriorityOptions() { persistCodableToSQLite(selectedFeePriorityOptionRawByChain, key: Self.selectedFeePriorityOptionsByChainDefaultsKey) }
    func runDogecoinRescan() async {
        guard !isRunningDogecoinRescan else { return }
        isRunningDogecoinRescan = true
        defer { isRunningDogecoinRescan = false }
        logger.log("Starting Dogecoin rescan")
        appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rescan started.")
        await refreshDogecoinAddressDiscovery()
        await refreshDogecoinReceiveReservationState()
        await refreshBalances()
        await refreshDogecoinTransactions(limit: HistoryPaging.endpointBatchSize)
        await refreshPendingDogecoinTransactions()
        dogecoinRescanLastRunAt = Date()
        logger.log("Completed Dogecoin rescan")
        appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rescan completed.")
    }
    private func runUTXORescan(
        running: WritableKeyPath<WalletStore, Bool>, lastRun: WritableKeyPath<WalletStore, Date?>, chainName: String, abbrev: String, refreshHistory: () async -> Void, refreshPending: () async -> Void
    ) async {
        guard !self[keyPath: running] else { return }
        self[keyPath: running] = true
        defer { self[keyPath: running] = false }
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(abbrev) rescan started.")
        await refreshBalances()
        await refreshHistory()
        await refreshPending()
        self[keyPath: lastRun] = Date()
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(abbrev) rescan completed.")
    }
    func runBitcoinRescan() async { await runUTXORescan(running: \.isRunningBitcoinRescan, lastRun: \.bitcoinRescanLastRunAt, chainName: "Bitcoin", abbrev: "BTC", refreshHistory: { await self.refreshBitcoinTransactions(limit: HistoryPaging.endpointBatchSize) }, refreshPending: { await self.refreshPendingBitcoinTransactions() }) }
    func runBitcoinCashRescan() async { await runUTXORescan(running: \.isRunningBitcoinCashRescan, lastRun: \.bitcoinCashRescanLastRunAt, chainName: "Bitcoin Cash", abbrev: "BCH", refreshHistory: { await self.refreshBitcoinCashTransactions(limit: HistoryPaging.endpointBatchSize) }, refreshPending: { await self.refreshPendingBitcoinCashTransactions() }) }
    func runBitcoinSVRescan() async { await runUTXORescan(running: \.isRunningBitcoinSVRescan, lastRun: \.bitcoinSVRescanLastRunAt, chainName: "Bitcoin SV", abbrev: "BSV", refreshHistory: { await self.refreshBitcoinSVTransactions(limit: HistoryPaging.endpointBatchSize) }, refreshPending: { await self.refreshPendingBitcoinSVTransactions() }) }
    func runLitecoinRescan() async { await runUTXORescan(running: \.isRunningLitecoinRescan, lastRun: \.litecoinRescanLastRunAt, chainName: "Litecoin", abbrev: "LTC", refreshHistory: { await self.refreshLitecoinTransactions(limit: HistoryPaging.endpointBatchSize) }, refreshPending: { await self.refreshPendingLitecoinTransactions() }) }
    func runDogecoinHistoryDiagnostics() async {
        guard !isRunningDogecoinHistoryDiagnostics else { return }
        isRunningDogecoinHistoryDiagnostics = true
        defer { isRunningDogecoinHistoryDiagnostics = false }
        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Dogecoin", let address = resolvedDogecoinAddress(for: wallet) else { return nil }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            dogecoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }
        for (wallet, address) in walletsToRefresh {
            do {
                let json = try await withTimeout(seconds: 20) { try await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.dogecoin, address: address) }
                dogecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id, identifier: address, sourceUsed: "rust", transactionCount: decodeRustHistoryJSON(json: json).count, nextCursor: nil, error: nil
                )
            } catch {
                dogecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id, identifier: address, sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription
                )
            }
            dogecoinHistoryDiagnosticsLastUpdatedAt = Date()
        }}
    func runDogecoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingDogecoinEndpointHealth else { return }
        isCheckingDogecoinEndpointHealth = true
        defer { isCheckingDogecoinEndpointHealth = false }
        await runSimpleEndpointReachabilityDiagnostics(
            checks: DogecoinBalanceService.diagnosticsChecks(), profile: .diagnostics, setResults: { [weak self] in self?.dogecoinEndpointHealthResults = $0 }, markUpdated: { [weak self] in self?.dogecoinEndpointHealthLastUpdatedAt = Date() }
        )
    }
    func startNetworkPathMonitorIfNeeded() {
#if canImport(Network)
        networkPathMonitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            let constrained = path.isConstrained
            let expensive = path.isExpensive
            DispatchQueue.main.async {
                guard let self else { return }
                self.isNetworkReachable = reachable
                self.isConstrainedNetwork = constrained
                self.isExpensiveNetwork = expensive
            }}
        networkPathMonitor.start(queue: networkPathMonitorQueue)
#endif
    }
    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive, useFaceID, useAutoLock {
            isAppLocked = true
            appLockError = nil
        }
        if !isActive {
            maintenanceTask?.cancel()
            maintenanceTask = nil
            return
        }
        startMaintenanceLoopIfNeeded()
    }
    func unlockApp() async {
        guard useFaceID else {
            isAppLocked = false
            appLockError = nil
            return
        }
        let authenticated = await authenticateForSensitiveAction(reason: "Authenticate to unlock Spectra")
        if authenticated {
            isAppLocked = false
            appLockError = nil
        }}
    func startMaintenanceLoopIfNeeded() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runScheduledMaintenanceOnce()
                let pollSeconds = self.appIsActive ? Self.activeMaintenancePollSeconds : Self.inactiveMaintenancePollSeconds
                try? await Task.sleep(nanoseconds: pollSeconds * 1_000_000_000)
            }}}
    func runScheduledMaintenanceOnce(now: Date = Date()) async {
        if appIsActive {
            await runActiveScheduledMaintenance(now: now)
            return
        }
        let interval = backgroundMaintenanceInterval(now: now)
        guard WalletRefreshPlanner.shouldRunBackgroundMaintenance(
            now: now, isNetworkReachable: isNetworkReachable, lastBackgroundMaintenanceAt: lastBackgroundMaintenanceAt, interval: interval
        ) else {
            return
        }
        lastBackgroundMaintenanceAt = now
        await performBackgroundMaintenanceTick()
    }
    func authenticateForSensitiveAction(reason: String, allowWhenAuthenticationUnavailable: Bool = false) async -> Bool {
        guard useFaceID, requireBiometricForSendActions else { return true }
        let context = LAContext()
        var authError: NSError? guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            if allowWhenAuthenticationUnavailable { return true }
            let message = "Device authentication unavailable: \(authError?.localizedDescription ?? "unknown error")"
            sendError = message
            appLockError = message
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                Task { @MainActor in
                    if success { self.appLockError = nil } else {
                        let message = error?.localizedDescription ?? "Authentication cancelled."
                        self.sendError = message
                        self.appLockError = message
                    }
                    continuation.resume(returning: success)
                }}}}
    func authenticateForSeedPhraseReveal(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError? guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }}}
    func retryUTXOTransactionStatus(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        let supportedChains = Set(["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"])
        guard supportedChains.contains(transaction.chainName), transaction.kind == .send else { return "Status recheck is only supported for UTXO send transactions." }
        guard transaction.transactionHash != nil else { return "This transaction has no hash to recheck." }
        if transaction.chainName == "Dogecoin" {
            var tracker = dogecoinStatusTrackingByTransactionID[transactionID] ?? DogecoinStatusTrackingState.initial(now: Date())
            tracker.nextCheckAt = Date.distantPast
            tracker.reachedFinality = false
            dogecoinStatusTrackingByTransactionID[transactionID] = tracker
        } else {
            var tracker = statusTrackingByTransactionID[transactionID] ?? TransactionStatusTrackingState.initial(now: Date())
            tracker.nextCheckAt = Date.distantPast
            statusTrackingByTransactionID[transactionID] = tracker
        }
        switch transaction.chainName {
        case "Bitcoin": await refreshPendingBitcoinTransactions()
        case "Bitcoin Cash": await refreshPendingBitcoinCashTransactions()
        case "Bitcoin SV": await refreshPendingBitcoinSVTransactions()
        case "Litecoin": await refreshPendingLitecoinTransactions()
        case "Dogecoin": await refreshPendingDogecoinTransactions()
        default: break
        }
        guard let updated = transactions.first(where: { $0.id == transactionID }) else { return "Transaction status refresh completed." }
        if updated.status != transaction.status { return "Status updated: \(updated.statusText)." }
        if updated.status == .pending { return "No confirmation yet. Spectra will keep retrying automatically." }
        if updated.status == .failed { return updated.failureReason ?? "Transaction remains failed." }
        return "Transaction is confirmed."
    }
    func rebroadcastDogecoinTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.chainName == "Dogecoin", transaction.kind == .send else { return "Rebroadcast is only supported for Dogecoin send transactions." }
        guard await authenticateForSensitiveAction(reason: "Authorize Dogecoin rebroadcast") else { return sendError ?? "Authentication failed." }
        guard let rawTransactionHex = transaction.dogecoinRawTransactionHex, !rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "This transaction cannot be rebroadcast because raw signed data was not saved." }
        appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rebroadcast requested.", transactionHash: transaction.transactionHash)
        do {
            let resultJSON = try await WalletServiceBridge.shared.broadcastRaw(chainId: SpectraChainID.dogecoin, payload: rawTransactionHex)
            let txidFromJSON = WalletSendLayer.rustField("txid", from: resultJSON)
            let txHash = txidFromJSON.isEmpty ? (transaction.transactionHash ?? "") : txidFromJSON
            let result = (transactionHash: txHash, verificationStatus: SendBroadcastVerificationStatus.deferred)
            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                let existing = transactions[index]
                transactions[index] = TransactionRecord(
                    id: existing.id, walletID: existing.walletID, kind: existing.kind, status: .pending, walletName: existing.walletName, assetName: existing.assetName, symbol: existing.symbol, chainName: existing.chainName, amount: existing.amount, address: existing.address, transactionHash: result.transactionHash, receiptBlockNumber: existing.receiptBlockNumber, receiptGasUsed: existing.receiptGasUsed, receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei, receiptNetworkFeeETH: existing.receiptNetworkFeeETH, feePriorityRaw: existing.feePriorityRaw, feeRateDescription: existing.feeRateDescription, confirmationCount: existing.confirmationCount, dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE, dogecoinConfirmations: existing.dogecoinConfirmations, dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB, usedChangeOutput: existing.usedChangeOutput, dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput, sourceDerivationPath: existing.sourceDerivationPath, changeDerivationPath: existing.changeDerivationPath, sourceAddress: existing.sourceAddress, changeAddress: existing.changeAddress, dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex, failureReason: nil, transactionHistorySource: existing.transactionHistorySource, createdAt: existing.createdAt
                )
            }
            await refreshPendingDogecoinTransactions()
            switch result.verificationStatus {
            case .verified: appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rebroadcast verified by provider.", transactionHash: result.transactionHash)
                return "Transaction rebroadcasted and observed on network providers."
            case .deferred: appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE rebroadcast accepted; verification deferred.", transactionHash: result.transactionHash)
                return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message): appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE rebroadcast verification warning: \(message)", transactionHash: result.transactionHash)
                return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE rebroadcast failed: \(error.localizedDescription)", transactionHash: transaction.transactionHash)
            return error.localizedDescription
        }}
    func rebroadcastSignedTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.kind == .send else { return "Rebroadcast is only supported for send transactions." }
        guard let payload = transaction.rebroadcastPayload, let format = transaction.rebroadcastPayloadFormat else { return "This transaction cannot be rebroadcast because signed payload data was not saved." }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction rebroadcast") else { return sendError ?? "Authentication failed." }
        do {
            let (transactionHash, verificationStatus) = try await rebroadcastSignedTransaction(
                transaction: transaction, payload: payload, format: format
            )
            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                let existing = transactions[index]
                transactions[index] = TransactionRecord(
                    id: existing.id, walletID: existing.walletID, kind: existing.kind, status: .pending, walletName: existing.walletName, assetName: existing.assetName, symbol: existing.symbol, chainName: existing.chainName, amount: existing.amount, address: existing.address, transactionHash: transactionHash, ethereumNonce: existing.ethereumNonce, receiptBlockNumber: existing.receiptBlockNumber, receiptGasUsed: existing.receiptGasUsed, receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei, receiptNetworkFeeETH: existing.receiptNetworkFeeETH, feePriorityRaw: existing.feePriorityRaw, feeRateDescription: existing.feeRateDescription, confirmationCount: existing.confirmationCount, dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE, dogecoinConfirmations: existing.dogecoinConfirmations, dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB, usedChangeOutput: existing.usedChangeOutput, dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput, sourceDerivationPath: existing.sourceDerivationPath, changeDerivationPath: existing.changeDerivationPath, sourceAddress: existing.sourceAddress, changeAddress: existing.changeAddress, dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex, signedTransactionPayload: existing.signedTransactionPayload, signedTransactionPayloadFormat: existing.signedTransactionPayloadFormat, failureReason: nil, transactionHistorySource: existing.transactionHistorySource, createdAt: existing.createdAt
                )
            }
            if transaction.chainName == "Dogecoin" { await refreshPendingDogecoinTransactions() }
            switch verificationStatus {
            case .verified: return "Transaction rebroadcasted and observed on the network."
            case .deferred: return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message): return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            return error.localizedDescription
        }}
    func rebroadcastSignedTransaction(transaction: TransactionRecord, payload: String, format: String) async throws -> (transactionHash: String, verificationStatus: SendBroadcastVerificationStatus) {
        let existing = transaction.transactionHash ?? ""
        if format == "icp.signed_hex" || format == "icp.rust_json" || format == "monero.rust_json" { return (existing, .deferred) }
        if format == "evm.raw_hex" || format == "evm.rust_json" {
            guard let chainId = SpectraChainID.id(for: transaction.chainName) else { throw NSError(domain: "Spectra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported EVM chain for rebroadcast."]) }
            let resultJSON = try await WalletServiceBridge.shared.broadcastRaw(chainId: chainId, payload: payload)
            let txid = WalletSendLayer.rustField("txid", from: resultJSON)
            return (txid.isEmpty ? existing : txid, .deferred)
        }
        if format == "sui.signed_json" {
            let suiPayload: String
            if let suiData = payload.data(using: .utf8), let suiObj = try? JSONSerialization.jsonObject(with: suiData) as? [String: String], let txB64 = suiObj["txBytesBase64"], let sigB64 = suiObj["signatureBase64"], let remapped = (try? JSONSerialization.data(withJSONObject: ["tx_bytes_b64": txB64, "sig_b64": sigB64]))..flatMap({ String(data: $0, encoding: .utf8) }) {
                suiPayload = remapped
            } else { suiPayload = payload }
            let resultJSON = try await WalletServiceBridge.shared.broadcastRaw(chainId: SpectraChainID.sui, payload: suiPayload)
            let digest = WalletSendLayer.rustField("digest", from: resultJSON)
            return (digest.isEmpty ? existing : digest, .deferred)
        }
        struct BroadcastEntry {
            let chainId: UInt32
            let resultField: String    // field to extract from broadcast result JSON
            let wrapKey: String?       // if set, wrap payload as JSON { wrapKey: payload }
            let extractField: String?  // if set, extract this field from rust_json payload first
        }
        let table: [String: BroadcastEntry] = [
            "bitcoin.raw_hex":        .init(chainId: SpectraChainID.bitcoin,     resultField: "txid",         wrapKey: nil,                extractField: nil), "bitcoin_cash.raw_hex":   .init(chainId: SpectraChainID.bitcoinCash, resultField: "txid",         wrapKey: nil,                extractField: nil), "bitcoin_sv.raw_hex":     .init(chainId: SpectraChainID.bitcoinSv,   resultField: "txid",         wrapKey: nil,                extractField: nil), "litecoin.raw_hex":       .init(chainId: SpectraChainID.litecoin,    resultField: "txid",         wrapKey: nil,                extractField: nil), "dogecoin.raw_hex":       .init(chainId: SpectraChainID.dogecoin,    resultField: "txid",         wrapKey: nil,                extractField: nil), "tron.signed_json":       .init(chainId: SpectraChainID.tron,        resultField: "txid",         wrapKey: nil,                extractField: nil), "solana.base64":          .init(chainId: SpectraChainID.solana,      resultField: "signature",    wrapKey: nil,                extractField: nil), "xrp.blob_hex":           .init(chainId: SpectraChainID.xrp,         resultField: "txid",         wrapKey: "tx_blob_hex",      extractField: nil), "stellar.xdr":            .init(chainId: SpectraChainID.stellar,     resultField: "txid",         wrapKey: "signed_xdr_b64",   extractField: nil), "cardano.cbor_hex":       .init(chainId: SpectraChainID.cardano,     resultField: "txid",         wrapKey: "cbor_hex",         extractField: nil), "near.base64":            .init(chainId: SpectraChainID.near,        resultField: "txid",         wrapKey: "signed_tx_b64",    extractField: nil), "polkadot.extrinsic_hex": .init(chainId: SpectraChainID.polkadot,   resultField: "txid",         wrapKey: "extrinsic_hex",    extractField: nil), "aptos.signed_json":      .init(chainId: SpectraChainID.aptos,       resultField: "txid",         wrapKey: "signed_body_json", extractField: nil), "ton.boc":                .init(chainId: SpectraChainID.ton,         resultField: "message_hash", wrapKey: "boc_b64",          extractField: nil), "bitcoin.rust_json":      .init(chainId: SpectraChainID.bitcoin,     resultField: "txid",         wrapKey: nil,                extractField: "raw_tx_hex"), "bitcoin_cash.rust_json": .init(chainId: SpectraChainID.bitcoinCash, resultField: "txid",         wrapKey: nil,                extractField: "raw_tx_hex"), "bitcoin_sv.rust_json":   .init(chainId: SpectraChainID.bitcoinSv,   resultField: "txid",         wrapKey: nil,                extractField: "raw_tx_hex"), "litecoin.rust_json":     .init(chainId: SpectraChainID.litecoin,    resultField: "txid",         wrapKey: nil,                extractField: "raw_tx_hex"), "dogecoin.rust_json":     .init(chainId: SpectraChainID.dogecoin,    resultField: "txid",         wrapKey: nil,                extractField: "raw_tx_hex"), "solana.rust_json":       .init(chainId: SpectraChainID.solana,      resultField: "signature",    wrapKey: nil,                extractField: "signed_tx_base64"), "tron.rust_json":         .init(chainId: SpectraChainID.tron,        resultField: "txid",         wrapKey: nil,                extractField: "signed_tx_json"), "xrp.rust_json":          .init(chainId: SpectraChainID.xrp,         resultField: "txid",         wrapKey: nil,                extractField: nil), "stellar.rust_json":      .init(chainId: SpectraChainID.stellar,     resultField: "txid",         wrapKey: nil,                extractField: nil), "cardano.rust_json":      .init(chainId: SpectraChainID.cardano,     resultField: "txid",         wrapKey: nil,                extractField: nil), "polkadot.rust_json":     .init(chainId: SpectraChainID.polkadot,    resultField: "txid",         wrapKey: nil,                extractField: nil), "sui.rust_json":          .init(chainId: SpectraChainID.sui,         resultField: "digest",       wrapKey: nil,                extractField: nil), "aptos.rust_json":        .init(chainId: SpectraChainID.aptos,       resultField: "txid",         wrapKey: nil,                extractField: nil), "ton.rust_json":          .init(chainId: SpectraChainID.ton,         resultField: "message_hash", wrapKey: nil,                extractField: nil), "near.rust_json":         .init(chainId: SpectraChainID.near,        resultField: "txid",         wrapKey: nil,                extractField: nil), ]
        guard let entry = table[format] else { throw NSError(domain: "Spectra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rebroadcast is not supported for this transaction format yet."]) }
        let broadcastPayload: String
        if let extractField = entry.extractField { broadcastPayload = WalletSendLayer.rustField(extractField, from: payload) } else if let wrapKey = entry.wrapKey {
            broadcastPayload = (try? JSONSerialization.data(withJSONObject: [wrapKey: payload]))..flatMap { String(data: $0, encoding: .utf8) } ?? payload
        } else { broadcastPayload = payload }
        let resultJSON = try await WalletServiceBridge.shared.broadcastRaw(chainId: entry.chainId, payload: broadcastPayload)
        let resultValue = WalletSendLayer.rustField(entry.resultField, from: resultJSON)
        return (resultValue.isEmpty ? existing : resultValue, .deferred)
    }
    func walletDerivationPath(for wallet: ImportedWallet, chain: SeedDerivationChain) -> String { derivationResolution(for: wallet, chain: chain).normalizedPath }
    func derivationAccount(for wallet: ImportedWallet, chain: SeedDerivationChain) -> UInt32 { derivationResolution(for: wallet, chain: chain).accountIndex }
    func derivationResolution(for wallet: ImportedWallet, chain: SeedDerivationChain) -> SeedDerivationResolution { chain.resolve(path: wallet.seedDerivationPaths.path(for: chain)) }
    func bitcoinNetworkMode(for wallet: ImportedWallet) -> BitcoinNetworkMode { wallet.bitcoinNetworkMode }
    func dogecoinNetworkMode(for wallet: ImportedWallet) -> DogecoinNetworkMode { wallet.dogecoinNetworkMode }
    func displayNetworkName(for chainName: String) -> String {
        if chainName == "Bitcoin" { return bitcoinNetworkMode.displayName }
        if chainName == "Ethereum" { return ethereumNetworkMode.displayName }
        if chainName == "Dogecoin" { return dogecoinNetworkMode.displayName }
        return chainName
    }
    func displayChainTitle(for chainName: String) -> String {
        let networkName = displayNetworkName(for: chainName)
        if networkName == chainName || networkName == "Mainnet" { return chainName }
        return "\(chainName) \(networkName)"
    }
    func displayNetworkName(for wallet: ImportedWallet) -> String {
        if wallet.selectedChain == "Bitcoin" { return bitcoinNetworkMode(for: wallet).displayName }
        if wallet.selectedChain == "Dogecoin" { return dogecoinNetworkMode(for: wallet).displayName }
        return displayNetworkName(for: wallet.selectedChain)
    }
    func displayChainTitle(for wallet: ImportedWallet) -> String {
        let networkName = displayNetworkName(for: wallet)
        if networkName == wallet.selectedChain || networkName == "Mainnet" { return wallet.selectedChain }
        return "\(wallet.selectedChain) \(networkName)"
    }
    func displayNetworkName(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"), let walletID = transaction.walletID, let wallet = cachedWalletByID[walletID] { return displayNetworkName(for: wallet) }
        return displayNetworkName(for: transaction.chainName)
    }
    func displayChainTitle(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"), let walletID = transaction.walletID, let wallet = cachedWalletByID[walletID] { return displayChainTitle(for: wallet) }
        return displayChainTitle(for: transaction.chainName)
    }
    func solanaDerivationPreference(for wallet: ImportedWallet) -> SolanaDerivationPreference { derivationResolution(for: wallet, chain: .solana).flavor == .legacy ? .legacy : .standard }
    func resolvedEthereumAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedEthereumAddress(for: wallet, using: self) }
    func resolvedBitcoinAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedBitcoinAddress(for: wallet, using: self) }
    func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String) -> String? { WalletAddressResolver.resolvedEVMAddress(for: wallet, chainName: chainName, using: self) }
    func resolvedTronAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedTronAddress(for: wallet, using: self) }
    func resolvedSolanaAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedSolanaAddress(for: wallet, using: self) }
    func resolvedSuiAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedSuiAddress(for: wallet, using: self) }
    func resolvedAptosAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedAptosAddress(for: wallet, using: self) }
    func resolvedTONAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedTONAddress(for: wallet, using: self) }
    func resolvedICPAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedICPAddress(for: wallet, using: self) }
    func resolvedNearAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedNearAddress(for: wallet, using: self) }
    func resolvedPolkadotAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedPolkadotAddress(for: wallet, using: self) }
    func resolvedStellarAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedStellarAddress(for: wallet, using: self) }
    func resolvedCardanoAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedCardanoAddress(for: wallet, using: self) }
    func resolvedXRPAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedXRPAddress(for: wallet, using: self) }
    func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedMoneroAddress(for: wallet) }
    func resolvedDogecoinAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedDogecoinAddress(for: wallet, using: self) }
    func resolvedLitecoinAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedLitecoinAddress(for: wallet, using: self) }
    func resolvedBitcoinCashAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedBitcoinCashAddress(for: wallet, using: self) }
    func resolvedBitcoinSVAddress(for wallet: ImportedWallet) -> String? { WalletAddressResolver.resolvedBitcoinSVAddress(for: wallet, using: self) }
    func walletWithResolvedDogecoinAddress(_ wallet: ImportedWallet) -> ImportedWallet {
        let resolvedAddress = resolvedDogecoinAddress(for: wallet) ?? wallet.dogecoinAddress
        return ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXPub: wallet.bitcoinXPub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSVAddress: wallet.bitcoinSVAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: resolvedAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: wallet.holdings
        )
    }
    func knownDogecoinAddresses(for wallet: ImportedWallet) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        let networkMode = wallet.dogecoinNetworkMode
        func addIfValid(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidDogecoinAddressForPolicy(trimmed, networkMode: networkMode) else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }
        addIfValid(resolvedDogecoinAddress(for: wallet))
        addIfValid(wallet.dogecoinAddress)
        for transaction in transactions where
            transaction.chainName == "Dogecoin"
            && transaction.walletID == wallet.id
        {
            addIfValid(transaction.sourceAddress)
            addIfValid(transaction.changeAddress)
        }
        for discoveredAddress in discoveredDogecoinAddressesByWallet[wallet.id] ?? [] { addIfValid(discoveredAddress) }
        for ownedAddress in ownedDogecoinAddresses(for: wallet.id) { addIfValid(ownedAddress) }
        addIfValid(dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: false))
        return ordered
    }
    func parseDogecoinDerivationIndex(path: String?, expectedPrefix: String) -> Int? {
        guard let path, path.hasPrefix(expectedPrefix) else { return nil }
        let suffix = String(path.dropFirst(expectedPrefix.count))
        return Int(suffix)
    }
    func supportsDeepUTXODiscovery(chainName: String) -> Bool { chainName == "Bitcoin Cash" || chainName == "Bitcoin SV" || chainName == "Litecoin" }
    func isValidUTXOAddressForPolicy(_ address: String, chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin": return AddressValidation.isValidBitcoinAddress(address, networkMode: bitcoinNetworkMode)
        case "Bitcoin Cash": return AddressValidation.isValidBitcoinCashAddress(address)
        case "Bitcoin SV": return AddressValidation.isValidBitcoinSVAddress(address)
        case "Litecoin": return AddressValidation.isValidLitecoinAddress(address)
        default: return false
        }}
    func utxoDiscoveryDerivationPath(for wallet: ImportedWallet, chainName: String, branch: WalletDerivationBranch, index: Int) -> String? {
        guard let derivationChain = seedDerivationChain(for: chainName), var segments = DerivationPathParser.parse(walletDerivationPath(for: wallet, chain: derivationChain)), segments.count >= 5 else { return nil }
        segments[segments.count - 2] = DerivationPathSegment(value: UInt32(branch.rawValue), isHardened: false)
        segments[segments.count - 1] = DerivationPathSegment(value: UInt32(max(0, index)), isHardened: false)
        return DerivationPathParser.string(from: segments)
    }
    func parseUTXODiscoveryIndex(path: String?, chainName: String, branch: WalletDerivationBranch) -> Int? {
        guard let path, let derivationChain = seedDerivationChain(for: chainName), let pathSegments = DerivationPathParser.parse(path), var walletSegments = DerivationPathParser.parse(derivationChain.defaultPath), pathSegments.count == walletSegments.count, pathSegments.count >= 5 else { return nil }
        walletSegments[walletSegments.count - 2] = DerivationPathSegment(value: UInt32(branch.rawValue), isHardened: false)
        walletSegments[walletSegments.count - 1] = DerivationPathSegment(value: pathSegments.last?.value ?? 0, isHardened: false)
        let candidatePrefix = DerivationPathParser.string(from: Array(walletSegments.dropLast()))
        let pathPrefix = DerivationPathParser.string(from: Array(pathSegments.dropLast()))
        guard candidatePrefix == pathPrefix, pathSegments[pathSegments.count - 2].value == UInt32(branch.rawValue) else { return nil }
        return Int(pathSegments.last?.value ?? 0)
    }
    func deriveUTXOAddress(for wallet: ImportedWallet, chainName: String, branch: WalletDerivationBranch, index: Int) -> String? {
        guard let seedPhrase = storedSeedPhrase(for: wallet.id), supportsDeepUTXODiscovery(chainName: chainName) || chainName == "Bitcoin", let derivationPath = utxoDiscoveryDerivationPath(for: wallet, chainName: chainName, branch: branch, index: index), let derivationChain = utxoDiscoveryDerivationChain(for: chainName), let address = try? deriveSeedPhraseAddress(
                seedPhrase: seedPhrase, chain: derivationChain, network: derivationNetwork(for: derivationChain, wallet: wallet), derivationPath: derivationPath
              ), isValidUTXOAddressForPolicy(address, chainName: chainName) else {
            return nil
        }
        return address
    }
    func hasUTXOOnChainActivity(address: String, chainName: String) async -> Bool {
        switch chainName {
        case "Bitcoin": if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.bitcoin, address: address), let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let confirmedSats = (obj["confirmed_sats"] as? Int) ?? 0
                let txCount = (obj["utxo_count"] as? Int) ?? 0
                if txCount > 0 || confirmedSats > 0 { return true }}
        case "Bitcoin Cash", "Bitcoin SV", "Litecoin": guard let chainId = SpectraChainID.id(for: chainName) else { return false }
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: chainId, address: address), let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json), sat > 0 { return true }
            if let histJSON = try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address), !(histJSON == "[]" || histJSON == "null"), !((histJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }) ?? []).isEmpty { return true }
        default: return false
        }
        return false
    }
    func knownUTXOAddresses(for wallet: ImportedWallet, chainName: String) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidUTXOAddressForPolicy(trimmed, chainName: chainName) else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }
        switch chainName {
        case "Bitcoin": appendAddress(wallet.bitcoinAddress)
        case "Bitcoin Cash": appendAddress(wallet.bitcoinCashAddress)
        case "Bitcoin SV": appendAddress(wallet.bitcoinSVAddress)
        case "Litecoin": appendAddress(wallet.litecoinAddress)
        default: break
        }
        appendAddress(resolvedAddress(for: wallet, chainName: chainName))
        appendAddress(reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false))
        for transaction in transactions where transaction.chainName == chainName && transaction.walletID == wallet.id {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }
        for discoveredAddress in discoveredUTXOAddressesByChain[chainName]?[wallet.id] ?? [] { appendAddress(discoveredAddress) }
        for ownedAddress in ownedAddresses(for: wallet.id, chainName: chainName) { appendAddress(ownedAddress) }
        return ordered
    }
    func discoverUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        var ordered = knownUTXOAddresses(for: wallet, chainName: chainName)
        var seen = Set(ordered.map { $0.lowercased() })
        guard supportsDeepUTXODiscovery(chainName: chainName), storedSeedPhrase(for: wallet.id) != nil else { return ordered }
        let state = keypoolState(for: wallet, chainName: chainName)
        let highestOwnedExternal = (chainOwnedAddressMapByChain[chainName] ?? [:]).values..filter { $0.walletID == wallet.id && $0.branch == "external" }.map(\.index)..compactMap { $0 }.max() ?? 0
        let reserved = state.reservedReceiveIndex ?? 0
        let scanUpperBound = min(
            Self.utxoDiscoveryMaxIndex, max(state.nextExternalIndex, max(highestOwnedExternal + 1, reserved + 1)) + Self.utxoDiscoveryGapLimit
        )
        guard scanUpperBound >= 0 else { return ordered }
        for index in 0 ... scanUpperBound {
            guard let derivedAddress = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: index) else { continue }
            let normalized = derivedAddress.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                ordered.append(derivedAddress)
            }
            if await hasUTXOOnChainActivity(address: derivedAddress, chainName: chainName) {
                registerOwnedAddress(
                    chainName: chainName, address: derivedAddress, walletID: wallet.id, derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet, chainName: chainName, branch: .external, index: index
                    ), index: index, branch: "external"
                )
            }}
        return ordered
    }
    func refreshUTXOAddressDiscovery(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }
        let discovered = await withTaskGroup(of: (UUID, [String]).self, returning: [UUID: [String]].self) { group in
            for wallet in utxoWallets {
                group.addTask { [wallet] in
                    let addresses = await self.discoverUTXOAddresses(for: wallet, chainName: chainName)
                    return (wallet.id, addresses)
                }}
            var mapping: [UUID: [String]] = [:]
            for await (walletID, addresses) in group { mapping[walletID] = addresses }
            return mapping
        }
        discoveredUTXOAddressesByChain[chainName] = discovered
    }
    func refreshUTXOReceiveReservationState(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else { return }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else { return }
        for wallet in utxoWallets {
            guard storedSeedPhrase(for: wallet.id) != nil else { continue }
            _ = reserveReceiveIndex(for: wallet, chainName: chainName)
            var state = keypoolState(for: wallet, chainName: chainName)
            guard let reservedIndex = state.reservedReceiveIndex, let reservedAddress = deriveUTXOAddress(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                  ) else {
                continue
            }
            registerOwnedAddress(
                chainName: chainName, address: reservedAddress, walletID: wallet.id, derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                ), index: reservedIndex, branch: "external"
            )
            guard await hasUTXOOnChainActivity(address: reservedAddress, chainName: chainName) else { continue }
            let nextReserved = max(state.nextExternalIndex, reservedIndex + 1)
            state.reservedReceiveIndex = nextReserved
            state.nextExternalIndex = max(state.nextExternalIndex, nextReserved + 1)
            var perWallet = chainKeypoolByChain[chainName] ?? [:]
            perWallet[wallet.id] = state
            chainKeypoolByChain[chainName] = perWallet
            if let nextAddress = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: nextReserved) {
                registerOwnedAddress(
                    chainName: chainName, address: nextAddress, walletID: wallet.id, derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet, chainName: chainName, branch: .external, index: nextReserved
                    ), index: nextReserved, branch: "external"
                )
            }}}
    private static let chainNameToDerivationChain: [String: SeedDerivationChain] = [
        "Bitcoin": .bitcoin, "Bitcoin Cash": .bitcoinCash, "Bitcoin SV": .bitcoinSV, "Litecoin": .litecoin, "Dogecoin": .dogecoin, "Ethereum": .ethereum, "Ethereum Classic": .ethereumClassic, "Arbitrum": .arbitrum, "Optimism": .optimism, "BNB Chain": .ethereum, "Avalanche": .avalanche, "Hyperliquid": .hyperliquid, "Tron": .tron, "Solana": .solana, "Stellar": .stellar, "XRP Ledger": .xrp, "Cardano": .cardano, "Sui": .sui, "Aptos": .aptos, "TON": .ton, "Internet Computer": .internetComputer, "NEAR": .near, "Polkadot": .polkadot, ]
    func seedDerivationChain(for chainName: String) -> SeedDerivationChain? { Self.chainNameToDerivationChain[chainName] }
    func walletHasAddress(for wallet: ImportedWallet, chainName: String) -> Bool { resolvedAddress(for: wallet, chainName: chainName) != nil }
    func resolvedAddress(for wallet: ImportedWallet, chainName: String) -> String? { WalletAddressResolver.resolvedAddress(for: wallet, chainName: chainName, using: self) }
    func normalizedOwnedAddressKey(chainName: String, address: String) -> String { address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func registerOwnedAddress(
        chainName: String, address: String?, walletID: UUID?, derivationPath: String?, index: Int?, branch: String? ) {
        guard let address, let walletID else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = normalizedOwnedAddressKey(chainName: chainName, address: trimmed)
        var addresses = chainOwnedAddressMapByChain[chainName] ?? [:]
        addresses[key] = ChainOwnedAddressRecord(
            chainName: chainName, address: trimmed, walletID: walletID, derivationPath: derivationPath, index: index, branch: branch
        )
        chainOwnedAddressMapByChain[chainName] = addresses
    }
    func ownedAddresses(for walletID: UUID, chainName: String) -> [String] {
        (chainOwnedAddressMapByChain[chainName] ?? [:]).compactMap { key, value in
            guard value.walletID == walletID else { return nil }
            return value.address ?? key
        }}
    func normalizedDogecoinAddressKey(_ address: String) -> String { address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func registerDogecoinOwnedAddress(address: String?, walletID: UUID?, derivationPath: String?, index: Int?, branch: String?, networkMode: DogecoinNetworkMode = .mainnet) {
        guard let address, let walletID, let derivationPath, let index, let branch else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDogecoinAddressForPolicy(trimmed, networkMode: networkMode) else { return }
        let key = normalizedDogecoinAddressKey(trimmed)
        dogecoinOwnedAddressMap[key] = DogecoinOwnedAddressRecord(
            address: trimmed, walletID: walletID, derivationPath: derivationPath, index: index, branch: branch
        )
        registerOwnedAddress(
            chainName: "Dogecoin", address: trimmed, walletID: walletID, derivationPath: derivationPath, index: index, branch: branch
        )
    }
    func ownedDogecoinAddresses(for walletID: UUID) -> [String] {
        dogecoinOwnedAddressMap.compactMap { key, value in
            guard value.walletID == walletID else { return nil }
            return value.address ?? key
        }}
    func baselineChainKeypoolState(for wallet: ImportedWallet, chainName: String) -> ChainKeypoolState {
        if chainName == "Dogecoin" {
            let dogecoinState = baselineDogecoinKeypoolState(for: wallet)
            return ChainKeypoolState(
                nextExternalIndex: dogecoinState.nextExternalIndex, nextChangeIndex: dogecoinState.nextChangeIndex, reservedReceiveIndex: dogecoinState.reservedReceiveIndex
            )
        }
        if supportsDeepUTXODiscovery(chainName: chainName) {
            let chainTransactions = transactions.filter { $0.walletID == wallet.id && $0.chainName == chainName }
            let maxExternalIndex = chainTransactions..compactMap {
                    parseUTXODiscoveryIndex(path: $0.sourceDerivationPath, chainName: chainName, branch: .external)
                }.max() ?? -1
            let maxChangeIndex = chainTransactions..compactMap {
                    parseUTXODiscoveryIndex(path: $0.changeDerivationPath, chainName: chainName, branch: .change)
                }.max() ?? -1
            let maxOwnedExternalIndex = (chainOwnedAddressMapByChain[chainName] ?? [:]).values..filter { $0.walletID == wallet.id && $0.branch == "external" }.compactMap(\.index)..max() ?? 0
            let maxOwnedChangeIndex = (chainOwnedAddressMapByChain[chainName] ?? [:]).values..filter { $0.walletID == wallet.id && $0.branch == "change" }.compactMap(\.index)..max() ?? -1
            return ChainKeypoolState(
                nextExternalIndex: max(max(maxExternalIndex, maxOwnedExternalIndex) + 1, 1), nextChangeIndex: max(max(maxChangeIndex, maxOwnedChangeIndex) + 1, 0), reservedReceiveIndex: nil
            )
        }
        let hasResolvedAddress = resolvedAddress(for: wallet, chainName: chainName) != nil
        let nextExternalIndex = hasResolvedAddress ? 1 : 0
        return ChainKeypoolState(
            nextExternalIndex: nextExternalIndex, nextChangeIndex: 0, reservedReceiveIndex: hasResolvedAddress ? 0 : nil
        )
    }
    func keypoolState(for wallet: ImportedWallet, chainName: String) -> ChainKeypoolState {
        if chainName == "Dogecoin" {
            let dogecoinState = keypoolState(for: wallet)
            let mirrored = ChainKeypoolState(
                nextExternalIndex: dogecoinState.nextExternalIndex, nextChangeIndex: dogecoinState.nextChangeIndex, reservedReceiveIndex: dogecoinState.reservedReceiveIndex
            )
            var perWallet = chainKeypoolByChain[chainName] ?? [:]
            perWallet[wallet.id] = mirrored
            chainKeypoolByChain[chainName] = perWallet
            return mirrored
        }
        let baseline = baselineChainKeypoolState(for: wallet, chainName: chainName)
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        if var existing = perWallet[wallet.id] {
            existing.nextExternalIndex = max(existing.nextExternalIndex, baseline.nextExternalIndex)
            existing.nextChangeIndex = max(existing.nextChangeIndex, baseline.nextChangeIndex)
            if existing.reservedReceiveIndex == nil { existing.reservedReceiveIndex = baseline.reservedReceiveIndex }
            perWallet[wallet.id] = existing
            chainKeypoolByChain[chainName] = perWallet
            return existing
        }
        perWallet[wallet.id] = baseline
        chainKeypoolByChain[chainName] = perWallet
        return baseline
    }
    func reserveReceiveIndex(for wallet: ImportedWallet, chainName: String) -> Int? {
        if chainName == "Dogecoin" { return reserveDogecoinReceiveIndex(for: wallet) }
        var state = keypoolState(for: wallet, chainName: chainName)
        if let reserved = state.reservedReceiveIndex { return reserved }
        let reserved = max(state.nextExternalIndex, 0)
        state.reservedReceiveIndex = reserved
        state.nextExternalIndex = reserved + 1
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        perWallet[wallet.id] = state
        chainKeypoolByChain[chainName] = perWallet
        return reserved
    }
    func reserveChangeIndex(for wallet: ImportedWallet, chainName: String) -> Int? {
        if chainName == "Dogecoin" { return reserveDogecoinChangeIndex(for: wallet) }
        var state = keypoolState(for: wallet, chainName: chainName)
        let reserved = max(state.nextChangeIndex, 0)
        state.nextChangeIndex = reserved + 1
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        perWallet[wallet.id] = state
        chainKeypoolByChain[chainName] = perWallet
        return reserved
    }
    func reservedReceiveDerivationPath(for wallet: ImportedWallet, chainName: String, index: Int?) -> String? {
        if chainName == "Dogecoin" {
            guard let index else { return nil }
            return WalletDerivationPath.dogecoin(
                account: 0, branch: .external, index: UInt32(index)
            )
        }
        if supportsDeepUTXODiscovery(chainName: chainName) {
            guard let index else { return nil }
            return utxoDiscoveryDerivationPath(for: wallet, chainName: chainName, branch: .external, index: index)
        }
        guard seedDerivationChain(for: chainName) != nil else { return nil }
        return seedDerivationChain(for: chainName).map { walletDerivationPath(for: wallet, chain: $0) }}
    func reservedReceiveAddress(for wallet: ImportedWallet, chainName: String, reserveIfMissing: Bool) -> String? {
        if chainName == "Dogecoin" { return dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: reserveIfMissing) }
        if supportsDeepUTXODiscovery(chainName: chainName) {
            var state = keypoolState(for: wallet, chainName: chainName)
            if state.reservedReceiveIndex == nil, reserveIfMissing {
                let reserved = max(state.nextExternalIndex, 1)
                state.reservedReceiveIndex = reserved
                state.nextExternalIndex = max(state.nextExternalIndex, reserved + 1)
                var perWallet = chainKeypoolByChain[chainName] ?? [:]
                perWallet[wallet.id] = state
                chainKeypoolByChain[chainName] = perWallet
            }
            guard let reservedIndex = state.reservedReceiveIndex, let address = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: reservedIndex) else { return resolvedAddress(for: wallet, chainName: chainName) }
            registerOwnedAddress(
                chainName: chainName, address: address, walletID: wallet.id, derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                ), index: reservedIndex, branch: "external"
            )
            return address
        }
        if reserveIfMissing { _ = reserveReceiveIndex(for: wallet, chainName: chainName) }
        guard let address = resolvedAddress(for: wallet, chainName: chainName) else { return nil }
        let reservedIndex = keypoolState(for: wallet, chainName: chainName).reservedReceiveIndex
        registerOwnedAddress(
            chainName: chainName, address: address, walletID: wallet.id, derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), index: reservedIndex, branch: "external"
        )
        return address
    }
    func activateLiveReceiveAddress(_ address: String?, for wallet: ImportedWallet, chainName: String, derivationPath: String? = nil) -> String {
        guard let address else { return "" }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let reservedIndex = reserveReceiveIndex(for: wallet, chainName: chainName)
        registerOwnedAddress(
            chainName: chainName, address: trimmed, walletID: wallet.id, derivationPath: derivationPath ?? reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), index: reservedIndex, branch: "external"
        )
        return trimmed
    }
    func syncChainOwnedAddressManagementState() {
        for wallet in wallets {
            for chainName in ChainBackendRegistry.diagnosticsChains.map(\.title) {
                guard let address = resolvedAddress(for: wallet, chainName: chainName) else { continue }
                let reservedIndex = reserveReceiveIndex(for: wallet, chainName: chainName)
                registerOwnedAddress(
                    chainName: chainName, address: address, walletID: wallet.id, derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), index: reservedIndex, branch: "external"
                )
            }}}
    func baselineDogecoinKeypoolState(for wallet: ImportedWallet) -> DogecoinKeypoolState {
        let dogecoinTransactions = transactions.filter {
            $0.chainName == "Dogecoin"
                && $0.walletID == wallet.id
        }
        let maxExternalIndex = dogecoinTransactions..compactMap {
                parseDogecoinDerivationIndex(
                    path: $0.sourceDerivationPath, expectedPrefix: WalletDerivationPath.dogecoinExternalPrefix(account: 0)
                )
            }.max() ?? 0
        let maxChangeIndex = dogecoinTransactions..compactMap {
                parseDogecoinDerivationIndex(
                    path: $0.changeDerivationPath, expectedPrefix: WalletDerivationPath.dogecoinChangePrefix(account: 0)
                )
            }.max() ?? -1
        let maxOwnedExternalIndex = dogecoinOwnedAddressMap.values..filter { $0.walletID == wallet.id && $0.branch == "external" }.map(\.index)..max() ?? 0
        let maxOwnedChangeIndex = dogecoinOwnedAddressMap.values..filter { $0.walletID == wallet.id && $0.branch == "change" }.map(\.index)..max() ?? -1
        return DogecoinKeypoolState(
            nextExternalIndex: max(max(maxExternalIndex, maxOwnedExternalIndex) + 1, 1), nextChangeIndex: max(max(maxChangeIndex, maxOwnedChangeIndex) + 1, 0), reservedReceiveIndex: nil
        )
    }
    func keypoolState(for wallet: ImportedWallet) -> DogecoinKeypoolState {
        let baseline = baselineDogecoinKeypoolState(for: wallet)
        if var existing = dogecoinKeypoolByWalletID[wallet.id] {
            existing.nextExternalIndex = max(existing.nextExternalIndex, baseline.nextExternalIndex)
            existing.nextChangeIndex = max(existing.nextChangeIndex, baseline.nextChangeIndex)
            if let reserved = existing.reservedReceiveIndex { existing.nextExternalIndex = max(existing.nextExternalIndex, reserved + 1) }
            dogecoinKeypoolByWalletID[wallet.id] = existing
            return existing
        }
        dogecoinKeypoolByWalletID[wallet.id] = baseline
        return baseline
    }
    func reserveDogecoinReceiveIndex(for wallet: ImportedWallet) -> Int {
        var state = keypoolState(for: wallet)
        if let reserved = state.reservedReceiveIndex { return reserved }
        let reserved = max(state.nextExternalIndex, 1)
        state.reservedReceiveIndex = reserved
        state.nextExternalIndex = reserved + 1
        dogecoinKeypoolByWalletID[wallet.id] = state
        var genericState = chainKeypoolByChain["Dogecoin"] ?? [:]
        genericState[wallet.id] = ChainKeypoolState(
            nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex, reservedReceiveIndex: state.reservedReceiveIndex
        )
        chainKeypoolByChain["Dogecoin"] = genericState
        return reserved
    }
    func reserveDogecoinChangeIndex(for wallet: ImportedWallet) -> Int {
        var state = keypoolState(for: wallet)
        let reserved = max(state.nextChangeIndex, 0)
        state.nextChangeIndex = reserved + 1
        dogecoinKeypoolByWalletID[wallet.id] = state
        var genericState = chainKeypoolByChain["Dogecoin"] ?? [:]
        genericState[wallet.id] = ChainKeypoolState(
            nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex, reservedReceiveIndex: state.reservedReceiveIndex
        )
        chainKeypoolByChain["Dogecoin"] = genericState
        return reserved
    }
    func dogecoinReservedReceiveAddress(for wallet: ImportedWallet, reserveIfMissing: Bool) -> String? {
        var state = keypoolState(for: wallet)
        if state.reservedReceiveIndex == nil, reserveIfMissing {
            let reserved = max(state.nextExternalIndex, 1)
            state.reservedReceiveIndex = reserved
            state.nextExternalIndex = max(state.nextExternalIndex, reserved + 1)
            dogecoinKeypoolByWalletID[wallet.id] = state
        }
        guard let reservedIndex = state.reservedReceiveIndex else { return nil }
        if let derivedAddress = deriveDogecoinAddress(for: wallet, isChange: false, index: reservedIndex), isValidDogecoinAddressForPolicy(derivedAddress, networkMode: wallet.dogecoinNetworkMode) {
            registerDogecoinOwnedAddress(
                address: derivedAddress, walletID: wallet.id, derivationPath: WalletDerivationPath.dogecoin(
                    account: 0, branch: .external, index: UInt32(reservedIndex)
                ), index: reservedIndex, branch: "external", networkMode: wallet.dogecoinNetworkMode
            )
            return derivedAddress
        }
        return resolvedDogecoinAddress(for: wallet)
    }
    func refreshDogecoinReceiveReservationState() async {
        let dogecoinWallets = wallets.filter { $0.selectedChain == "Dogecoin" }
        guard !dogecoinWallets.isEmpty else { return }
        for wallet in dogecoinWallets {
            guard storedSeedPhrase(for: wallet.id) != nil else { continue }
            _ = reserveDogecoinReceiveIndex(for: wallet)
            var state = keypoolState(for: wallet)
            guard let reservedIndex = state.reservedReceiveIndex else { continue }
            guard let reservedAddress = deriveDogecoinAddress(for: wallet, isChange: false, index: reservedIndex), isValidDogecoinAddressForPolicy(reservedAddress, networkMode: wallet.dogecoinNetworkMode) else { continue }
            registerDogecoinOwnedAddress(
                address: reservedAddress, walletID: wallet.id, derivationPath: WalletDerivationPath.dogecoin(
                    account: 0, branch: .external, index: UInt32(reservedIndex)
                ), index: reservedIndex, branch: "external", networkMode: wallet.dogecoinNetworkMode
            )
            let hasActivity = await hasDogecoinOnChainActivity(address: reservedAddress, networkMode: wallet.dogecoinNetworkMode)
            guard hasActivity else { continue }
            let nextReserved = max(state.nextExternalIndex, reservedIndex + 1)
            state.reservedReceiveIndex = nextReserved
            state.nextExternalIndex = max(state.nextExternalIndex, nextReserved + 1)
            dogecoinKeypoolByWalletID[wallet.id] = state
            if let nextAddress = deriveDogecoinAddress(for: wallet, isChange: false, index: nextReserved), isValidDogecoinAddressForPolicy(nextAddress, networkMode: wallet.dogecoinNetworkMode) {
                registerDogecoinOwnedAddress(
                    address: nextAddress, walletID: wallet.id, derivationPath: WalletDerivationPath.dogecoin(
                        account: 0, branch: .external, index: UInt32(nextReserved)
                    ), index: nextReserved, branch: "external", networkMode: wallet.dogecoinNetworkMode
                )
            }}}
    func hasDogecoinOnChainActivity(address: String, networkMode: DogecoinNetworkMode) async -> Bool {
        if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.dogecoin, address: address), let koin = RustBalanceDecoder.uint64Field("balance_koin", from: json), koin > 0 { return true }
        if let histJSON = try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.dogecoin, address: address), !(histJSON == "[]" || histJSON == "null"), !((histJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }) ?? []).isEmpty {
            return true
        }
        return false
    }
    func discoverDogecoinAddresses(for wallet: ImportedWallet) async -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidDogecoinAddressForPolicy(trimmed) else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }
        appendAddress(wallet.dogecoinAddress)
        appendAddress(resolvedDogecoinAddress(for: wallet))
        appendAddress(dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: false))
        for transaction in transactions where
            transaction.chainName == "Dogecoin"
            && transaction.walletID == wallet.id
        {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }
        if let seedPhrase = storedSeedPhrase(for: wallet.id) {
            let state = keypoolState(for: wallet)
            let highestOwnedExternal = dogecoinOwnedAddressMap.values..filter { $0.walletID == wallet.id && $0.branch == "external" }.map(\.index)..max() ?? 0
            let reserved = state.reservedReceiveIndex ?? 0
            let scanUpperBound = min(
                Self.dogecoinDiscoveryMaxIndex, max(state.nextExternalIndex, max(highestOwnedExternal + 1, reserved + 1)) + Self.dogecoinDiscoveryGapLimit
            )
            if scanUpperBound >= 0 {
                for index in 0 ... scanUpperBound {
                    if let derived = try? deriveSeedPhraseAddress(
                        seedPhrase: seedPhrase, chain: .dogecoin, network: derivationNetwork(for: .dogecoin, wallet: wallet), derivationPath: WalletDerivationPath.dogecoin(
                            account: derivationAccount(for: wallet, chain: .dogecoin), branch: .external, index: UInt32(index)
                        )
                    ) {
                        appendAddress(derived)
                    }}}}
        return ordered
    }
    func deriveDogecoinAddress(for wallet: ImportedWallet, isChange: Bool, index: Int) -> String? {
        guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { return nil }
        return try? deriveSeedPhraseAddress(
            seedPhrase: seedPhrase, chain: .dogecoin, network: derivationNetwork(for: .dogecoin, wallet: wallet), derivationPath: WalletDerivationPath.dogecoin(
                account: derivationAccount(for: wallet, chain: .dogecoin), branch: isChange ? .change : .external, index: UInt32(index)
            )
        )
    }
    func refreshDogecoinAddressDiscovery() async {
        let dogecoinWallets = wallets.filter { $0.selectedChain == "Dogecoin" }
        guard !dogecoinWallets.isEmpty else {
            discoveredDogecoinAddressesByWallet = [:]
            return
        }
        let discovered = await withTaskGroup(of: (UUID, [String]).self, returning: [UUID: [String]].self) { group in
            for wallet in dogecoinWallets {
                group.addTask { [wallet] in
                    let addresses = await self.discoverDogecoinAddresses(for: wallet)
                    return (wallet.id, addresses)
                }}
            var mapping: [UUID: [String]] = [:]
            for await (walletID, addresses) in group { mapping[walletID] = addresses }
            return mapping
        }
        discoveredDogecoinAddressesByWallet = discovered
    }
    func refreshEthereumSendPreview() async { await WalletSendLayer.refreshEthereumSendPreview(using: self) }
    func refreshDogecoinSendPreview() async { await WalletSendLayer.refreshDogecoinSendPreview(using: self) }
    func refreshBitcoinSendPreview() async { await WalletSendLayer.refreshBitcoinSendPreview(using: self) }
    func refreshBitcoinCashSendPreview() async { await WalletSendLayer.refreshBitcoinCashSendPreview(using: self) }
    func refreshBitcoinSVSendPreview() async { await WalletSendLayer.refreshBitcoinSVSendPreview(using: self) }
    func refreshLitecoinSendPreview() async { await WalletSendLayer.refreshLitecoinSendPreview(using: self) }
    func refreshTronSendPreview() async { await WalletSendLayer.refreshTronSendPreview(using: self) }
    func refreshSolanaSendPreview() async { await WalletSendLayer.refreshSolanaSendPreview(using: self) }
    func refreshXRPSendPreview() async { await WalletSendLayer.refreshXRPSendPreview(using: self) }
    func refreshStellarSendPreview() async { await WalletSendLayer.refreshStellarSendPreview(using: self) }
    func refreshMoneroSendPreview() async { await WalletSendLayer.refreshMoneroSendPreview(using: self) }
    func refreshCardanoSendPreview() async { await WalletSendLayer.refreshCardanoSendPreview(using: self) }
    func refreshSuiSendPreview() async { await WalletSendLayer.refreshSuiSendPreview(using: self) }
    func refreshAptosSendPreview() async { await WalletSendLayer.refreshAptosSendPreview(using: self) }
    func refreshTONSendPreview() async { await WalletSendLayer.refreshTONSendPreview(using: self) }
    func refreshICPSendPreview() async { await WalletSendLayer.refreshICPSendPreview(using: self) }
    func refreshNearSendPreview() async { await WalletSendLayer.refreshNearSendPreview(using: self) }
    func refreshPolkadotSendPreview() async { await WalletSendLayer.refreshPolkadotSendPreview(using: self) }
    func refreshSendPreview() async { await WalletSendLayer.refreshSendPreview(using: self) }
    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let probeID = "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)"
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDestination.isEmpty else {
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        var destinationForProbe = trimmedDestination
        var ensResolutionInfo: String? if !isValidAddress(trimmedDestination, for: coin.chainName) {
            if (coin.chainName == "Ethereum" || coin.chainName == "Arbitrum" || coin.chainName == "Optimism" || coin.chainName == "BNB Chain" || coin.chainName == "Avalanche" || coin.chainName == "Hyperliquid"), isENSNameCandidate(trimmedDestination) {
                do {
                    let resolved = try await resolveEVMRecipientAddress(input: trimmedDestination, for: coin.chainName)
                    destinationForProbe = resolved.address
                    ensResolutionInfo = resolved.usedENS ? "Resolved ENS \(trimmedDestination) to \(resolved.address)." : nil
                } catch {
                    sendDestinationRiskWarning = nil
                    sendDestinationInfoMessage = nil
                    isCheckingSendDestinationBalance = false
                    return
                }
            } else {
                sendDestinationRiskWarning = nil
                sendDestinationInfoMessage = nil
                isCheckingSendDestinationBalance = false
                return
            }}
        let addressProbeKey = "\(coin.chainName)|\(coin.symbol)|\(destinationForProbe.lowercased())"
        if lastSendDestinationProbeKey == addressProbeKey {
            sendDestinationRiskWarning = lastSendDestinationProbeWarning
            if let ensResolutionInfo {
                sendDestinationInfoMessage = [lastSendDestinationProbeInfoMessage, ensResolutionInfo]
                    .compactMap { $0 }.joined(separator: " ")
            } else { sendDestinationInfoMessage = lastSendDestinationProbeInfoMessage }
            isCheckingSendDestinationBalance = false
            return
        }
        isCheckingSendDestinationBalance = true
        defer { isCheckingSendDestinationBalance = false }
        do {
            let warning: String? let infoMessage: String? switch coin.chainName {
            case "Bitcoin": let btcJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.bitcoin, address: destinationForProbe)
                let btcObj = btcJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let btcBalance = (btcObj["confirmed_sats"] as? Int) ?? 0
                let hasHistory = ((btcObj["utxo_count"] as? Int) ?? 0) > 0
                warning = (btcBalance <= 0 && !hasHistory)
                    ? "Warning: this Bitcoin address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (btcBalance <= 0 && hasHistory)
                    ? "Note: this Bitcoin address has transaction history but currently zero balance."
                    : nil
            case "Litecoin": (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.litecoin, address: destinationForProbe, balanceField: "balance_sat", divisor: 1e8, chainName: "Litecoin", balanceLabel: "balance")
            case "Dogecoin": guard coin.symbol == "DOGE" else { warning = nil; infoMessage = nil; break }
                (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.dogecoin, address: destinationForProbe, balanceField: "balance_koin", divisor: 1e8, chainName: "Dogecoin", balanceLabel: "balance")
            case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": guard let chainId = SpectraChainID.id(for: coin.chainName) else {
                    warning = nil
                    infoMessage = nil
                    break
                }
                let normalizedAddress = try validateEVMAddress(destinationForProbe)
                let previewJSON = try await WalletServiceBridge.shared.fetchEVMSendPreviewJSON(
                    chainId: chainId, from: normalizedAddress, to: normalizedAddress, valueWei: "0", dataHex: "0x"
                )
                let previewData = previewJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let nonce = previewData["nonce"] as? Int ?? 0
                let hasHistory = nonce > 0
                if coin.symbol == "ETH" || coin.symbol == "BNB" || coin.symbol == "AVAX" || coin.symbol == "ARB" || coin.symbol == "OP" {
                    let nativeBalance = previewData["balance_eth"] as? Double ?? 0
                    warning = (nativeBalance <= 0 && !hasHistory)
                        ? "Warning: this \(coin.chainName) address has zero balance and no transaction history. Double-check recipient details."
                        : nil
                    infoMessage = (nativeBalance <= 0 && hasHistory)
                        ? "Note: this \(coin.chainName) address has transaction history but currently zero \(coin.symbol) balance."
                        : nil
                } else if let token = supportedEVMToken(for: coin) {
                    let tokenBalances = try await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch(
                        chainId: chainId, address: normalizedAddress, tokens: [(contract: token.contractAddress, symbol: token.symbol, decimals: token.decimals)]
                    )
                    let tokenBalance = tokenBalances.first?.balance ?? .zero
                    warning = (tokenBalance <= .zero && !hasHistory)
                        ? "Warning: this address has zero \(coin.symbol) balance and no transaction history on \(coin.chainName). Double-check recipient details."
                        : nil
                    infoMessage = (tokenBalance <= .zero && hasHistory)
                        ? "Note: this address has transaction history but currently zero \(coin.symbol) balance on \(coin.chainName)."
                        : nil
                } else {
                    warning = nil
                    infoMessage = nil
                }
            case "Tron": if coin.symbol == "TRX" || coin.symbol == "USDT" {
                    let tronNativeJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.tron, address: destinationForProbe)
                    let tronSun = RustBalanceDecoder.uint64Field("sun", from: tronNativeJSON) ?? 0
                    let tronHistJSON = (try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.tron, address: destinationForProbe)) ?? "[]"
                    let hasHistory = !(tronHistJSON == "[]" || tronHistJSON == "null" || (tronHistJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []).isEmpty)
                    if coin.symbol == "TRX" {
                        let trxBalance = Double(tronSun) / 1e6
                        warning = (trxBalance <= 0 && !hasHistory)
                            ? "Warning: this Tron address has zero TRX balance and no transaction history. Double-check recipient details."
                            : nil
                        infoMessage = (trxBalance <= 0 && hasHistory)
                            ? "Note: this Tron address has transaction history but currently zero TRX balance."
                            : nil
                    } else {
                        let usdtTokenJSON = try await WalletServiceBridge.shared.fetchTokenBalancesJSON(
                            chainId: SpectraChainID.tron, address: destinationForProbe, tokens: [(contract: TronBalanceService.usdtTronContract, symbol: "USDT", decimals: 6)]
                        )
                        let usdtArr = usdtTokenJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
                        let usdtBalance = usdtArr.first.flatMap { $0["balance_display"] as? String }.flatMap { Double($0) } ?? 0
                        warning = (usdtBalance <= 0 && !hasHistory)
                            ? "Warning: this Tron address has zero USDT balance and no transaction history. Double-check recipient details."
                            : nil
                        infoMessage = (usdtBalance <= 0 && hasHistory)
                            ? "Note: this Tron address has transaction history but currently zero USDT balance."
                            : nil
                    }
                } else {
                    warning = nil
                    infoMessage = nil
                }
            case "Solana": (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.solana, address: destinationForProbe, balanceField: "lamports", divisor: 1e9, chainName: "Solana", balanceLabel: "SOL balance")
            case "XRP Ledger": (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.xrp, address: destinationForProbe, balanceField: "drops", divisor: 1e6, chainName: "XRP", balanceLabel: "XRP balance")
            case "Monero": (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.monero, address: destinationForProbe, balanceField: "piconeros", divisor: 1e12, chainName: "Monero", balanceLabel: "XMR balance")
            case "Sui": (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.sui, address: destinationForProbe, balanceField: "mist", divisor: 1e9, chainName: "Sui", balanceLabel: "SUI balance")
            case "Aptos": (warning, infoMessage) = await fetchChainRiskWarning(chainId: SpectraChainID.aptos, address: destinationForProbe, balanceField: "octas", divisor: 1e8, chainName: "Aptos", balanceLabel: "APT balance")
            case "NEAR": let nearJson = (try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.near, address: destinationForProbe)) ?? "{}"
                let yoctoStr = (nearJson.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["yocto_near"] as? String ?? "0"
                let nearBalance = (Double(yoctoStr) ?? 0) / 1e24
                let nearHistJson = (try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.near, address: destinationForProbe)) ?? "[]"
                let nearHasHistory = !(nearHistJson == "[]" || (nearHistJson.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []).isEmpty)
                warning = (nearBalance <= 0 && !nearHasHistory) ? "Warning: this NEAR address has zero balance and no transaction history. Double-check recipient details." : nil
                infoMessage = (nearBalance <= 0 && nearHasHistory) ? "Note: this NEAR address has transaction history but currently zero NEAR balance." : nil
            default: warning = nil
                infoMessage = nil
            }
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = warning
            sendDestinationInfoMessage = [infoMessage, ensResolutionInfo]
                .compactMap { $0 }.joined(separator: " ")
            lastSendDestinationProbeKey = addressProbeKey
            lastSendDestinationProbeWarning = warning
            lastSendDestinationProbeInfoMessage = sendDestinationInfoMessage
        } catch {
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
        }}
    func userFacingTronSendError(_ error: Error, symbol: String) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("timed out") { return "Tron network request timed out. Please try again." }
        if message.localizedCaseInsensitiveContains("not connected")
            || message.localizedCaseInsensitiveContains("offline") {
            return "No network connection. Check your internet and retry."
        }
        return message
    }
    func recordTronSendDiagnosticError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tronLastSendErrorDetails = trimmed
        tronLastSendErrorAt = Date()
    }
    func submitSend() async { await WalletSendLayer.submitSend(using: self) }
    private func fetchChainRiskWarning(chainId: UInt32, address: String, balanceField: String, divisor: Double, chainName: String, balanceLabel: String) async -> (warning: String?, info: String?) {
        guard let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: chainId, address: address) else { return (nil, nil) }
        let raw = RustBalanceDecoder.uint64Field(balanceField, from: json) ?? 0
        let balance = Double(raw) / divisor
        let histJSON = (try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address)) ?? "[]"
        let hasHistory = !(histJSON == "[]" || histJSON == "null" || (histJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []).isEmpty)
        return (
            (balance <= 0 && !hasHistory) ? "Warning: this \(chainName) address has zero balance and no transaction history. Double-check recipient details." : nil, (balance <= 0 && hasHistory) ? "Note: this \(chainName) address has transaction history but currently zero \(balanceLabel)." : nil
        )
    }
}
