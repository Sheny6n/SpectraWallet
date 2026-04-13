import Combine
import Foundation
private enum HistoryChainID {
    static let bitcoin: UInt32     =  0
    static let ethereum: UInt32    =  1
    static let dogecoin: UInt32    =  3
    static let litecoin: UInt32    =  5
    static let bitcoinCash: UInt32 =  6
    static let tron: UInt32        =  7
    static let arbitrum: UInt32    = 11
    static let optimism: UInt32    = 12
    static let bitcoinSV: UInt32   = 22
    static let bnb: UInt32         = 23
    static let hyperliquid: UInt32 = 24
}
extension WalletStore {
    func historyPaginationExhausted(chainId: UInt32, walletId: UUID) -> Bool { (try? WalletServiceBridge.shared.isHistoryExhausted( chainId: chainId, walletId: walletId.uuidString)) ?? false }
    func historyPaginationCursor(chainId: UInt32, walletId: UUID) -> String? {
        try? WalletServiceBridge.shared.historyNextCursor(
            chainId: chainId, walletId: walletId.uuidString)
    }
    func historyPaginationPage(chainId: UInt32, walletId: UUID) -> Int { Int((try? WalletServiceBridge.shared.historyNextPage( chainId: chainId, walletId: walletId.uuidString)) ?? 0) }
    func setHistoryCursor(chainId: UInt32, walletId: UUID, cursor: String?) {
        try? WalletServiceBridge.shared.advanceHistoryCursor(
            chainId: chainId, walletId: walletId.uuidString, nextCursor: cursor)
        objectWillChange.send()
    }
    func setHistoryPage(chainId: UInt32, walletId: UUID, page: Int) {
        try? WalletServiceBridge.shared.setHistoryPage(
            chainId: chainId, walletId: walletId.uuidString, page: UInt32(max(0, page)))
        objectWillChange.send()
    }
    func markHistoryExhausted(chainId: UInt32, walletId: UUID) {
        try? WalletServiceBridge.shared.setHistoryExhausted(
            chainId: chainId, walletId: walletId.uuidString, exhausted: true)
        objectWillChange.send()
    }
    func markHistoryActive(chainId: UInt32, walletId: UUID) {
        try? WalletServiceBridge.shared.setHistoryExhausted(
            chainId: chainId, walletId: walletId.uuidString, exhausted: false)
        objectWillChange.send()
    }
    func resetHistoryPagination(chainId: UInt32, walletId: UUID) {
        try? WalletServiceBridge.shared.resetHistory(
            chainId: chainId, walletId: walletId.uuidString)
        objectWillChange.send()
    }
    func resetHistoryPaginationForWallet(_ walletId: UUID) {
        try? WalletServiceBridge.shared.resetHistoryForWallet(walletId: walletId.uuidString)
        objectWillChange.send()
    }
    func resetAllHistoryPagination() {
        try? WalletServiceBridge.shared.resetAllHistory()
        objectWillChange.send()
    }
}
// ────────────────────────────────────────────────────────────────────────────
// Normalized history fetch: a single function replaces all per-chain
// refresh methods for non-EVM, non-UTXO-HD chains.
// Rust normalizes the raw chain response; Swift maps it to TransactionRecord.
// ────────────────────────────────────────────────────────────────────────────
private struct NormalizedChainEntry: Decodable {
    let kind: String
    let status: String
    let assetName: String
    let symbol: String
    let chainName: String
    let amount: Double
    let counterparty: String
    let txHash: String
    let blockHeight: Int?
    let timestamp: Double
}
extension WalletStore {
    func canLoadMoreHistory(for walletID: UUID) -> Bool {
        guard let wallet = cachedWalletByID[walletID] else { return false }
        switch wallet.selectedChain {
        case "Bitcoin": return !historyPaginationExhausted(chainId: HistoryChainID.bitcoin, walletId: walletID)
        case "Bitcoin Cash": return !historyPaginationExhausted(chainId: HistoryChainID.bitcoinCash, walletId: walletID)
        case "Bitcoin SV": return !historyPaginationExhausted(chainId: HistoryChainID.bitcoinSV, walletId: walletID)
        case "Litecoin": return !historyPaginationExhausted(chainId: HistoryChainID.litecoin, walletId: walletID)
        case "Dogecoin": return !historyPaginationExhausted(chainId: HistoryChainID.dogecoin, walletId: walletID)
        case "Ethereum": return !historyPaginationExhausted(chainId: HistoryChainID.ethereum, walletId: walletID)
        case "Arbitrum": return !historyPaginationExhausted(chainId: HistoryChainID.arbitrum, walletId: walletID)
        case "Optimism": return !historyPaginationExhausted(chainId: HistoryChainID.optimism, walletId: walletID)
        case "BNB Chain": return !historyPaginationExhausted(chainId: HistoryChainID.bnb, walletId: walletID)
        case "Hyperliquid": return !historyPaginationExhausted(chainId: HistoryChainID.hyperliquid, walletId: walletID)
        case "Tron": return !historyPaginationExhausted(chainId: HistoryChainID.tron, walletId: walletID)
        default: return false
        }
    }
    func canLoadMoreOnChainHistory(for walletIDs: Set<UUID>) -> Bool {
        !isLoadingMoreOnChainHistory && walletIDs.contains(where: canLoadMoreHistory(for:))
    }
    func loadMoreOnChainHistory(for walletIDs: Set<UUID>) async { await WalletFetchLayer.loadMoreOnChainHistory(for: walletIDs, using: self) }

    // ── Generic normalized refresh (covers BCH, BSV, LTC, XRP, XLM, ADA, DOT,
    //    SOL, TRX, SUI, APT, TON, NEAR, ICP, XMR and any future account-based chain)
    func refreshNormalizedChainTransactions(
        chainName: String,
        chainId: UInt32,
        resolveAddress: (ImportedWallet) -> String?,
        upsert: ([TransactionRecord]) -> Void,
        loadMore: Bool = false,
        targetWalletIDs: Set<UUID>? = nil
    ) async {
        let walletSnapshot = wallets
        let filtered = walletSnapshot.filter { wallet in
            guard wallet.selectedChain == chainName, resolveAddress(wallet) != nil else { return false }
            guard let targetWalletIDs else { return true }
            return targetWalletIDs.contains(wallet.id)
        }
        guard !filtered.isEmpty else { return }
        var discovered: [TransactionRecord] = []
        var hadErrors = false
        for wallet in filtered {
            guard let address = resolveAddress(wallet) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchNormalizedHistoryJSON(chainId: chainId, address: address)
                let entries = decodeNormalizedHistory(json)
                discovered.append(contentsOf: entries.map { entry in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: TransactionKind(rawValue: entry.kind) ?? .send,
                        status: TransactionStatus(rawValue: entry.status) ?? .confirmed,
                        walletName: wallet.name,
                        assetName: entry.assetName,
                        symbol: entry.symbol,
                        chainName: entry.chainName,
                        amount: entry.amount,
                        address: entry.counterparty,
                        transactionHash: entry.txHash.isEmpty ? nil : entry.txHash,
                        receiptBlockNumber: entry.blockHeight,
                        transactionHistorySource: "rust",
                        createdAt: entry.timestamp > 0 ? Date(timeIntervalSince1970: entry.timestamp) : Date()
                    )
                })
            } catch {
                hadErrors = true
            }
        }
        guard !discovered.isEmpty else {
            if hadErrors { markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.") }
            return
        }
        upsert(discovered)
        if hadErrors { markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.") } else { markChainHealthy(chainName) }
    }

    private func decodeNormalizedHistory(_ json: String) -> [NormalizedChainEntry] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([NormalizedChainEntry].self, from: data)
        else { return [] }
        return entries
    }

    // ── Per-chain refresh methods (thin wrappers over the generic above)
    func refreshBitcoinCashTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash, resolveAddress: { resolvedBitcoinCashAddress(for: $0) }, upsert: upsertBitcoinCashTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshBitcoinSVTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv, resolveAddress: { resolvedBitcoinSVAddress(for: $0) }, upsert: upsertBitcoinSVTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshLitecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Litecoin", chainId: SpectraChainID.litecoin, resolveAddress: { resolvedLitecoinAddress(for: $0) }, upsert: upsertLitecoinTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshCardanoTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Cardano", chainId: SpectraChainID.cardano, resolveAddress: { resolvedCardanoAddress(for: $0) }, upsert: upsertCardanoTransactions)
    }
    func refreshXRPTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "XRP Ledger", chainId: SpectraChainID.xrp, resolveAddress: { resolvedXRPAddress(for: $0) }, upsert: upsertXRPTransactions)
    }
    func refreshStellarTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Stellar", chainId: SpectraChainID.stellar, resolveAddress: { resolvedStellarAddress(for: $0) }, upsert: upsertStellarTransactions)
    }
    func refreshMoneroTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Monero", chainId: SpectraChainID.monero, resolveAddress: { resolvedMoneroAddress(for: $0) }, upsert: upsertMoneroTransactions)
    }
    func refreshSuiTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Sui", chainId: SpectraChainID.sui, resolveAddress: { resolvedSuiAddress(for: $0) }, upsert: upsertSuiTransactions)
    }
    func refreshICPTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Internet Computer", chainId: SpectraChainID.icp, resolveAddress: { resolvedICPAddress(for: $0) }, upsert: upsertICPTransactions)
    }
    func refreshAptosTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Aptos", chainId: SpectraChainID.aptos, resolveAddress: { resolvedAptosAddress(for: $0) }, upsert: upsertAptosTransactions)
    }
    func refreshTONTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "TON", chainId: SpectraChainID.ton, resolveAddress: { resolvedTONAddress(for: $0) }, upsert: upsertTONTransactions)
    }
    func refreshNearTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "NEAR", chainId: SpectraChainID.near, resolveAddress: { resolvedNearAddress(for: $0) }, upsert: upsertNearTransactions)
    }
    func refreshPolkadotTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Polkadot", chainId: SpectraChainID.polkadot, resolveAddress: { resolvedPolkadotAddress(for: $0) }, upsert: upsertPolkadotTransactions)
    }
    func refreshSolanaTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(chainName: "Solana", chainId: SpectraChainID.solana, resolveAddress: { resolvedSolanaAddress(for: $0) }, upsert: upsertSolanaTransactions)
    }
    func refreshTronTransactions(loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Tron", chainId: SpectraChainID.tron, resolveAddress: { resolvedTronAddress(for: $0) }, upsert: upsertTronTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Bitcoin (special: HD xpub address expansion + single-address fallback)
// ────────────────────────────────────────────────────────────────────────────
extension WalletStore {
func fetchBitcoinHistoryPage(for wallet: ImportedWallet, limit: Int, cursor: String?) async throws -> BitcoinHistoryPage {
    if cursor == nil, let seedPhrase = storedSeedPhrase(for: wallet.id), !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let pathParts = wallet.seedDerivationPaths.bitcoin.split(separator: "/")
        let accountPath = String(pathParts.prefix(4).joined(separator: "/"))
        if let xpub = try? await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
            mnemonicPhrase: seedPhrase, passphrase: "", accountPath: accountPath
        ) {
            let page = try await fetchBitcoinHDHistoryPage(xpub: xpub, limit: limit)
            if !page.snapshots.isEmpty { return page }}}
    if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty {
        let json = try await WalletServiceBridge.shared.fetchNormalizedHistoryJSON(chainId: SpectraChainID.bitcoin, address: bitcoinAddress)
        return decodeBitcoinNormalizedPage(json: json, limit: limit)
    }
    if let bitcoinXPub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinXPub.isEmpty { return try await fetchBitcoinHDHistoryPage(xpub: bitcoinXPub, limit: limit) }
    throw URLError(.fileDoesNotExist)
}
private func fetchBitcoinHDHistoryPage(xpub: String, limit: Int) async throws -> BitcoinHistoryPage {
    struct HdAddr: Decodable { let address: String }
    async let receiveTask = WalletServiceBridge.shared.deriveBitcoinHdAddressesJSON(
        xpub: xpub, change: 0, startIndex: 0, count: 20)
    async let changeTask = WalletServiceBridge.shared.deriveBitcoinHdAddressesJSON(
        xpub: xpub, change: 1, startIndex: 0, count: 10)
    let (receiveJSON, changeJSON) = try await (receiveTask, changeTask)
    let receiveAddrs = (try? JSONDecoder().decode([HdAddr].self, from: Data(receiveJSON.utf8)))?.map(\.address) ?? []
    let changeAddrs = (try? JSONDecoder().decode([HdAddr].self, from: Data(changeJSON.utf8)))?.map(\.address) ?? []
    let allAddresses = receiveAddrs + changeAddrs
    guard !allAddresses.isEmpty else { return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust.hd") }
    let indexedAddresses = Array(allAddresses.enumerated())
    let fetchedSnapshots = await collectLimitedConcurrentIndexedResults(from: indexedAddresses, maxConcurrent: 4) { entry in
        let (index, address) = entry
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.bitcoin, address: address)
            let entries = self.decodeRustHistoryJSON(json: json)
            let payloads = entries.compactMap { obj -> WalletRustBitcoinHistorySnapshotPayload? in
                guard let txid = obj["txid"] as? String else { return nil }
                let netSats = obj["net_sats"] as? Int ?? 0
                let confirmed = obj["confirmed"] as? Bool ?? false
                return WalletRustBitcoinHistorySnapshotPayload(
                    txid: txid, amountBTC: Double(abs(netSats)) / 100_000_000, kind: netSats >= 0 ? "receive" : "send", status: confirmed ? "confirmed" : "pending", counterpartyAddress: "", blockHeight: obj["block_height"] as? Int, createdAtUnix: obj["block_time"] as? Double ?? 0
                )
            }
            return (index, payloads)
        } catch {
            return (index, nil)
        }}
    let mergedSnapshots = try WalletRustAppCoreBridge.mergeBitcoinHistorySnapshots(
        WalletRustMergeBitcoinHistorySnapshotsRequest(
            snapshots: fetchedSnapshots.sorted { $0.key < $1.key }.flatMap(\.value), ownedAddresses: allAddresses, limit: limit
        )
    )
    return BitcoinHistoryPage(
        snapshots: mergedSnapshots.map { snapshot in
            BitcoinHistorySnapshot(
                txid: snapshot.txid, amountBTC: snapshot.amountBTC, kind: TransactionKind(rawValue: snapshot.kind) ?? .send, status: TransactionStatus(rawValue: snapshot.status) ?? .pending, counterpartyAddress: snapshot.counterpartyAddress, blockHeight: snapshot.blockHeight, createdAt: Date(timeIntervalSince1970: snapshot.createdAtUnix)
            )
        }, nextCursor: nil, sourceUsed: "rust.hd"
    )
}
private func decodeBitcoinNormalizedPage(json: String, limit: Int) -> BitcoinHistoryPage {
    guard let data = json.data(using: .utf8),
          let entries = try? JSONDecoder().decode([NormalizedChainEntry].self, from: data)
    else { return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust") }
    let snapshots: [BitcoinHistorySnapshot] = Array(entries.prefix(limit)).map { e in
        BitcoinHistorySnapshot(
            txid: e.txHash,
            amountBTC: e.amount,
            kind: TransactionKind(rawValue: e.kind) ?? .send,
            status: TransactionStatus(rawValue: e.status) ?? .confirmed,
            counterpartyAddress: e.counterparty,
            blockHeight: e.blockHeight,
            createdAt: e.timestamp > 0 ? Date(timeIntervalSince1970: e.timestamp) : Date()
        )
    }
    let nextCursor = entries.count > limit ? entries[limit - 1].txHash : nil
    return BitcoinHistoryPage(snapshots: snapshots, nextCursor: nextCursor, sourceUsed: "rust")
}
func decodeRustHistoryJSON(json: String) -> [[String: Any]] {
    guard let data = json.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return arr
}
func refreshBitcoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let bitcoinWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == "Bitcoin" else { return false }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !bitcoinWallets.isEmpty else { return }
    let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))
    if !loadMore {
        for walletID in Set(bitcoinWallets.map(\.id)) { resetHistoryPagination(chainId: HistoryChainID.bitcoin, walletId: walletID) }}
    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    for wallet in bitcoinWallets {
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.bitcoin, walletId: wallet.id) { continue }
        let cursor = loadMore ? historyPaginationCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id) : nil
        do {
            let page = try await fetchBitcoinHistoryPage(for: wallet, limit: requestedLimit, cursor: cursor)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
            setHistoryCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id, cursor: page.nextCursor)
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: page.snapshots.count, nextCursor: page.nextCursor, error: nil
            )
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
            discoveredTransactions.append(
                contentsOf: page.snapshots.map { snapshot in
                    TransactionRecord(
                        walletID: wallet.id, kind: snapshot.kind, status: snapshot.status, walletName: wallet.name, assetName: "Bitcoin", symbol: "BTC", chainName: "Bitcoin", amount: snapshot.amountBTC, address: snapshot.counterpartyAddress, transactionHash: snapshot.txid, receiptBlockNumber: snapshot.blockHeight, transactionHistorySource: page.sourceUsed, createdAt: snapshot.createdAt
                    )
                }
            )
        } catch {
            encounteredErrors = true
            setHistoryCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id, cursor: nil)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? ""
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id, identifier: identifier, sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription
            )
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
        }}
    if !discoveredTransactions.isEmpty {
        upsertBitcoinTransactions(discoveredTransactions)
        if encounteredErrors { markChainDegraded("Bitcoin", detail: "Bitcoin history loaded with partial provider failures.") } else { markChainHealthy("Bitcoin") }
    } else if encounteredErrors { markChainDegraded("Bitcoin", detail: "Bitcoin history refresh failed. Using cached history.") }
}
}

// ────────────────────────────────────────────────────────────────────────────
// Dogecoin (special: multi-address per-wallet, UTXO aggregation)
// ────────────────────────────────────────────────────────────────────────────
extension WalletStore {
func refreshDogecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let walletsToRefresh = plannedDogecoinHistoryWallets(walletSnapshot: walletSnapshot, targetWalletIDs: targetWalletIDs) ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, [String])? in
        guard wallet.selectedChain == "Dogecoin", !knownDogecoinAddresses(for: wallet).isEmpty else { return nil }
        if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) { return nil }
        return (wallet, knownDogecoinAddresses(for: wallet))
    }
    guard !walletsToRefresh.isEmpty else { return }
    let fetchLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 200))
    if !loadMore {
        for walletID in Set(walletsToRefresh.map { $0.0.id }) {
            resetHistoryPagination(chainId: HistoryChainID.dogecoin, walletId: walletID)
        }}
    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    for (wallet, dogecoinAddresses) in walletsToRefresh {
        let ownAddressSet = Set(dogecoinAddresses.map { $0.lowercased() })
        var snapshotsByHash: [String: [DogecoinBalanceService.AddressTransactionSnapshot]] = [:]
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.dogecoin, walletId: wallet.id) { continue }
        for dogecoinAddress in dogecoinAddresses {
            do {
                let json = try await WalletServiceBridge.shared.fetchNormalizedHistoryJSON(chainId: SpectraChainID.dogecoin, address: dogecoinAddress)
                let entries = decodeNormalizedHistory(json)
                for entry in entries {
                    guard !entry.txHash.isEmpty else { continue }
                    let blockHeight = entry.blockHeight
                    snapshotsByHash[entry.txHash, default: []].append(
                        DogecoinBalanceService.AddressTransactionSnapshot(
                            hash: entry.txHash,
                            kind: TransactionKind(rawValue: entry.kind) ?? .send,
                            status: TransactionStatus(rawValue: entry.status) ?? .confirmed,
                            amount: entry.amount,
                            counterpartyAddress: entry.counterparty,
                            createdAt: entry.timestamp > 0 ? Date(timeIntervalSince1970: entry.timestamp) : Date.distantPast,
                            blockNumber: blockHeight
                        )
                    )
                }
                markHistoryExhausted(chainId: HistoryChainID.dogecoin, walletId: wallet.id)
            } catch {
                encounteredErrors = true
                continue
            }}
        guard !snapshotsByHash.isEmpty else { continue }
        let mapped: [TransactionRecord] = snapshotsByHash.values.compactMap { groupedSnapshots -> TransactionRecord? in
            guard let first = groupedSnapshots.first else { return nil }
            let signedAmount = groupedSnapshots.reduce(0.0) { partialResult, snapshot in
                partialResult + (snapshot.kind == .receive ? snapshot.amount : -snapshot.amount)
            }
            guard abs(signedAmount) > 0 else { return nil }
            let effectiveKind: TransactionKind = signedAmount > 0 ? .receive : .send
            let effectiveAmount = abs(signedAmount)
            let effectiveStatus: TransactionStatus = groupedSnapshots.contains(where: { $0.status == .pending }) ? .pending : .confirmed
            let effectiveBlockNumber = groupedSnapshots.compactMap(\.blockNumber).max()
            let knownDates = groupedSnapshots.map(\.createdAt).filter { $0 != Date.distantPast }
            let effectiveCreatedAt = knownDates.min() ?? first.createdAt
            let preferredCounterparty = groupedSnapshots.map(\.counterpartyAddress).first(where: { !ownAddressSet.contains($0.lowercased()) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                ?? first.counterpartyAddress
            return TransactionRecord(
                walletID: wallet.id, kind: effectiveKind, status: effectiveStatus, walletName: wallet.name, assetName: "Dogecoin", symbol: "DOGE", chainName: "Dogecoin", amount: effectiveAmount, address: preferredCounterparty, transactionHash: first.hash, receiptBlockNumber: effectiveBlockNumber, transactionHistorySource: "dogecoin.providers", createdAt: effectiveCreatedAt
            )
        }
        syncedTransactions.append(contentsOf: mapped)
    }
    guard !syncedTransactions.isEmpty else {
        if encounteredErrors { markChainDegraded("Dogecoin", detail: "Dogecoin history refresh failed. Using cached history.") }
        return
    }
    upsertDogecoinTransactions(syncedTransactions)
    if encounteredErrors { markChainDegraded("Dogecoin", detail: "Dogecoin history loaded with partial provider failures.") } else { markChainHealthy("Dogecoin") }
}
private func plannedDogecoinHistoryWallets(
    walletSnapshot: [ImportedWallet], targetWalletIDs: Set<UUID>?
) -> [(ImportedWallet, [String])]? {
    let request = WalletRustDogecoinRefreshTargetsRequest(
        wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustDogecoinRefreshWalletInput(
                index: index, walletID: wallet.id.uuidString, selectedChain: wallet.selectedChain, addresses: knownDogecoinAddresses(for: wallet)
            )
        }, allowedWalletIDs: targetWalletIDs?.map(\.uuidString)
    )
    guard let targets = try? WalletRustAppCoreBridge.planDogecoinRefreshTargets(request) else { return nil }
    let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id.uuidString, $0) })
    return targets.compactMap { target in
        guard let wallet = walletByID[target.walletID] else { return nil }
        return (wallet, target.addresses)
    }
}
}

// ────────────────────────────────────────────────────────────────────────────
// EVM (special: token + native transfers, page-based pagination)
// ────────────────────────────────────────────────────────────────────────────
extension WalletStore {
@MainActor func refreshEVMTokenTransactions(
    chainName: String, maxResults: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil
) async {
    guard let chain = evmChainContext(for: chainName) else { return }
    let walletSnapshot = wallets
    let walletsToRefresh = plannedEVMHistoryWallets(
        chainName: chainName, walletSnapshot: walletSnapshot, targetWalletIDs: targetWalletIDs
    ) ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, String)? in
        guard wallet.selectedChain == chainName, let address = resolvedEVMAddress(for: wallet, chainName: chainName) else { return nil }
        if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) { return nil }
        return (wallet, address)
    }
    guard !walletsToRefresh.isEmpty else { return }
    let refreshedWalletIDs = Set(walletsToRefresh.map { $0.0.id })
    let historyTargets: [([ImportedWallet], String, String)] = plannedEVMHistoryGroups(
        chainName: chainName, walletSnapshot: walletSnapshot, loadMore: loadMore, targetWalletIDs: targetWalletIDs
    ) ?? {
        if loadMore {
            return walletsToRefresh.map { ([$0.0], $0.1, normalizeEVMAddress($0.1)) }}
        return Dictionary(grouping: walletsToRefresh) {
            normalizeEVMAddress($0.1)
        }
        .values.compactMap { group in
            guard let first = group.first else { return nil }
            return (group.map(\.0), first.1, normalizeEVMAddress(first.1))
        }}()
    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    let unknownTimestamp = Date.distantPast
    let requestedPageSize = max(20, min(maxResults ?? HistoryPaging.endpointBatchSize, 500))
    if !loadMore {
        let walletIDs = Set(walletsToRefresh.map { $0.0.id })
        let evmChainId: UInt32 = chain.isEthereumFamily ? HistoryChainID.ethereum
            : chain == .arbitrum ? HistoryChainID.arbitrum
            : chain == .optimism ? HistoryChainID.optimism
            : chain == .hyperliquid ? HistoryChainID.hyperliquid
            : HistoryChainID.bnb
        for walletID in walletIDs {
            resetHistoryPagination(chainId: evmChainId, walletId: walletID)
            setHistoryPage(chainId: evmChainId, walletId: walletID, page: 1)
        }}
    let evmChainId: UInt32 = chain.isEthereumFamily ? HistoryChainID.ethereum
        : chain == .arbitrum ? HistoryChainID.arbitrum
        : chain == .optimism ? HistoryChainID.optimism
        : chain == .hyperliquid ? HistoryChainID.hyperliquid
        : HistoryChainID.bnb
    for (targetWallets, _, normalizedAddress) in historyTargets {
        guard let representativeWallet = targetWallets.first else { continue }
        if loadMore && historyPaginationExhausted(chainId: evmChainId, walletId: representativeWallet.id) { continue }
        let currentPage = max(1, historyPaginationPage(chainId: evmChainId, walletId: representativeWallet.id))
        let page = loadMore ? (currentPage + 1) : currentPage
        let trackedTokens: [EthereumSupportedToken]? = if chain.isEthereumMainnet { enabledEthereumTrackedTokens() } else if chain == .arbitrum { enabledArbitrumTrackedTokens() } else if chain == .optimism { enabledOptimismTrackedTokens() } else if chain == .hyperliquid { enabledHyperliquidTrackedTokens() } else if chain == .bnb { enabledBNBTrackedTokens() } else { nil }
        var tokenHistory: [EthereumTokenTransferSnapshot] = []
        var tokenDiagnostics: EthereumTokenTransferHistoryDiagnostics?
        var tokenHistoryError: Error?
        var nativeTransfers: [EthereumNativeTransferSnapshot] = []
        guard let chainId = SpectraChainID.id(for: chainName) else {
            encounteredErrors = true
            continue
        }
        let tokenTuples: [(contract: String, symbol: String, name: String, decimals: Int)] =
            (trackedTokens ?? []).map { ($0.contractAddress, $0.symbol, $0.name, $0.decimals) }
        do {
            let json = try await WalletServiceBridge.shared.fetchEVMHistoryPageJSON(
                chainId: chainId, address: normalizedAddress, tokens: tokenTuples, page: page, pageSize: requestedPageSize
            )
            let (decodedToken, decodedNative) = decodeEvmHistoryPageJSON(json)
            tokenHistory = decodedToken
            nativeTransfers = decodedNative
            tokenDiagnostics = EthereumTokenTransferHistoryDiagnostics(
                address: normalizedAddress, rpcTransferCount: 0, rpcError: nil, blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: decodedToken.count, etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "rust/etherscan"
            )
        } catch {
            tokenHistoryError = error
            encounteredErrors = true
        }
        typealias DiagsByWallet = [UUID: EthereumTokenTransferHistoryDiagnostics]
        let diagsKP: ReferenceWritableKeyPath<WalletStore, DiagsByWallet>? =
            chain.isEthereumFamily ? \.ethereumHistoryDiagnosticsByWallet
            : chain == .arbitrum   ? \.arbitrumHistoryDiagnosticsByWallet
            : chain == .optimism   ? \.optimismHistoryDiagnosticsByWallet
            : nil
        let tsKP: ReferenceWritableKeyPath<WalletStore, Date?>? =
            chain.isEthereumFamily ? \.ethereumHistoryDiagnosticsLastUpdatedAt
            : chain == .arbitrum   ? \.arbitrumHistoryDiagnosticsLastUpdatedAt
            : chain == .optimism   ? \.optimismHistoryDiagnosticsLastUpdatedAt
            : nil
        if let diagsKP, let tsKP {
            if let tokenDiagnostics {
                var diags = self[keyPath: diagsKP]
                for wallet in targetWallets { diags[wallet.id] = tokenDiagnostics }
                self[keyPath: diagsKP] = diags
            } else if let tokenHistoryError {
                let errDiag = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizedAddress, rpcTransferCount: 0, rpcError: tokenHistoryError.localizedDescription, blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: 0, etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "none"
                )
                var diags = self[keyPath: diagsKP]
                for wallet in targetWallets { diags[wallet.id] = errDiag }
                self[keyPath: diagsKP] = diags
            }
            self[keyPath: tsKP] = Date()
        }
        let isLastPage = tokenHistory.count < requestedPageSize && nativeTransfers.count < requestedPageSize
        for wallet in targetWallets {
            if isLastPage { markHistoryExhausted(chainId: evmChainId, walletId: wallet.id) } else { markHistoryActive(chainId: evmChainId, walletId: wallet.id) }
            setHistoryPage(chainId: evmChainId, walletId: wallet.id, page: page)
        }
        for wallet in targetWallets {
            for transfer in tokenHistory {
                let isOutgoing = transfer.fromAddress == normalizedAddress
                let isIncoming = transfer.toAddress == normalizedAddress
                guard isOutgoing || isIncoming else { continue }
                let counterparty = isOutgoing ? transfer.toAddress : transfer.fromAddress
                let walletSideAddress = isOutgoing ? transfer.fromAddress : transfer.toAddress
                let createdAt = transfer.timestamp ?? unknownTimestamp
                syncedTransactions.append(
                    TransactionRecord(
                        walletID: wallet.id, kind: isOutgoing ? .send : .receive, status: .confirmed, walletName: wallet.name, assetName: transfer.tokenName, symbol: transfer.symbol, chainName: chainName, amount: NSDecimalNumber(decimal: transfer.amount).doubleValue, address: counterparty, transactionHash: transfer.transactionHash, receiptBlockNumber: transfer.blockNumber, sourceAddress: walletSideAddress, transactionHistorySource: tokenDiagnostics?.sourceUsed ?? "none", createdAt: createdAt
                    )
                )
            }}
        for wallet in targetWallets {
            for transfer in nativeTransfers {
                let isOutgoing = transfer.fromAddress == normalizedAddress
                let isIncoming = transfer.toAddress == normalizedAddress
                guard isOutgoing || isIncoming else { continue }
                let counterparty = isOutgoing ? transfer.toAddress : transfer.fromAddress
                let walletSideAddress = isOutgoing ? transfer.fromAddress : transfer.toAddress
                let createdAt = transfer.timestamp ?? unknownTimestamp
                let nativeAssetName: String
                let nativeSymbol: String
                switch chain {
                case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism: nativeAssetName = "Ether"; nativeSymbol = "ETH"
                case .avalanche: nativeAssetName = "Avalanche"; nativeSymbol = "AVAX"
                case .bnb: nativeAssetName = "BNB"; nativeSymbol = "BNB"
                case .ethereumClassic: nativeAssetName = "Ethereum Classic"; nativeSymbol = "ETC"
                case .hyperliquid: nativeAssetName = "Hyperliquid"; nativeSymbol = "HYPE"
                }
                syncedTransactions.append(
                    TransactionRecord(
                        walletID: wallet.id, kind: isOutgoing ? .send : .receive, status: .confirmed, walletName: wallet.name, assetName: nativeAssetName, symbol: nativeSymbol, chainName: chainName, amount: NSDecimalNumber(decimal: transfer.amount).doubleValue, address: counterparty, transactionHash: transfer.transactionHash, receiptBlockNumber: transfer.blockNumber, sourceAddress: walletSideAddress, transactionHistorySource: "etherscan", createdAt: createdAt
                    )
                )
            }}}
    guard !syncedTransactions.isEmpty else {
        if encounteredErrors {
            let hasCachedHistory = transactions.contains { transaction in
                guard transaction.chainName == chainName, let walletID = transaction.walletID else { return false }
                return refreshedWalletIDs.contains(walletID)
            }
            if hasCachedHistory { markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.") }}
        return
    }
    switch chain {
    case .ethereum, .ethereumSepolia, .ethereumHoodi: upsertEthereumTransactions(syncedTransactions)
    case .arbitrum: upsertArbitrumTransactions(syncedTransactions)
    case .optimism: upsertOptimismTransactions(syncedTransactions)
    case .bnb: upsertBNBTransactions(syncedTransactions)
    case .avalanche: upsertAvalancheTransactions(syncedTransactions)
    case .ethereumClassic: upsertETCTransactions(syncedTransactions)
    case .hyperliquid: upsertHyperliquidTransactions(syncedTransactions)
    }
    if encounteredErrors { markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.") } else { markChainHealthy(chainName) }
}
private func plannedEVMHistoryWallets(
    chainName: String, walletSnapshot: [ImportedWallet], targetWalletIDs: Set<UUID>?
) -> [(ImportedWallet, String)]? {
    let allowedWalletIDs = targetWalletIDs?.map(\.uuidString)
    let request = WalletRustEVMRefreshTargetsRequest(
        chainName: chainName, wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustEVMRefreshWalletInput(
                index: index, walletID: wallet.id.uuidString, selectedChain: wallet.selectedChain, address: resolvedEVMAddress(for: wallet, chainName: chainName)
            )
        }, allowedWalletIDs: allowedWalletIDs, groupByNormalizedAddress: false
    )
    guard let plan = try? WalletRustAppCoreBridge.planEVMRefreshTargets(request) else { return nil }
    return plan.walletTargets.compactMap { target in
        guard let wallet = walletSnapshot.first(where: { $0.id.uuidString == target.walletID }) else { return nil }
        return (wallet, target.address)
    }
}
private func plannedEVMHistoryGroups(
    chainName: String, walletSnapshot: [ImportedWallet], loadMore: Bool, targetWalletIDs: Set<UUID>?
) -> [([ImportedWallet], String, String)]? {
    let allowedWalletIDs = targetWalletIDs?.map(\.uuidString)
    let request = WalletRustEVMRefreshTargetsRequest(
        chainName: chainName, wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustEVMRefreshWalletInput(
                index: index, walletID: wallet.id.uuidString, selectedChain: wallet.selectedChain, address: resolvedEVMAddress(for: wallet, chainName: chainName)
            )
        }, allowedWalletIDs: allowedWalletIDs, groupByNormalizedAddress: !loadMore
    )
    guard let plan = try? WalletRustAppCoreBridge.planEVMRefreshTargets(request) else { return nil }
    let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id.uuidString, $0) })
    return plan.groupedTargets.compactMap { target in
        let wallets = target.walletIDs.compactMap { walletByID[$0] }
        guard !wallets.isEmpty else { return nil }
        return (wallets, target.address, target.normalizedAddress)
    }
}
}

private func decodeEvmHistoryPageJSON(_ json: String) -> (
    tokens: [EthereumTokenTransferSnapshot], native: [EthereumNativeTransferSnapshot]
) {
    guard
        let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return ([], []) }
    var tokens: [EthereumTokenTransferSnapshot] = []
    if let rawTokens = obj["tokens"] as? [[String: Any]] {
        for item in rawTokens {
            guard
                let contract   = item["contract"]     as? String, let symbol     = item["symbol"]       as? String, let tokenName  = item["token_name"]   as? String, let fromAddr   = item["from"]         as? String, let toAddr     = item["to"]           as? String, let txid       = item["txid"]         as? String, let blockNum   = item["block_number"] as? Int, let logIdx     = item["log_index"]    as? Int, let tsecs      = item["timestamp"]    as? TimeInterval
            else { continue }
            let decimals = item["decimals"] as? Int ?? 18
            let amountDecimal: Decimal
            if let display = item["amount_display"] as? String, let d = Decimal(string: display) { amountDecimal = d } else if let raw = item["amount_raw"] as? String, let rawDec = Decimal(string: raw) {
                let scale = decimalPow(Decimal(10), decimals)
                amountDecimal = rawDec / scale
            } else { amountDecimal = 0 }
            tokens.append(EthereumTokenTransferSnapshot( contractAddress: contract, tokenName: tokenName, symbol: symbol, decimals: decimals, fromAddress: fromAddr, toAddress: toAddr, amount: amountDecimal, transactionHash: txid, blockNumber: blockNum, logIndex: logIdx, timestamp: tsecs > 0 ? Date(timeIntervalSince1970: tsecs) : nil
            ))
        }}
    var native: [EthereumNativeTransferSnapshot] = []
    if let rawNative = obj["native"] as? [[String: Any]] {
        let weiPerCoin = Decimal(string: "1000000000000000000")! // 1e18
        for item in rawNative {
            guard
                let fromAddr = item["from"]         as? String, let toAddr   = item["to"]           as? String, let txid     = item["txid"]         as? String, let blockNum = item["block_number"] as? Int, let tsecs    = item["timestamp"]    as? TimeInterval, let weiStr   = item["value_wei"]    as? String, let weiDec   = Decimal(string: weiStr)
            else { continue }
            let amount = weiDec / weiPerCoin
            native.append(EthereumNativeTransferSnapshot( fromAddress: fromAddr, toAddress: toAddr, amount: amount, transactionHash: txid, blockNumber: blockNum, timestamp: tsecs > 0 ? Date(timeIntervalSince1970: tsecs) : nil
            ))
        }}
    return (tokens, native)
}
private func decimalPow(_ base: Decimal, _ exponent: Int) -> Decimal {
    var result = Decimal(1)
    for _ in 0 ..< exponent { result *= base }
    return result
}
