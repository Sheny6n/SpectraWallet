import Foundation
import SwiftUI
@MainActor
extension WalletStore {
    func beginReceive() {
        guard let firstWallet = receiveEnabledWallets.first else { return }
        receiveWalletID = firstWallet.id.uuidString
        receiveChainName = availableReceiveChains(for: receiveWalletID).first ?? ""
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
        isShowingReceiveSheet = true
    }
    func syncReceiveAssetSelection() {
        let availableChains = availableReceiveChains(for: receiveWalletID)
        if !availableChains.contains(receiveChainName) { receiveChainName = availableChains.first ?? "" }
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
    }
    func cancelReceive() {
        isShowingReceiveSheet = false
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
    }
    func refreshPendingTransactions(includeHistoryRefreshes: Bool = true, historyRefreshInterval: TimeInterval = 120) async {
        guard !isRefreshingPendingTransactions else { return }
        let trackedChains = pendingTransactionMaintenanceChainIDs
        guard !trackedChains.isEmpty else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        isRefreshingPendingTransactions = true
        defer {
            isRefreshingPendingTransactions = false
            recordPerformanceSample(
                "refresh_pending_transactions", startedAt: startedAt, metadata: "chains=\(trackedChains.count) include_history=\(includeHistoryRefreshes)"
            )
        }
        lastPendingTransactionRefreshAt = Date()
        let trackedTransactionIDs = Set(
            transactions.compactMap { transaction -> UUID? in
                guard transaction.kind == .send, transaction.transactionHash != nil else { return nil }
                if transaction.status == .pending { return transaction.id }
                if transaction.status == .confirmed { return transaction.id }
                return nil
            }
        )
        statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedTransactionIDs.contains($0.key) }
        await withTaskGroup(of: Void.self) { group in
            let allPendingChains = [
                "Bitcoin", "Bitcoin Cash", "Litecoin", "Ethereum", "Arbitrum", "Optimism", "Ethereum Classic", "BNB Chain", "Avalanche", "Hyperliquid", "Dogecoin", "Tron", "Solana", "Cardano", "XRP Ledger", "Stellar", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot"
            ]
            for chainName in allPendingChains {
                guard let chainID = WalletChainID(chainName), trackedChains.contains(chainID) else { continue }
                group.addTask { await self.refreshPendingTransactionsForChain(chainName) }}
            await group.waitForAll()
        }
        guard includeHistoryRefreshes else {
            if let lastSentTransaction, let refreshedTransaction = transactions.first(where: { $0.id == lastSentTransaction.id }) {
                self.lastSentTransaction = refreshedTransaction
                updateSendVerificationNoticeForLastSentTransaction()
            }
            return
        }
        await runPendingTransactionHistoryRefreshes(for: trackedChains, interval: historyRefreshInterval)
        if let lastSentTransaction, let refreshedTransaction = transactions.first(where: { $0.id == lastSentTransaction.id }) {
            self.lastSentTransaction = refreshedTransaction
            updateSendVerificationNoticeForLastSentTransaction()
        }}
    var pendingTransactionRefreshStatusText: String? {
        guard let lastPendingTransactionRefreshAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeText = formatter.localizedString(for: lastPendingTransactionRefreshAt, relativeTo: Date())
        return localizedStoreFormat("Last checked %@", relativeText)
    }
    func receiveAddress() -> String {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else { return "Select a wallet and chain" }
        if receiveCoin.symbol == "BTC" {
            if !receiveResolvedAddress.isEmpty { return receiveResolvedAddress }
            if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty { return bitcoinAddress }
            if storedSeedPhrase(for: wallet.id) == nil { return "Bitcoin receive unavailable. Open Edit Name and add the seed phrase or BTC watch address." }
            return isResolvingReceiveAddress ? "Loading Bitcoin receive address..." : "Tap Refresh or reopen Receive to resolve a Bitcoin address."
        }
        if receiveCoin.symbol == "BCH", receiveCoin.chainName == "Bitcoin Cash" {
            if !receiveResolvedAddress.isEmpty { return receiveResolvedAddress }
            if let bitcoinCashAddress = resolvedBitcoinCashAddress(for: wallet), !bitcoinCashAddress.isEmpty { return bitcoinCashAddress }
            if storedSeedPhrase(for: wallet.id) == nil { return "Bitcoin Cash receive unavailable. Open Edit Name and add the seed phrase or BCH watch address." }
            return isResolvingReceiveAddress ? "Loading Bitcoin Cash receive address..." : "Tap Refresh or reopen Receive to resolve a Bitcoin Cash address."
        }
        if receiveCoin.symbol == "BSV", receiveCoin.chainName == "Bitcoin SV" {
            if !receiveResolvedAddress.isEmpty { return receiveResolvedAddress }
            if let bitcoinSVAddress = resolvedBitcoinSVAddress(for: wallet), !bitcoinSVAddress.isEmpty { return bitcoinSVAddress }
            if storedSeedPhrase(for: wallet.id) == nil { return "Bitcoin SV receive unavailable. Open Edit Name and add the seed phrase or BSV watch address." }
            return isResolvingReceiveAddress ? "Loading Bitcoin SV receive address..." : "Tap Refresh or reopen Receive to resolve a Bitcoin SV address."
        }
        if receiveCoin.symbol == "LTC", receiveCoin.chainName == "Litecoin" {
            if !receiveResolvedAddress.isEmpty { return receiveResolvedAddress }
            if let litecoinAddress = resolvedLitecoinAddress(for: wallet), !litecoinAddress.isEmpty { return litecoinAddress }
            if storedSeedPhrase(for: wallet.id) == nil { return "Litecoin receive unavailable. Open Edit Name and add the seed phrase or LTC watch address." }
            return isResolvingReceiveAddress ? "Loading Litecoin receive address..." : "Tap Refresh or reopen Receive to resolve a Litecoin address."
        }
        if receiveCoin.symbol == "DOGE", receiveCoin.chainName == "Dogecoin" {
            if !receiveResolvedAddress.isEmpty { return receiveResolvedAddress }
            let hasSeed = storedSeedPhrase(for: wallet.id) != nil
            let hasWatchAddress = wallet.dogecoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasSeed || hasWatchAddress else { return "Dogecoin receive unavailable. Open Edit Name and add a seed phrase or DOGE watch address." }
            return isResolvingReceiveAddress ? "Loading Dogecoin receive address..." : "Tap Refresh or reopen Receive to resolve a Dogecoin address."
        }
        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) else { return "\(receiveCoin.chainName) receive unavailable. Open Edit Name and add the seed phrase." }
            return receiveResolvedAddress.isEmpty ? evmAddress : receiveResolvedAddress
        }
        let simpleChainResolvers: [(String, (ImportedWallet) -> String?, String)] = [
            ("Tron",              { self.resolvedTronAddress(for: $0) },      "seed phrase or TRON watch address"), ("Solana",            { self.resolvedSolanaAddress(for: $0) },    "seed phrase or SOL watch address"), ("Cardano",           { self.resolvedCardanoAddress(for: $0) },   "seed phrase"), ("XRP Ledger",        { self.resolvedXRPAddress(for: $0) },       "seed phrase or XRP watch address"), ("Stellar",           { self.resolvedStellarAddress(for: $0) },   "seed phrase or Stellar watch address"), ("Monero",            { self.resolvedMoneroAddress(for: $0) },    "a Monero address"), ("Sui",               { self.resolvedSuiAddress(for: $0) },       "seed phrase or Sui watch address"), ("Aptos",             { self.resolvedAptosAddress(for: $0) },     "seed phrase or Aptos watch address"), ("TON",               { self.resolvedTONAddress(for: $0) },       "seed phrase or TON watch address"), ("Internet Computer", { self.resolvedICPAddress(for: $0) },       "seed phrase or ICP watch address"), ("NEAR",              { self.resolvedNearAddress(for: $0) },      "seed phrase or NEAR watch address"), ("Polkadot",          { self.resolvedPolkadotAddress(for: $0) },  "seed phrase or Polkadot watch address"), ]
        for (chainName, resolver, hint) in simpleChainResolvers where receiveCoin.chainName == chainName {
            guard let address = resolver(wallet) else { return "\(chainName) receive unavailable. Open Edit Name and add the \(hint)." }
            return receiveResolvedAddress.isEmpty ? address : receiveResolvedAddress
        }
        return "Receive is not enabled for this chain."
    }
    private func refreshPendingTransactionsForChain(_ chainName: String) async {
        switch chainName {
        case "Bitcoin":           await refreshPendingBitcoinTransactions()
        case "Bitcoin Cash":      await refreshPendingBitcoinCashTransactions()
        case "Litecoin":          await refreshPendingLitecoinTransactions()
        case "Ethereum":          await refreshPendingEthereumTransactions()
        case "Arbitrum":          await refreshPendingArbitrumTransactions()
        case "Optimism":          await refreshPendingOptimismTransactions()
        case "Ethereum Classic":  await refreshPendingETCTransactions()
        case "BNB Chain":         await refreshPendingBNBTransactions()
        case "Avalanche":         await refreshPendingAvalancheTransactions()
        case "Hyperliquid":       await refreshPendingHyperliquidTransactions()
        case "Dogecoin":          await refreshPendingDogecoinTransactions()
        case "Tron":              await refreshPendingTronTransactions()
        case "Solana":            await refreshPendingSolanaTransactions()
        case "Cardano":           await refreshPendingCardanoTransactions()
        case "XRP Ledger":        await refreshPendingXRPTransactions()
        case "Stellar":           await refreshPendingStellarTransactions()
        case "Monero":            await refreshPendingMoneroTransactions()
        case "Sui":               await refreshPendingSuiTransactions()
        case "Aptos":             await refreshPendingAptosTransactions()
        case "TON":               await refreshPendingTONTransactions()
        case "Internet Computer": await refreshPendingICPTransactions()
        case "NEAR":              await refreshPendingNearTransactions()
        case "Polkadot":          await refreshPendingPolkadotTransactions()
        default: break
        }}
    func refreshReceiveAddress() async {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            receiveResolvedAddress = ""
            return
        }
        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) else {
                receiveResolvedAddress = ""
                return
            }
            guard !isResolvingReceiveAddress else { return }
            isResolvingReceiveAddress = true
            defer { isResolvingReceiveAddress = false }
            do {
                receiveResolvedAddress = activateLiveReceiveAddress(
                    try receiveEVMAddress(for: evmAddress), for: wallet, chainName: receiveCoin.chainName
                )
            } catch {
                receiveResolvedAddress = ""
            }
            return
        }
        let liveResolvers: [(String, (ImportedWallet) -> String?)] = [
            ("Tron",              { self.resolvedTronAddress(for: $0) }), ("Solana",            { self.resolvedSolanaAddress(for: $0) }), ("Cardano",           { self.resolvedCardanoAddress(for: $0) }), ("XRP Ledger",        { self.resolvedXRPAddress(for: $0) }), ("Stellar",           { self.resolvedStellarAddress(for: $0) }), ("Monero",            { self.resolvedMoneroAddress(for: $0) }), ("Sui",               { self.resolvedSuiAddress(for: $0) }), ("Aptos",             { self.resolvedAptosAddress(for: $0) }), ("TON",               { self.resolvedTONAddress(for: $0) }), ("Internet Computer", { self.resolvedICPAddress(for: $0) }), ("NEAR",              { self.resolvedNearAddress(for: $0) }), ("Polkadot",          { self.resolvedPolkadotAddress(for: $0) }), ]
        for (chainName, resolver) in liveResolvers where receiveCoin.chainName == chainName {
            receiveResolvedAddress = activateLiveReceiveAddress(resolver(wallet), for: wallet, chainName: chainName)
            return
        }
        if receiveCoin.symbol == "DOGE", receiveCoin.chainName == "Dogecoin" {
            guard let dogecoinAddress = dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: true) else {
                receiveResolvedAddress = ""
                return
            }
            receiveResolvedAddress = dogecoinAddress
            return
        }
        guard receiveCoin.symbol == "BTC" else {
            if (receiveCoin.symbol == "BCH" && receiveCoin.chainName == "Bitcoin Cash")
                || (receiveCoin.symbol == "BSV" && receiveCoin.chainName == "Bitcoin SV")
                || (receiveCoin.symbol == "LTC" && receiveCoin.chainName == "Litecoin") {
                receiveResolvedAddress = reservedReceiveAddress(for: wallet, chainName: receiveCoin.chainName, reserveIfMissing: true) ?? ""
                return
            }
            receiveResolvedAddress = ""
            return
        }
        if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty, storedSeedPhrase(for: wallet.id) == nil {
            receiveResolvedAddress = activateLiveReceiveAddress(bitcoinAddress, for: wallet, chainName: receiveCoin.chainName)
            return
        }
        guard !isResolvingReceiveAddress else { return }
        isResolvingReceiveAddress = true
        defer { isResolvingReceiveAddress = false }
        do {
            let xpub: String
            if let stored = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty { xpub = stored } else if let seedPhrase = storedSeedPhrase(for: wallet.id) {
                xpub = try await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                    mnemonicPhrase: seedPhrase, passphrase: "", accountPath: "m/84'/0'/0'")
            } else {
                receiveResolvedAddress = ""
                return
            }
            let json = try await WalletServiceBridge.shared.fetchBitcoinNextUnusedAddressJSON(xpub: xpub)
            let address: String? if json.trimmingCharacters(in: .whitespacesAndNewlines) == "null" { address = nil } else if let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { address = obj["address"] as? String } else { address = nil }
            receiveResolvedAddress = activateLiveReceiveAddress(
                address ?? wallet.bitcoinAddress ?? "", for: wallet, chainName: receiveCoin.chainName
            )
        } catch {
            receiveResolvedAddress = ""
        }}
    func importWallet() async {
        guard canImportWallet else { return }
        guard !isImportingWallet else { return }
        let trimmedWalletName = importDraft.walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingWalletID {
            renameWallet(id: editingWalletID, to: trimmedWalletName)
            return
        }
        if importDraft.requiresBackupVerification && !importDraft.isBackupVerificationComplete {
            importError = "Confirm your seed backup words before importing the wallet."
            return
        }
        isImportingWallet = true
        defer { isImportingWallet = false }
        let coins = importDraft.selectedCoins
        let trimmedSeedPhrase = importDraft.seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }.joined(separator: " ")
        let trimmedPrivateKey = PrivateKeyHex.normalized(from: importDraft.privateKeyInput)
        let trimmedWalletPassword = importDraft.normalizedWalletPassword
        let bitcoinAddressEntries = importDraft.watchOnlyEntries(from: importDraft.bitcoinAddressInput)
        let trimmedBitcoinAddress = importDraft.bitcoinAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBitcoinXPub = importDraft.bitcoinXPubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let bitcoinCashAddressEntries = importDraft.watchOnlyEntries(from: importDraft.bitcoinCashAddressInput)
        let typedBitcoinCashAddress = importDraft.bitcoinCashAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let bitcoinSVAddressEntries = importDraft.watchOnlyEntries(from: importDraft.bitcoinSVAddressInput)
        let typedBitcoinSVAddress = importDraft.bitcoinSVAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let litecoinAddressEntries = importDraft.watchOnlyEntries(from: importDraft.litecoinAddressInput)
        let typedLitecoinAddress = importDraft.litecoinAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let dogecoinAddressEntries = importDraft.watchOnlyEntries(from: importDraft.dogecoinAddressInput)
        let typedDogecoinAddress = importDraft.dogecoinAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let ethereumAddressEntries = importDraft.watchOnlyEntries(from: importDraft.ethereumAddressInput)
        let typedEthereumAddress = importDraft.ethereumAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let tronAddressEntries = importDraft.watchOnlyEntries(from: importDraft.tronAddressInput)
        let typedTronAddress = importDraft.tronAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let solanaAddressEntries = importDraft.watchOnlyEntries(from: importDraft.solanaAddressInput)
        let typedSolanaAddress = importDraft.solanaAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let xrpAddressEntries = importDraft.watchOnlyEntries(from: importDraft.xrpAddressInput)
        let typedXRPAddress = importDraft.xrpAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stellarAddressEntries = importDraft.watchOnlyEntries(from: importDraft.stellarAddressInput)
        let typedStellarAddress = importDraft.stellarAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedMoneroAddress = importDraft.moneroAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardanoAddressEntries = importDraft.watchOnlyEntries(from: importDraft.cardanoAddressInput)
        let typedCardanoAddress = importDraft.cardanoAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let suiAddressEntries = importDraft.watchOnlyEntries(from: importDraft.suiAddressInput)
        let typedSuiAddress = importDraft.suiAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let aptosAddressEntries = importDraft.watchOnlyEntries(from: importDraft.aptosAddressInput)
        let typedAptosAddress = importDraft.aptosAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let tonAddressEntries = importDraft.watchOnlyEntries(from: importDraft.tonAddressInput)
        let typedTonAddress = importDraft.tonAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let icpAddressEntries = importDraft.watchOnlyEntries(from: importDraft.icpAddressInput)
        let typedICPAddress = importDraft.icpAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let nearAddressEntries = importDraft.watchOnlyEntries(from: importDraft.nearAddressInput)
        let typedNearAddress = importDraft.nearAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let polkadotAddressEntries = importDraft.watchOnlyEntries(from: importDraft.polkadotAddressInput)
        let typedPolkadotAddress = importDraft.polkadotAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsBitcoinImport = importDraft.wantsBitcoin
        let wantsBitcoinCashImport = importDraft.wantsBitcoinCash
        let wantsBitcoinSVImport = importDraft.wantsBitcoinSV
        let wantsLitecoinImport = importDraft.wantsLitecoin
        let wantsDogecoinImport = importDraft.wantsDogecoin
        let wantsEthereumImport = importDraft.wantsEthereum
        let wantsEthereumClassicImport = importDraft.wantsEthereumClassic
        let wantsArbitrumImport = importDraft.wantsArbitrum
        let wantsOptimismImport = importDraft.wantsOptimism
        let wantsBNBImport = importDraft.wantsBNBChain
        let wantsAvalancheImport = importDraft.wantsAvalanche
        let wantsHyperliquidImport = importDraft.wantsHyperliquid
        let wantsTronImport = importDraft.wantsTron
        let wantsSolanaImport = importDraft.wantsSolana
        let wantsCardanoImport = importDraft.wantsCardano
        let wantsXRPImport = importDraft.wantsXRP
        let wantsStellarImport = importDraft.wantsStellar
        let wantsMoneroImport = importDraft.wantsMonero
        let wantsSuiImport = importDraft.wantsSui
        let wantsAptosImport = importDraft.wantsAptos
        let wantsTONImport = importDraft.wantsTON
        let wantsICPImport = importDraft.wantsICP
        let wantsNearImport = importDraft.wantsNear
        let wantsPolkadotImport = importDraft.wantsPolkadot
        let selectedDerivationPreset = importDraft.seedDerivationPreset
        let selectedDerivationPaths: SeedDerivationPaths = {
            var paths = importDraft.seedDerivationPaths
            paths.isCustomEnabled = true
            return paths
        }()
        let isWatchOnlyImport = importDraft.isWatchOnlyMode
        let isPrivateKeyImport = importDraft.isPrivateKeyImportMode
        let selectedChainNames = importDraft.selectedChainNames
        let defaultWalletNameStartIndex = nextDefaultWalletNameIndex()
        var importedWalletsForRefresh: [ImportedWallet] = []
        guard let primarySelectedChainName = selectedChainNames.first else {
            importError = "Select a chain first."
            return
        }
        let requiresSeedPhrase = (wantsBitcoinImport || wantsBitcoinCashImport || wantsBitcoinSVImport || wantsLitecoinImport || wantsDogecoinImport || wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport || wantsTronImport || wantsSolanaImport || wantsCardanoImport || wantsXRPImport || wantsStellarImport || wantsMoneroImport || wantsSuiImport || wantsAptosImport || wantsTONImport || wantsICPImport || wantsNearImport || wantsPolkadotImport) && !isWatchOnlyImport && !isPrivateKeyImport
        let resolvedBitcoinAddress: String? = wantsBitcoinImport ? (trimmedBitcoinAddress.isEmpty ? nil : trimmedBitcoinAddress) : nil
        let resolvedBitcoinXPub: String? = wantsBitcoinImport ? (trimmedBitcoinXPub.isEmpty ? nil : trimmedBitcoinXPub) : nil
        let resolvedBitcoinCashAddress: String? = wantsBitcoinCashImport ? (typedBitcoinCashAddress.isEmpty ? nil : typedBitcoinCashAddress) : nil
        let resolvedBitcoinSVAddress: String? = wantsBitcoinSVImport ? (typedBitcoinSVAddress.isEmpty ? nil : typedBitcoinSVAddress) : nil
        let resolvedLitecoinAddress: String? = wantsLitecoinImport ? (typedLitecoinAddress.isEmpty ? nil : typedLitecoinAddress) : nil
        let resolvedTronAddress: String? = wantsTronImport ? (typedTronAddress.isEmpty ? nil : typedTronAddress) : nil
        let resolvedSolanaAddress: String? = wantsSolanaImport ? (typedSolanaAddress.isEmpty ? nil : typedSolanaAddress) : nil
        let resolvedXRPAddress: String? = wantsXRPImport ? (typedXRPAddress.isEmpty ? nil : typedXRPAddress) : nil
        let resolvedStellarAddress: String? = wantsStellarImport ? (typedStellarAddress.isEmpty ? nil : typedStellarAddress) : nil
        let resolvedMoneroAddress: String? = wantsMoneroImport ? (typedMoneroAddress.isEmpty ? nil : typedMoneroAddress) : nil
        let resolvedCardanoAddress: String? = wantsCardanoImport ? (typedCardanoAddress.isEmpty ? nil : typedCardanoAddress) : nil
        let resolvedSuiAddress: String? = wantsSuiImport ? (typedSuiAddress.isEmpty ? nil : typedSuiAddress) : nil
        let resolvedAptosAddress: String? = wantsAptosImport ? (typedAptosAddress.isEmpty ? nil : typedAptosAddress) : nil
        let resolvedTONAddress: String? = wantsTONImport ? (typedTonAddress.isEmpty ? nil : typedTonAddress) : nil
        let resolvedICPAddress: String? = wantsICPImport ? (typedICPAddress.isEmpty ? nil : typedICPAddress) : nil
        let resolvedNearAddress: String? = wantsNearImport ? (typedNearAddress.isEmpty ? nil : typedNearAddress) : nil
        let resolvedPolkadotAddress: String? = wantsPolkadotImport ? (typedPolkadotAddress.isEmpty ? nil : typedPolkadotAddress) : nil
        if isPrivateKeyImport {
            guard PrivateKeyHex.isLikely(trimmedPrivateKey) else {
                importError = "Enter a valid 32-byte hex key."
                return
            }
            let unsupportedPrivateKeyChains = selectedChainNames.filter { !["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "Cardano", "XRP Ledger", "Stellar", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot"].contains($0) }
            guard unsupportedPrivateKeyChains.isEmpty else {
                importError = "Private key import currently supports every chain in this build except Monero."
                return
            }
            let derivedAddress = derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName)
            guard derivedAddress.bitcoin != nil || derivedAddress.bitcoinCash != nil || derivedAddress.bitcoinSV != nil || derivedAddress.litecoin != nil || derivedAddress.dogecoin != nil || derivedAddress.evm != nil || derivedAddress.tron != nil || derivedAddress.solana != nil || derivedAddress.xrp != nil || derivedAddress.stellar != nil || derivedAddress.cardano != nil || derivedAddress.sui != nil || derivedAddress.aptos != nil || derivedAddress.ton != nil || derivedAddress.icp != nil || derivedAddress.near != nil || derivedAddress.polkadot != nil else {
                importError = "Unable to derive an address from this key."
                return
            }}
        if isWatchOnlyImport && wantsBitcoinImport {
            let hasValidAddress = !bitcoinAddressEntries.isEmpty
                && bitcoinAddressEntries.allSatisfy { AddressValidation.isValidBitcoinAddress($0, networkMode: self.bitcoinNetworkMode) }
            let hasValidXPub = resolvedBitcoinXPub.map { $0.hasPrefix("xpub") || $0.hasPrefix("ypub") || $0.hasPrefix("zpub") } ?? false
            if !hasValidAddress && !hasValidXPub {
                importError = "Enter one valid Bitcoin address per line or a valid xpub/zpub for watched addresses."
                return
            }}
        if wantsMoneroImport {
            if (resolvedMoneroAddress?.isEmpty ?? true) || !AddressValidation.isValidMoneroAddress(resolvedMoneroAddress ?? "") {
                importError = localizedStoreString("Enter a valid Monero address.")
                return
            }
            if isWatchOnlyImport {
                importError = "Monero watched addresses are not supported in this build."
                return
            }}
        if wantsCardanoImport && !isWatchOnlyImport {
            if let resolvedCardanoAddress, !resolvedCardanoAddress.isEmpty, !AddressValidation.isValidCardanoAddress(resolvedCardanoAddress) {
                importError = localizedStoreString("Enter a valid Cardano address.")
                return
            }}
        if isWatchOnlyImport {
            let watchOnlyValidations: [(Bool, [String], (String) -> Bool, String)] = [
                (wantsBitcoinCashImport, bitcoinCashAddressEntries, AddressValidation.isValidBitcoinCashAddress,    "Bitcoin Cash address"), (wantsBitcoinSVImport,   bitcoinSVAddressEntries,   AddressValidation.isValidBitcoinSVAddress,      "Bitcoin SV address"), (wantsLitecoinImport,    litecoinAddressEntries,    AddressValidation.isValidLitecoinAddress,        "Litecoin address"), (wantsDogecoinImport,    dogecoinAddressEntries,    { self.isValidDogecoinAddressForPolicy($0) },    "Dogecoin address"), (wantsTronImport,        tronAddressEntries,        AddressValidation.isValidTronAddress,            "Tron address"), (wantsSolanaImport,      solanaAddressEntries,      AddressValidation.isValidSolanaAddress,          "Solana address"), (wantsXRPImport,         xrpAddressEntries,         AddressValidation.isValidXRPAddress,             "XRP address"), (wantsStellarImport,     stellarAddressEntries,     AddressValidation.isValidStellarAddress,         "Stellar address"), (wantsCardanoImport,     cardanoAddressEntries,     AddressValidation.isValidCardanoAddress,         "Cardano address"), (wantsSuiImport,         suiAddressEntries,         AddressValidation.isValidSuiAddress,             "Sui address"), (wantsAptosImport,       aptosAddressEntries,       AddressValidation.isValidAptosAddress,           "Aptos address"), (wantsTONImport,         tonAddressEntries,         AddressValidation.isValidTONAddress,             "TON address"), (wantsICPImport,         icpAddressEntries,         AddressValidation.isValidICPAddress,             "Internet Computer account identifier"), (wantsNearImport,        nearAddressEntries,        AddressValidation.isValidNearAddress,            "NEAR address"), (wantsPolkadotImport,    polkadotAddressEntries,    AddressValidation.isValidPolkadotAddress,        "Polkadot address"), ]
            for (wantsImport, entries, validator, name) in watchOnlyValidations where wantsImport {
                if entries.isEmpty || !entries.allSatisfy(validator) {
                    importError = "Enter one valid \(name) per line for watched addresses."
                    return
                }}}
        if isWatchOnlyImport && (wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport) {
            if ethereumAddressEntries.isEmpty || !ethereumAddressEntries.allSatisfy(AddressValidation.isValidEthereumAddress) {
                importError = "Enter one valid EVM address per line for watched addresses."
                return
            }}
        if editingWalletID == nil {
            let bitcoinCashAddress: String? let bitcoinSVAddress: String? let litecoinAddress: String? let dogecoinAddress: String? let ethereumAddress: String? let ethereumClassicAddress: String? let tronAddress: String? let solanaAddress: String? let xrpAddress: String? let stellarAddress: String? let moneroAddress: String? let cardanoAddress: String? let suiAddress: String? let aptosAddress: String? let tonAddress: String? let icpAddress: String? let nearAddress: String? let polkadotAddress: String? let derivedBitcoinAddress: String? let createdWalletIDs = selectedChainNames.map { _ in UUID() }
            let bitcoinWalletID = zip(selectedChainNames, createdWalletIDs)..first(where: { $0.0 == "Bitcoin" })? .1
            if requiresSeedPhrase {
                var chainPaths: [String: String] = [:]
                if wantsBitcoinImport       { chainPaths["Bitcoin"]           = selectedDerivationPaths.bitcoin }
                if wantsBitcoinCashImport   { chainPaths["Bitcoin Cash"]      = selectedDerivationPaths.bitcoinCash }
                if wantsBitcoinSVImport     { chainPaths["Bitcoin SV"]        = selectedDerivationPaths.bitcoinSV }
                if wantsLitecoinImport      { chainPaths["Litecoin"]          = selectedDerivationPaths.litecoin }
                if wantsDogecoinImport      { chainPaths["Dogecoin"]          = selectedDerivationPaths.dogecoin }
                let needsEvm = wantsEthereumImport || wantsArbitrumImport || wantsOptimismImport
                    || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport
                if needsEvm                 { chainPaths["Ethereum"]          = selectedDerivationPaths.ethereum }
                if wantsEthereumClassicImport { chainPaths["Ethereum Classic"] = selectedDerivationPaths.ethereumClassic }
                if wantsTronImport          { chainPaths["Tron"]              = selectedDerivationPaths.tron }
                if wantsSolanaImport        { chainPaths["Solana"]            = selectedDerivationPaths.solana }
                if wantsCardanoImport       { chainPaths["Cardano"]           = selectedDerivationPaths.cardano }
                if wantsXRPImport           { chainPaths["XRP Ledger"]        = selectedDerivationPaths.xrp }
                if wantsStellarImport       { chainPaths["Stellar"]           = selectedDerivationPaths.stellar }
                if wantsSuiImport           { chainPaths["Sui"]               = selectedDerivationPaths.sui }
                if wantsAptosImport         { chainPaths["Aptos"]             = selectedDerivationPaths.aptos }
                if wantsTONImport           { chainPaths["TON"]               = selectedDerivationPaths.ton }
                if wantsICPImport           { chainPaths["Internet Computer"] = selectedDerivationPaths.internetComputer }
                if wantsNearImport          { chainPaths["NEAR"]              = selectedDerivationPaths.near }
                if wantsPolkadotImport      { chainPaths["Polkadot"]          = selectedDerivationPaths.polkadot }
                do {
                    let derived = try WalletRustDerivationBridge.deriveAllAddresses(
                        seedPhrase: trimmedSeedPhrase, chainPaths: chainPaths
                    )
                    if wantsBitcoinImport {
                        guard let bitcoinWalletID else {
                            importError = "Bitcoin wallet initialization failed."
                            return
                        }
                        _ = bitcoinWalletID
                    }
                    derivedBitcoinAddress    = derived["Bitcoin"]
                    bitcoinCashAddress       = derived["Bitcoin Cash"]
                    bitcoinSVAddress         = derived["Bitcoin SV"]
                    litecoinAddress          = derived["Litecoin"]
                    dogecoinAddress          = derived["Dogecoin"]
                    ethereumAddress          = derived["Ethereum"]
                    ethereumClassicAddress   = derived["Ethereum Classic"]
                    tronAddress              = derived["Tron"]
                    solanaAddress            = derived["Solana"]
                    cardanoAddress           = derived["Cardano"]
                    xrpAddress               = derived["XRP Ledger"]
                    stellarAddress           = derived["Stellar"]
                    suiAddress               = derived["Sui"]
                    aptosAddress             = derived["Aptos"]
                    tonAddress               = derived["TON"]
                    icpAddress               = derived["Internet Computer"]
                    nearAddress              = derived["NEAR"]
                    polkadotAddress          = derived["Polkadot"]
                    moneroAddress            = resolvedMoneroAddress
                } catch {
                    let resolvedMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    if resolvedMessage.isEmpty || resolvedMessage == "(null)" { importError = "Wallet initialization failed. Check the seed phrase." } else { importError = resolvedMessage }
                    return
                }
            } else {
                let derivedPrivateKeyAddress = isPrivateKeyImport ? derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName) : PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
                derivedBitcoinAddress = derivedPrivateKeyAddress.bitcoin
                bitcoinCashAddress = derivedPrivateKeyAddress.bitcoinCash ?? (AddressValidation.isValidBitcoinCashAddress(typedBitcoinCashAddress) ? typedBitcoinCashAddress : nil)
                bitcoinSVAddress = derivedPrivateKeyAddress.bitcoinSV ?? (AddressValidation.isValidBitcoinSVAddress(typedBitcoinSVAddress) ? typedBitcoinSVAddress : nil)
                litecoinAddress = derivedPrivateKeyAddress.litecoin ?? (AddressValidation.isValidLitecoinAddress(typedLitecoinAddress) ? typedLitecoinAddress : nil)
                dogecoinAddress = derivedPrivateKeyAddress.dogecoin ?? (isValidDogecoinAddressForPolicy(typedDogecoinAddress) ? typedDogecoinAddress : nil)
                ethereumAddress = derivedPrivateKeyAddress.evm ?? (AddressValidation.isValidEthereumAddress(typedEthereumAddress) ? normalizeEVMAddress(typedEthereumAddress) : nil)
                ethereumClassicAddress = ethereumAddress
                tronAddress = derivedPrivateKeyAddress.tron ?? (AddressValidation.isValidTronAddress(typedTronAddress) ? typedTronAddress : nil)
                solanaAddress = derivedPrivateKeyAddress.solana ?? (AddressValidation.isValidSolanaAddress(typedSolanaAddress) ? typedSolanaAddress : nil)
                xrpAddress = derivedPrivateKeyAddress.xrp ?? (AddressValidation.isValidXRPAddress(typedXRPAddress) ? typedXRPAddress : nil)
                stellarAddress = derivedPrivateKeyAddress.stellar ?? (AddressValidation.isValidStellarAddress(typedStellarAddress) ? typedStellarAddress : nil)
                moneroAddress = AddressValidation.isValidMoneroAddress(typedMoneroAddress) ? typedMoneroAddress : nil
                cardanoAddress = derivedPrivateKeyAddress.cardano ?? (AddressValidation.isValidCardanoAddress(typedCardanoAddress) ? typedCardanoAddress : nil)
                suiAddress = derivedPrivateKeyAddress.sui ?? (AddressValidation.isValidSuiAddress(typedSuiAddress) ? typedSuiAddress.lowercased() : nil)
                aptosAddress = derivedPrivateKeyAddress.aptos ?? (AddressValidation.isValidAptosAddress(typedAptosAddress) ? normalizedAddress(typedAptosAddress, for: "Aptos") : nil)
                tonAddress = derivedPrivateKeyAddress.ton ?? (AddressValidation.isValidTONAddress(typedTonAddress) ? normalizedAddress(typedTonAddress, for: "TON") : nil)
                icpAddress = derivedPrivateKeyAddress.icp ?? (AddressValidation.isValidICPAddress(typedICPAddress) ? normalizedAddress(typedICPAddress, for: "Internet Computer") : nil)
                nearAddress = derivedPrivateKeyAddress.near ?? (AddressValidation.isValidNearAddress(typedNearAddress) ? typedNearAddress.lowercased() : nil)
                polkadotAddress = derivedPrivateKeyAddress.polkadot ?? (AddressValidation.isValidPolkadotAddress(typedPolkadotAddress) ? typedPolkadotAddress : nil)
            }
            let plannedWalletIDs: [UUID]
            if isWatchOnlyImport {
                let watchOnlyWalletCount: Int = {
                    switch primarySelectedChainName {
                    case "Bitcoin": if let resolvedBitcoinXPub, !resolvedBitcoinXPub.isEmpty { return 1 }
                        return bitcoinAddressEntries.count
                    case "Bitcoin Cash": return bitcoinCashAddressEntries.count
                    case "Bitcoin SV": return bitcoinSVAddressEntries.count
                    case "Litecoin": return litecoinAddressEntries.count
                    case "Dogecoin": return dogecoinAddressEntries.count
                    case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return ethereumAddressEntries.count
                    case "Tron": return tronAddressEntries.count
                    case "Solana": return solanaAddressEntries.count
                    case "XRP Ledger": return xrpAddressEntries.count
                    case "Stellar": return stellarAddressEntries.count
                    case "Cardano": return cardanoAddressEntries.count
                    case "Sui": return suiAddressEntries.count
                    case "Aptos": return aptosAddressEntries.count
                    case "TON": return tonAddressEntries.count
                    case "Internet Computer": return icpAddressEntries.count
                    case "NEAR": return nearAddressEntries.count
                    case "Polkadot": return polkadotAddressEntries.count
                    default: return 0
                    }}()
                guard watchOnlyWalletCount > 0 else {
                    importError = "Enter at least one valid address to import."
                    return
                }
                plannedWalletIDs = (0..<watchOnlyWalletCount).map { _ in UUID() }
            } else {
                plannedWalletIDs = selectedChainNames.map { _ in UUID() }}
            let importPlanRequest = WalletRustImportPlanRequest(
                walletName: trimmedWalletName, defaultWalletNameStartIndex: defaultWalletNameStartIndex, primarySelectedChainName: primarySelectedChainName, selectedChainNames: selectedChainNames, plannedWalletIDs: plannedWalletIDs.map(\.uuidString), isWatchOnlyImport: isWatchOnlyImport, isPrivateKeyImport: isPrivateKeyImport, hasWalletPassword: trimmedWalletPassword != nil, resolvedAddresses: WalletRustImportAddresses(
                    bitcoinAddress: resolvedBitcoinAddress ?? derivedBitcoinAddress, bitcoinXpub: resolvedBitcoinXPub, bitcoinCashAddress: resolvedBitcoinCashAddress ?? bitcoinCashAddress, bitcoinSVAddress: resolvedBitcoinSVAddress ?? bitcoinSVAddress, litecoinAddress: resolvedLitecoinAddress ?? litecoinAddress, dogecoinAddress: dogecoinAddress, ethereumAddress: ethereumAddress, ethereumClassicAddress: ethereumClassicAddress, tronAddress: resolvedTronAddress ?? tronAddress, solanaAddress: resolvedSolanaAddress ?? solanaAddress, xrpAddress: resolvedXRPAddress ?? xrpAddress, stellarAddress: resolvedStellarAddress ?? stellarAddress, moneroAddress: resolvedMoneroAddress ?? moneroAddress, cardanoAddress: resolvedCardanoAddress ?? cardanoAddress, suiAddress: resolvedSuiAddress ?? suiAddress, aptosAddress: resolvedAptosAddress ?? aptosAddress, tonAddress: resolvedTONAddress ?? tonAddress, icpAddress: resolvedICPAddress ?? icpAddress, nearAddress: resolvedNearAddress ?? nearAddress, polkadotAddress: resolvedPolkadotAddress ?? polkadotAddress
                ), watchOnlyEntries: WalletRustWatchOnlyEntries(
                    bitcoinAddresses: bitcoinAddressEntries, bitcoinXpub: resolvedBitcoinXPub, bitcoinCashAddresses: bitcoinCashAddressEntries, bitcoinSVAddresses: bitcoinSVAddressEntries, litecoinAddresses: litecoinAddressEntries, dogecoinAddresses: dogecoinAddressEntries, ethereumAddresses: ethereumAddressEntries.map { normalizeEVMAddress($0) }, tronAddresses: tronAddressEntries, solanaAddresses: solanaAddressEntries, xrpAddresses: xrpAddressEntries, stellarAddresses: stellarAddressEntries, cardanoAddresses: cardanoAddressEntries, suiAddresses: suiAddressEntries.map { $0.lowercased() }, aptosAddresses: aptosAddressEntries.map { normalizedAddress($0, for: "Aptos") }, tonAddresses: tonAddressEntries.map { normalizedAddress($0, for: "TON") }, icpAddresses: icpAddressEntries.map { normalizedAddress($0, for: "Internet Computer") }, nearAddresses: nearAddressEntries.map { $0.lowercased() }, polkadotAddresses: polkadotAddressEntries
                )
            )
            let importPlan: WalletRustImportPlan
            do {
                importPlan = try WalletRustAppCoreBridge.planWalletImport(importPlanRequest)
            } catch {
                importError = error.localizedDescription
                return
            }
            let createdWallets: [ImportedWallet] = importPlan.wallets.compactMap { plannedWallet in
                guard let walletID = UUID(uuidString: plannedWallet.walletID) else { return nil }
                return walletForPlannedImport(
                    id: walletID, plan: plannedWallet, seedDerivationPreset: selectedDerivationPreset, seedDerivationPaths: selectedDerivationPaths, holdings: coins
                )
            }
            for instruction in importPlan.secretInstructions {
                guard let walletID = UUID(uuidString: instruction.walletID) else { continue }
                let account = resolvedSeedPhraseAccount(for: walletID)
                let passwordAccount = resolvedSeedPhrasePasswordAccount(for: walletID)
                let privateKeyAccount = resolvedPrivateKeyAccount(for: walletID)
                if instruction.shouldStoreSeedPhrase { try? SecureSeedStore.save(trimmedSeedPhrase, for: account) } else { try? SecureSeedStore.deleteValue(for: account) }
                if instruction.shouldStorePasswordVerifier, let trimmedWalletPassword { try? SecureSeedPasswordStore.save(trimmedWalletPassword, for: passwordAccount) } else { try? SecureSeedPasswordStore.deleteValue(for: passwordAccount) }
                if instruction.shouldStorePrivateKey { SecurePrivateKeyStore.save(trimmedPrivateKey, for: privateKeyAccount) } else { SecurePrivateKeyStore.deleteValue(for: privateKeyAccount) }}
            wallets.append(contentsOf: createdWallets)
            importedWalletsForRefresh = createdWallets
            for w in createdWallets {
                let summary: [String: Any] = [
                    "id": w.id.uuidString, "name": w.name, "isWatchOnly": false, "selectedChain": w.selectedChain, "includeInPortfolioTotal": w.includeInPortfolioTotal, "bitcoinNetworkMode": w.bitcoinNetworkMode.rawValue, "dogecoinNetworkMode": w.dogecoinNetworkMode.rawValue, "derivationPreset": w.seedDerivationPreset ?? "standard", "derivationPaths": w.seedDerivationPaths ?? [:], "holdings": [], "addresses": []
                ]
                if let data = try? JSONSerialization.data(withJSONObject: summary), let json = String(data: data, encoding: .utf8) {
                    Task { try? await WalletServiceBridge.shared.upsertWalletJSON(json) }}}}
        finishWalletImportFlow()
        withAnimation {
        }
        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }
    func renameWallet(id: UUID, to newName: String) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        let wallet = wallets[index]
        wallets[index] = ImportedWallet(
            id: wallet.id, name: newName, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXPub: wallet.bitcoinXPub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSVAddress: wallet.bitcoinSVAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: wallet.holdings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
        finishWalletImportFlow()
    }
    func finishWalletImportFlow() {
        importError = nil
        importDraft.clearSensitiveInputs()
        resetImportForm()
        editingWalletID = nil
        isShowingWalletImporter = false
    }
    enum WalletImportSyncError: Error {
        case bitcoin
        case bitcoinCash
        case bitcoinSV
        case litecoin
        case dogecoin
        case ethereum
        case ethereumClassic
        case bnb
        case tron
        case solana
        case cardano
        case xrp
        case stellar
        case monero
        case sui
        case near
        case polkadot
    }
    struct PrivateKeyImportAddressResolution {
        let bitcoin: String? let bitcoinCash: String? let bitcoinSV: String? let litecoin: String? let dogecoin: String? static func only(bitcoin: String? = nil, bitcoinCash: String? = nil, bitcoinSV: String? = nil, litecoin: String? = nil, dogecoin: String? = nil, evm: String? = nil, tron: String? = nil, solana: String? = nil, xrp: String? = nil, stellar: String? = nil, cardano: String? = nil, sui: String? = nil, aptos: String? = nil, ton: String? = nil, icp: String? = nil, near: String? = nil, polkadot: String? = nil) -> Self { Self(bitcoin: bitcoin, bitcoinCash: bitcoinCash, bitcoinSV: bitcoinSV, litecoin: litecoin, dogecoin: dogecoin, evm: evm, tron: tron, solana: solana, xrp: xrp, stellar: stellar, cardano: cardano, sui: sui, aptos: aptos, ton: ton, icp: icp, near: near, polkadot: polkadot) }
        let evm: String? let tron: String? let solana: String? let xrp: String? let stellar: String? let cardano: String? let sui: String? let aptos: String? let ton: String? let icp: String? let near: String? let polkadot: String? }
    func derivePrivateKeyImportAddress(privateKeyHex: String, chainName: String?) -> PrivateKeyImportAddressResolution {
        guard let chainName else { return .only() }
        switch chainName {
        case "Bitcoin": return .only(bitcoin: try? SeedPhraseAddressDerivation.bitcoinAddress(forPrivateKey: privateKeyHex))
        case "Bitcoin Cash": return .only(bitcoinCash: try? SeedPhraseAddressDerivation.bitcoinCashAddress(forPrivateKey: privateKeyHex))
        case "Bitcoin SV": return .only(bitcoinSV: try? SeedPhraseAddressDerivation.bitcoinSVAddress(forPrivateKey: privateKeyHex))
        case "Litecoin": return .only(litecoin: try? SeedPhraseAddressDerivation.litecoinAddress(forPrivateKey: privateKeyHex))
        case "Dogecoin": return .only(dogecoin: try? SeedPhraseAddressDerivation.dogecoinAddress(forPrivateKey: privateKeyHex))
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return .only(evm: try? SeedPhraseAddressDerivation.evmAddress(forPrivateKey: privateKeyHex))
        case "Tron": return .only(tron: try? SeedPhraseAddressDerivation.tronAddress(forPrivateKey: privateKeyHex))
        case "Solana": return .only(solana: try? SeedPhraseAddressDerivation.solanaAddress(forPrivateKey: privateKeyHex))
        case "XRP Ledger": return .only(xrp: try? SeedPhraseAddressDerivation.xrpAddress(forPrivateKey: privateKeyHex))
        case "Stellar": return .only(stellar: try? SeedPhraseAddressDerivation.stellarAddress(forPrivateKey: privateKeyHex))
        case "Cardano": return .only(cardano: try? SeedPhraseAddressDerivation.cardanoAddress(forPrivateKey: privateKeyHex))
        case "Sui": return .only(sui: try? SeedPhraseAddressDerivation.suiAddress(forPrivateKey: privateKeyHex))
        case "Aptos": return .only(aptos: try? SeedPhraseAddressDerivation.aptosAddress(forPrivateKey: privateKeyHex))
        case "TON": return .only(ton: try? SeedPhraseAddressDerivation.tonAddress(forPrivateKey: privateKeyHex))
        case "Internet Computer": return .only(icp: try? SeedPhraseAddressDerivation.icpAddress(forPrivateKey: privateKeyHex))
        case "NEAR": return .only(near: try? SeedPhraseAddressDerivation.nearAddress(forPrivateKey: privateKeyHex))
        case "Polkadot": return .only(polkadot: try? SeedPhraseAddressDerivation.polkadotAddress(forPrivateKey: privateKeyHex))
        default: return .only()
        }}
    static func deriveSeedPhraseAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String) throws -> String {
        let result = try WalletDerivationLayer.derive(
            seedPhrase: seedPhrase, request: WalletDerivationRequest(
                chain: chain, network: network, derivationPath: derivationPath, curve: WalletDerivationEngine.curve(for: chain), requestedOutputs: [.address]
            )
        )
        guard let address = result.address else { throw WalletDerivationEngineError.emptyRequestedOutputs }
        return address
    }
    func deriveSeedPhraseAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String) throws -> String { try Self.deriveSeedPhraseAddress(seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath) }
    func derivationNetwork(for chain: SeedDerivationChain, wallet: ImportedWallet? = nil) -> WalletDerivationNetwork {
        switch chain {
        case .bitcoin: return derivationNetwork(for: wallet.map(bitcoinNetworkMode(for:)) ?? bitcoinNetworkMode)
        case .dogecoin: return derivationNetwork(for: wallet.map(dogecoinNetworkMode(for:)) ?? dogecoinNetworkMode)
        default: return .mainnet
        }}
    func derivationNetwork(for networkMode: BitcoinNetworkMode) -> WalletDerivationNetwork {
        switch networkMode {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .testnet4: return .testnet4
        case .signet: return .signet
        }}
    func derivationNetwork(for networkMode: DogecoinNetworkMode) -> WalletDerivationNetwork {
        switch networkMode {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        }}
    func utxoDiscoveryDerivationChain(for chainName: String) -> SeedDerivationChain? { ["Bitcoin": SeedDerivationChain.bitcoin, "Bitcoin Cash": .bitcoinCash, "Bitcoin SV": .bitcoinSV, "Litecoin": .litecoin, "Dogecoin": .dogecoin][chainName] }
    func walletDisplayName(baseName: String, batchPosition: Int, defaultWalletIndex: Int, selectedChainCount: Int) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Wallet \(defaultWalletIndex)" }
        return selectedChainCount > 1 ? "\(trimmed) \(batchPosition)" : trimmed
    }
    func nextDefaultWalletNameIndex() -> Int {
        let highestUsedIndex = wallets.reduce(into: 0) { currentHighest, wallet in
            guard wallet.name.hasPrefix("Wallet ") else { return }
            let suffix = wallet.name.dropFirst("Wallet ".count)
            guard let value = Int(suffix) else { return }
            currentHighest = max(currentHighest, value)
        }
        return highestUsedIndex + 1
    }
    func walletForSingleChain(id: UUID, name: String, chainName: String, bitcoinAddress: String?, bitcoinXPub: String?, bitcoinCashAddress: String?, bitcoinSVAddress: String?, litecoinAddress: String?, dogecoinAddress: String?, ethereumAddress: String?, tronAddress: String?, solanaAddress: String?, xrpAddress: String?, stellarAddress: String?, moneroAddress: String?, cardanoAddress: String?, suiAddress: String?, aptosAddress: String?, tonAddress: String?, icpAddress: String?, nearAddress: String?, polkadotAddress: String?, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths, holdings: [Coin]) -> ImportedWallet {
        ImportedWallet(
            id: id, name: name, bitcoinNetworkMode: chainName == "Bitcoin" ? bitcoinNetworkMode : .mainnet, dogecoinNetworkMode: chainName == "Dogecoin" ? dogecoinNetworkMode : .mainnet, bitcoinAddress: chainName == "Bitcoin" ? bitcoinAddress : nil, bitcoinXPub: chainName == "Bitcoin" ? bitcoinXPub : nil, bitcoinCashAddress: chainName == "Bitcoin Cash" ? bitcoinCashAddress : nil, bitcoinSVAddress: chainName == "Bitcoin SV" ? bitcoinSVAddress : nil, litecoinAddress: chainName == "Litecoin" ? litecoinAddress : nil, dogecoinAddress: chainName == "Dogecoin" ? dogecoinAddress : nil, ethereumAddress: (chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid") ? ethereumAddress : nil, tronAddress: chainName == "Tron" ? tronAddress : nil, solanaAddress: chainName == "Solana" ? solanaAddress : nil, stellarAddress: chainName == "Stellar" ? stellarAddress : nil, xrpAddress: chainName == "XRP Ledger" ? xrpAddress : nil, moneroAddress: chainName == "Monero" ? moneroAddress : nil, cardanoAddress: chainName == "Cardano" ? cardanoAddress : nil, suiAddress: chainName == "Sui" ? suiAddress : nil, aptosAddress: chainName == "Aptos" ? aptosAddress : nil, tonAddress: chainName == "TON" ? tonAddress : nil, icpAddress: chainName == "Internet Computer" ? icpAddress : nil, nearAddress: chainName == "NEAR" ? nearAddress : nil, polkadotAddress: chainName == "Polkadot" ? polkadotAddress : nil, seedDerivationPreset: seedDerivationPreset, seedDerivationPaths: seedDerivationPaths, selectedChain: chainName, holdings: holdings.filter { $0.chainName == chainName }
        )
    }
    func walletForPlannedImport(id: UUID, plan: WalletRustPlannedWallet, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths, holdings: [Coin]) -> ImportedWallet {
        walletForSingleChain(
            id: id, name: plan.name, chainName: plan.chainName, bitcoinAddress: plan.addresses.bitcoinAddress, bitcoinXPub: plan.addresses.bitcoinXpub, bitcoinCashAddress: plan.addresses.bitcoinCashAddress, bitcoinSVAddress: plan.addresses.bitcoinSVAddress, litecoinAddress: plan.addresses.litecoinAddress, dogecoinAddress: plan.addresses.dogecoinAddress, ethereumAddress: plan.chainName == "Ethereum Classic"
                ? (plan.addresses.ethereumClassicAddress ?? plan.addresses.ethereumAddress)
                : plan.addresses.ethereumAddress, tronAddress: plan.addresses.tronAddress, solanaAddress: plan.addresses.solanaAddress, xrpAddress: plan.addresses.xrpAddress, stellarAddress: plan.addresses.stellarAddress, moneroAddress: plan.addresses.moneroAddress, cardanoAddress: plan.addresses.cardanoAddress, suiAddress: plan.addresses.suiAddress, aptosAddress: plan.addresses.aptosAddress, tonAddress: plan.addresses.tonAddress, icpAddress: plan.addresses.icpAddress, nearAddress: plan.addresses.nearAddress, polkadotAddress: plan.addresses.polkadotAddress, seedDerivationPreset: seedDerivationPreset, seedDerivationPaths: seedDerivationPaths, holdings: holdings
        )
    }
    func hydrateImportedWalletBalances(wallet: ImportedWallet, seedPhrase: String, wantsBitcoinImport: Bool, wantsBitcoinCashImport: Bool, wantsBitcoinSVImport: Bool, wantsLitecoinImport: Bool, wantsDogecoinImport: Bool, wantsEthereumImport: Bool, wantsEthereumClassicImport: Bool, wantsBNBImport: Bool, wantsTronImport: Bool, wantsSolanaImport: Bool, wantsCardanoImport: Bool, wantsXRPImport: Bool, wantsStellarImport: Bool, wantsMoneroImport: Bool, wantsNearImport: Bool, wantsPolkadotImport: Bool) async throws -> ImportedWallet {
        async let bitcoinBalanceTask: Double? = fetchBitcoinImportBalanceIfNeeded(
            wantsBitcoinImport, wallet: wallet, seedPhrase: seedPhrase
        )
        async let bitcoinCashBalanceTask: Double? = fetchBitcoinCashImportBalanceIfNeeded(
            wantsBitcoinCashImport, address: wallet.bitcoinCashAddress
        )
        async let bitcoinSVBalanceTask: Double? = fetchBitcoinSVImportBalanceIfNeeded(
            wantsBitcoinSVImport, address: wallet.bitcoinSVAddress
        )
        async let litecoinBalanceTask: Double? = fetchLitecoinImportBalanceIfNeeded(
            wantsLitecoinImport, address: wallet.litecoinAddress
        )
        async let dogecoinBalanceTask: Double? = fetchDogecoinImportBalanceIfNeeded(
            wantsDogecoinImport, address: wallet.dogecoinAddress
        )
        async let ethereumPortfolioTask: (Double, [EthereumTokenBalanceSnapshot])? = fetchEthereumImportPortfolioIfNeeded(
            wantsEthereumImport, address: wallet.ethereumAddress
        )
        async let ethereumClassicPortfolioTask: (Double, [EthereumTokenBalanceSnapshot])? = fetchETCImportBalanceIfNeeded(
            wantsEthereumClassicImport, address: wallet.ethereumAddress
        )
        async let bnbPortfolioTask: (Double, [EthereumTokenBalanceSnapshot])? = fetchBNBImportBalanceIfNeeded(wantsBNBImport, address: wallet.ethereumAddress)
        async let tronPortfolioTask: (Double, [TronTokenBalanceSnapshot])? = fetchTronImportBalanceIfNeeded(wantsTronImport, address: wallet.tronAddress)
        async let solanaPortfolioTask: SolanaPortfolioSnapshot? = fetchSolanaImportPortfolioIfNeeded(
            wantsSolanaImport, address: wallet.solanaAddress
        )
        async let cardanoBalanceTask: Double? = fetchCardanoImportBalanceIfNeeded(
            wantsCardanoImport, address: wallet.cardanoAddress
        )
        async let xrpBalanceTask: Double? = fetchXRPImportBalanceIfNeeded(wantsXRPImport, address: wallet.xrpAddress)
        async let stellarBalanceTask: Double? = fetchStellarImportBalanceIfNeeded(
            wantsStellarImport, address: wallet.stellarAddress
        )
        async let moneroBalanceTask: Double? = fetchMoneroImportBalanceIfNeeded(wantsMoneroImport, address: wallet.moneroAddress)
        async let nearBalanceTask: Double? = fetchNearImportBalanceIfNeeded(wantsNearImport, address: wallet.nearAddress)
        async let polkadotBalanceTask: Double? = fetchPolkadotImportBalanceIfNeeded(
            wantsPolkadotImport, address: wallet.polkadotAddress
        )
        func applyNative(_ chainId: UInt32, _ balance: Double?) {
            guard let balance, let coin = initialNativeHolding(chainId: chainId, amount: balance) else { return }
            updatedHoldings = mergeNativeHolding(coin, into: updatedHoldings)
        }
        var updatedHoldings = wallet.holdings
        do { applyNative(SpectraChainID.bitcoin,    try await bitcoinBalanceTask) }     catch { throw WalletImportSyncError.bitcoin }
        do { applyNative(SpectraChainID.bitcoinCash, try await bitcoinCashBalanceTask) } catch { throw WalletImportSyncError.bitcoinCash }
        do { applyNative(SpectraChainID.bitcoinSv,  try await bitcoinSVBalanceTask) }   catch { throw WalletImportSyncError.bitcoinSV }
        do { applyNative(SpectraChainID.litecoin,   try await litecoinBalanceTask) }    catch { throw WalletImportSyncError.litecoin }
        do { applyNative(SpectraChainID.dogecoin,   try await dogecoinBalanceTask) }    catch { throw WalletImportSyncError.dogecoin }
        do {
            if let (nativeBalance, tokens) = try await ethereumPortfolioTask {
                applyNative(SpectraChainID.ethereum, nativeBalance)
                updatedHoldings = applyEVMTokenHoldings(tokens, chainName: "Ethereum", trackedTokens: enabledEthereumTrackedTokens(), to: updatedHoldings)
            }
        } catch { throw WalletImportSyncError.ethereum }
        do {
            if let (nativeBalance, _) = try await ethereumClassicPortfolioTask { applyNative(SpectraChainID.ethereumClassic, nativeBalance) }
        } catch { throw WalletImportSyncError.ethereumClassic }
        do {
            if let (nativeBalance, tokens) = try await bnbPortfolioTask {
                applyNative(SpectraChainID.bsc, nativeBalance)
                updatedHoldings = applyEVMTokenHoldings(tokens, chainName: "BNB Chain", trackedTokens: enabledBNBTrackedTokens(), to: updatedHoldings)
            }
        } catch { throw WalletImportSyncError.bnb }
        do {
            if let (nativeBalance, tokens) = try await tronPortfolioTask { updatedHoldings = applyTronPortfolio(nativeBalance: nativeBalance, tokenBalances: tokens, to: updatedHoldings) }
        } catch { throw WalletImportSyncError.tron }
        do {
            if let solanaPortfolio = try await solanaPortfolioTask { updatedHoldings = applySolanaPortfolio(nativeBalance: solanaPortfolio.nativeBalance, tokenBalances: solanaPortfolio.tokenBalances, to: updatedHoldings) }
        } catch { throw WalletImportSyncError.solana }
        do { applyNative(SpectraChainID.cardano,  try await cardanoBalanceTask) }  catch { throw WalletImportSyncError.cardano }
        do { applyNative(SpectraChainID.xrp,      try await xrpBalanceTask) }      catch { throw WalletImportSyncError.xrp }
        do { applyNative(SpectraChainID.stellar,  try await stellarBalanceTask) }  catch { throw WalletImportSyncError.stellar }
        do { applyNative(SpectraChainID.monero,   try await moneroBalanceTask) }   catch { throw WalletImportSyncError.monero }
        do { applyNative(SpectraChainID.near,     try await nearBalanceTask) }     catch { throw WalletImportSyncError.near }
        do { applyNative(SpectraChainID.polkadot, try await polkadotBalanceTask) } catch { throw WalletImportSyncError.polkadot }
        return walletByReplacingHoldings(wallet, with: updatedHoldings)
    }
    func fetchBitcoinImportBalanceIfNeeded(_ shouldFetch: Bool, wallet: ImportedWallet, seedPhrase: String) async throws -> Double? {
        guard shouldFetch else { return nil }
        let xpub: String
        if let stored = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty { xpub = stored } else {
            xpub = try await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                mnemonicPhrase: seedPhrase, passphrase: "", accountPath: "m/84'/0'/0'"
            )
        }
        let balJSON = try await WalletServiceBridge.shared.fetchBitcoinXpubBalanceJSON(xpub: xpub)
        guard let data = balJSON.data(using: .utf8), let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let confirmedSats = obj["confirmed_sats"] as? UInt64 else { return nil }
        return Double(confirmedSats) / 100_000_000
    }
    private func fetchUInt64BalanceIfNeeded(_ shouldFetch: Bool, address: String?, chainId: UInt32, field: String, divisor: Double, missingError: WalletImportSyncError? = nil) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            if let err = missingError { throw err }
            return nil
        }
        let json = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: chainId, address: address)
        guard let raw = RustBalanceDecoder.uint64Field(field, from: json) else { return nil }
        return Double(raw) / divisor
    }
    func fetchBitcoinCashImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.bitcoinCash, field: "balance_sat", divisor: 1e8, missingError: .bitcoinCash) }
    func fetchBitcoinSVImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.bitcoinSv, field: "balance_sat", divisor: 1e8, missingError: .bitcoinSV) }
    func walletByReplacingHoldings(_ wallet: ImportedWallet, with holdings: [Coin]) -> ImportedWallet {
        ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXPub: wallet.bitcoinXPub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSVAddress: wallet.bitcoinSVAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: holdings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
    }
    func fetchDogecoinImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.dogecoin, field: "balance_koin", divisor: 1e8, missingError: .dogecoin) }
    func fetchLitecoinImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.litecoin, field: "balance_sat", divisor: 1e8, missingError: .litecoin) }
    func fetchEthereumImportPortfolioIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> (Double, [EthereumTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw WalletImportSyncError.ethereum }
        return try await fetchEthereumPortfolio(for: address)
    }
    private func fetchEVMNativeImportIfNeeded(_ shouldFetch: Bool, address: String?, error: WalletImportSyncError, chainName: String) async throws -> (Double, [EthereumTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw error }
        let p = try await fetchEVMNativePortfolio(for: address, chainName: chainName)
        return (p.nativeBalance, p.tokenBalances)
    }
    func fetchETCImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> (Double, [EthereumTokenBalanceSnapshot])? { try await fetchEVMNativeImportIfNeeded(shouldFetch, address: address, error: .ethereumClassic, chainName: "Ethereum Classic") }
    func fetchBNBImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> (Double, [EthereumTokenBalanceSnapshot])? { try await fetchEVMNativeImportIfNeeded(shouldFetch, address: address, error: .bnb, chainName: "BNB Chain") }
    func fetchTronImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> (Double, [TronTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw WalletImportSyncError.tron }
        let nativeJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.tron, address: address)
        let sun = RustBalanceDecoder.uint64Field("sun", from: nativeJSON) ?? 0
        let trxBalance = Double(sun) / 1e6
        let trackedTokens = enabledTronTrackedTokens()
        let tuples = trackedTokens.map { t in (contract: t.contractAddress, symbol: t.symbol, decimals: t.decimals) }
        var tokenBalances: [TronTokenBalanceSnapshot] = []
        if !tuples.isEmpty, let tokenJSON = try? await WalletServiceBridge.shared.fetchTokenBalancesJSON(chainId: SpectraChainID.tron, address: address, tokens: tuples), let tokenData = tokenJSON.data(using: .utf8), let tokenArr = try? JSONSerialization.jsonObject(with: tokenData) as? [[String: Any]] {
            tokenBalances = tokenArr.compactMap { obj in
                guard let contract = obj["contract"] as? String, let symbol = obj["symbol"] as? String, let displayStr = obj["balance_display"] as? String, let balance = Double(displayStr) else { return nil }
                return TronTokenBalanceSnapshot(symbol: symbol, contractAddress: contract, balance: balance)
            }}
        return (trxBalance, tokenBalances)
    }
    func fetchCardanoImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.cardano, field: "lovelace", divisor: 1_000_000) }
    func fetchXRPImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.xrp, field: "drops", divisor: 1_000_000) }
    func fetchStellarImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw WalletImportSyncError.stellar }
        let json = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.stellar, address: address)
        guard let stroops = RustBalanceDecoder.int64Field("stroops", from: json) else { return nil }
        return Double(stroops) / 10_000_000
    }
    func fetchMoneroImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? { try await fetchUInt64BalanceIfNeeded(shouldFetch, address: address, chainId: SpectraChainID.monero, field: "piconeros", divisor: 1_000_000_000_000, missingError: .monero) }
    func fetchNearImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw WalletImportSyncError.near }
        let json = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.near, address: address)
        guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let yoctoStr = obj["yocto_near"] as? String, let yocto = Double(yoctoStr) else { return nil }
        return yocto / 1e24
    }
    func fetchPolkadotImportBalanceIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw WalletImportSyncError.polkadot }
        let json = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.polkadot, address: address)
        guard let planck = RustBalanceDecoder.uint128StringField("planck", from: json) else { return nil }
        return planck / 10_000_000_000
    }
    func fetchSolanaImportPortfolioIfNeeded(_ shouldFetch: Bool, address: String?) async throws -> SolanaPortfolioSnapshot? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { throw WalletImportSyncError.solana }
        let nativeJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.solana, address: address)
        guard let lamports = RustBalanceDecoder.uint64Field("lamports", from: nativeJSON) else { throw WalletImportSyncError.solana }
        let nativeBalance = Double(lamports) / 1e9
        let trackedTokensByMint = enabledSolanaTrackedTokens()
        let tuples = trackedTokensByMint.map { mint, meta in (contract: mint, symbol: meta.symbol, decimals: meta.decimals) }
        var tokenBalances: [SolanaSPLTokenBalanceSnapshot] = []
        if !tuples.isEmpty, let tokenJSON = try? await WalletServiceBridge.shared.fetchTokenBalancesJSON(chainId: SpectraChainID.solana, address: address, tokens: tuples), let tokenData = tokenJSON.data(using: .utf8), let tokenArr = try? JSONSerialization.jsonObject(with: tokenData) as? [[String: Any]] {
            tokenBalances = tokenArr.compactMap { obj -> SolanaSPLTokenBalanceSnapshot? in
                guard let mint = obj["contract"] as? String, let displayStr = obj["balance_display"] as? String, let balance = Double(displayStr), balance > 0 else { return nil }
                let meta = trackedTokensByMint[mint]
                return SolanaSPLTokenBalanceSnapshot(
                    mintAddress: mint, sourceTokenAccountAddress: "", symbol: meta?.symbol ?? (obj["symbol"] as? String ?? ""), name: meta?.name ?? "", tokenStandard: "SPL", decimals: meta?.decimals ?? (obj["decimals"] as? Int ?? 0), balance: balance, marketDataID: meta?.marketDataID ?? "", coinGeckoID: meta?.coinGeckoID ?? ""
                )
            }}
        return SolanaPortfolioSnapshot(nativeBalance: nativeBalance, tokenBalances: tokenBalances)
    }
    var portfolio: [Coin] { cachedPortfolio }
    var priceRequestCoins: [Coin] {
        var grouped: [String: Coin] = [:]
        var order: [String] = []
        for coin in cachedUniqueWalletPriceRequestCoins where isPricedAsset(coin) {
            let key = activePriceKey(for: coin)
            grouped[key] = coin
            order.append(key)
        }
        for coin in dashboardPinnedAssetPricingPrototypes
        where selectedMainTab == .home && isPricedAsset(coin) {
            let key = activePriceKey(for: coin)
            guard grouped[key] == nil else { continue }
            grouped[key] = coin
            order.append(key)
        }
        return order.compactMap { grouped[$0] }}
    var hasLivePriceRefreshWork: Bool { !priceRequestCoins.isEmpty }
    var shouldRunScheduledPriceRefresh: Bool { selectedMainTab == .home && hasLivePriceRefreshWork }
    var hasPendingTransactionMaintenanceWork: Bool {
        transactions.contains { transaction in
            guard transaction.kind == .send, transaction.transactionHash != nil else { return false }
            if transaction.status == .pending { return true }
            return transaction.status == .confirmed
        }}
    var pendingTransactionMaintenanceChains: Set<String> {
        Set(
            transactions.compactMap { transaction -> String? in
                guard transaction.kind == .send, transaction.transactionHash != nil else { return nil }
                if transaction.status == .pending { return transaction.chainName }
                if transaction.chainName == "Dogecoin", transaction.status == .confirmed { return transaction.chainName }
                return nil
            }
        )
    }
    var pendingTransactionMaintenanceChainIDs: Set<WalletChainID> { Set(pendingTransactionMaintenanceChains.compactMap(WalletChainID.init)) }
    var refreshableChainNames: Set<String> { cachedRefreshableChainNames }
    var refreshableChainIDs: Set<WalletChainID> { Set(refreshableChainNames.compactMap(WalletChainID.init)) }
    var backgroundBalanceRefreshFrequencyMinutes: Int { max(automaticRefreshFrequencyMinutes * 3, 15) }
    func refreshForForegroundIfNeeded() async {
        guard shouldPerformForegroundFullRefresh else { return }
        await performUserInitiatedRefresh(forceChainRefresh: false)
    }
    var shouldPerformForegroundFullRefresh: Bool {
        guard userInitiatedRefreshTask == nil else { return false }
        guard let lastFullRefreshAt else { return true }
        return Date().timeIntervalSince(lastFullRefreshAt) >= Self.foregroundFullRefreshStalenessInterval
    }
    var includedPortfolioWallets: [ImportedWallet] { cachedIncludedPortfolioWallets }
    func currentPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        return livePrices[activePriceKey(for: coin)]
    }
    func currentOrFallbackPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        if let livePrice = currentPriceIfAvailable(for: coin) { return livePrice }
        guard coin.priceUSD > 0 else { return nil }
        return coin.priceUSD
    }
    func currentPrice(for coin: Coin) -> Double { currentPriceIfAvailable(for: coin) ?? 0 }
    func fiatRateIfAvailable(for currency: FiatCurrency) -> Double? {
        if currency == .usd { return 1.0 }
        guard let rate = fiatRatesFromUSD[currency.rawValue], rate > 0 else { return nil }
        return rate
    }
    func fiatRate(for currency: FiatCurrency) -> Double { fiatRateIfAvailable(for: currency) ?? (currency == .usd ? 1.0 : 0) }
    func persistAssetDisplayDecimalsByChain() { persistCodableToSQLite(assetDisplayDecimalsByChain, key: Self.assetDisplayDecimalsByChainDefaultsKey) }
}
