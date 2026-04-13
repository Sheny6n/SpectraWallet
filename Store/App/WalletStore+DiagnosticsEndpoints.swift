import Foundation
import SwiftUI
@MainActor
extension WalletStore {
    func runBitcoinHistoryDiagnostics() async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }
        let btcWallets = wallets.filter { $0.selectedChain == "Bitcoin" }
        guard !btcWallets.isEmpty else {
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }
        for wallet in btcWallets {
            do {
                let page = try await withTimeout(seconds: 20) { try await self.fetchBitcoinHistoryPage(for: wallet, limit: HistoryPaging.endpointBatchSize, cursor: nil) }
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
                if identifier.isEmpty {
                    bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                        walletID: wallet.id, identifier: "missing address/xpub", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: "Wallet has no BTC address or xpub configured."
                    )
                    continue
                }
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: page.snapshots.count, nextCursor: page.nextCursor, error: nil
                )
            } catch {
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? "unknown"
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id, identifier: identifier, sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription
                )
            }
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
        }}
    func runBitcoinHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == "Bitcoin" else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }
        do {
            let page = try await withTimeout(seconds: 20) { try await self.fetchBitcoinHistoryPage(for: wallet, limit: HistoryPaging.endpointBatchSize, cursor: nil) }
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
            if identifier.isEmpty {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id, identifier: "missing address/xpub", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: "Wallet has no BTC address or xpub configured."
                )
                bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
                return
            }
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: page.snapshots.count, nextCursor: page.nextCursor, error: nil
            )
        } catch {
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? "unknown"
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id, identifier: identifier, sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription
            )
        }
        bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
    }
    func runBitcoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinEndpointHealth else { return }
        isCheckingBitcoinEndpointHealth = true
        defer { isCheckingBitcoinEndpointHealth = false }
        let endpoints = effectiveBitcoinEsploraEndpoints()
        var results: [BitcoinEndpointHealthResult] = []
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else {
                results.append(
                    BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")
                )
                continue
            }
            let probeTarget = url.appending(path: "blocks/tip/height")
            let probe = await probeHTTP(probeTarget)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail
                )
            )
            bitcoinEndpointHealthResults = results
            bitcoinEndpointHealthLastUpdatedAt = Date()
        }}
    func runLitecoinHistoryDiagnostics() async { await runUTXOStyleHistoryDiagnostics(chainId: SpectraChainID.litecoin, isRunningKP: \.isRunningLitecoinHistoryDiagnostics, chainName: "Litecoin", resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, diagsKP: \.litecoinHistoryDiagnosticsByWallet, tsKP: \.litecoinHistoryDiagnosticsLastUpdatedAt) }
    func runLitecoinHistoryDiagnostics(for walletID: UUID) async { await runUTXOStyleHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.litecoin, isRunningKP: \.isRunningLitecoinHistoryDiagnostics, chainName: "Litecoin", resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, diagsKP: \.litecoinHistoryDiagnosticsByWallet, tsKP: \.litecoinHistoryDiagnosticsLastUpdatedAt) }
    func runLitecoinEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingLitecoinEndpointHealth, checks: LitecoinBalanceService.diagnosticsChecks(), resultsKP: \.litecoinEndpointHealthResults, tsKP: \.litecoinEndpointHealthLastUpdatedAt) }
    func runBitcoinCashHistoryDiagnostics() async { await runUTXOStyleHistoryDiagnostics(chainId: SpectraChainID.bitcoinCash, isRunningKP: \.isRunningBitcoinCashHistoryDiagnostics, chainName: "Bitcoin Cash", resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, diagsKP: \.bitcoinCashHistoryDiagnosticsByWallet, tsKP: \.bitcoinCashHistoryDiagnosticsLastUpdatedAt) }
    func runBitcoinCashEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingBitcoinCashEndpointHealth, checks: BitcoinCashBalanceService.diagnosticsChecks(), resultsKP: \.bitcoinCashEndpointHealthResults, tsKP: \.bitcoinCashEndpointHealthLastUpdatedAt) }
    func runBitcoinSVHistoryDiagnostics() async { await runUTXOStyleHistoryDiagnostics(chainId: SpectraChainID.bitcoinSv, isRunningKP: \.isRunningBitcoinSVHistoryDiagnostics, chainName: "Bitcoin SV", resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, diagsKP: \.bitcoinSVHistoryDiagnosticsByWallet, tsKP: \.bitcoinSVHistoryDiagnosticsLastUpdatedAt) }
    func runBitcoinSVEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingBitcoinSVEndpointHealth, checks: BitcoinSVBalanceService.diagnosticsChecks(), resultsKP: \.bitcoinSVEndpointHealthResults, tsKP: \.bitcoinSVEndpointHealthLastUpdatedAt) }
    func runTronHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.tron, isRunningKP: \.isRunningTronHistoryDiagnostics, chainName: "Tron", resolveAddress: { self.resolvedTronAddress(for: $0) }, make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: $2, tronScanTRC20Count: 0, sourceUsed: $1, error: $3) }, diagsKP: \.tronHistoryDiagnosticsByWallet, tsKP: \.tronHistoryDiagnosticsLastUpdatedAt) }
    func runTronHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.tron, isRunningKP: \.isRunningTronHistoryDiagnostics, chainName: "Tron", resolveAddress: { self.resolvedTronAddress(for: $0) }, make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: $2, tronScanTRC20Count: 0, sourceUsed: $1, error: $3) }, diagsKP: \.tronHistoryDiagnosticsByWallet, tsKP: \.tronHistoryDiagnosticsLastUpdatedAt) }
    func runTronEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingTronEndpointHealth, checks: TronBalanceService.diagnosticsChecks(), resultsKP: \.tronEndpointHealthResults, tsKP: \.tronEndpointHealthLastUpdatedAt) }
    func runSolanaHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.solana, isRunningKP: \.isRunningSolanaHistoryDiagnostics, chainName: "Solana", resolveAddress: { self.resolvedSolanaAddress(for: $0) }, make: { SolanaHistoryDiagnostics(address: $0, rpcCount: $2, sourceUsed: $1, error: $3) }, diagsKP: \.solanaHistoryDiagnosticsByWallet, tsKP: \.solanaHistoryDiagnosticsLastUpdatedAt) }
    func runSolanaHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.solana, isRunningKP: \.isRunningSolanaHistoryDiagnostics, chainName: "Solana", resolveAddress: { self.resolvedSolanaAddress(for: $0) }, make: { SolanaHistoryDiagnostics(address: $0, rpcCount: $2, sourceUsed: $1, error: $3) }, diagsKP: \.solanaHistoryDiagnosticsByWallet, tsKP: \.solanaHistoryDiagnosticsLastUpdatedAt) }
    func runSolanaEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingSolanaEndpointHealth, checks: SolanaBalanceService.diagnosticsChecks(), resultsKP: \.solanaEndpointHealthResults, tsKP: \.solanaEndpointHealthLastUpdatedAt) }
    func runCardanoHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.cardano, isRunningKP: \.isRunningCardanoHistoryDiagnostics, chainName: "Cardano", resolveAddress: { self.resolvedCardanoAddress(for: $0) }, make: { CardanoHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.cardanoHistoryDiagnosticsByWallet, tsKP: \.cardanoHistoryDiagnosticsLastUpdatedAt) }
    func runCardanoHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.cardano, isRunningKP: \.isRunningCardanoHistoryDiagnostics, chainName: "Cardano", resolveAddress: { self.resolvedCardanoAddress(for: $0) }, make: { CardanoHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.cardanoHistoryDiagnosticsByWallet, tsKP: \.cardanoHistoryDiagnosticsLastUpdatedAt) }
    func runCardanoEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingCardanoEndpointHealth, checks: CardanoBalanceService.diagnosticsChecks(), resultsKP: \.cardanoEndpointHealthResults, tsKP: \.cardanoEndpointHealthLastUpdatedAt) }
    func runXRPHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.xrp, isRunningKP: \.isRunningXRPHistoryDiagnostics, chainName: "XRP Ledger", resolveAddress: { self.resolvedXRPAddress(for: $0) }, make: { XRPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.xrpHistoryDiagnosticsByWallet, tsKP: \.xrpHistoryDiagnosticsLastUpdatedAt) }
    func runXRPHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.xrp, isRunningKP: \.isRunningXRPHistoryDiagnostics, chainName: "XRP Ledger", resolveAddress: { self.resolvedXRPAddress(for: $0) }, make: { XRPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.xrpHistoryDiagnosticsByWallet, tsKP: \.xrpHistoryDiagnosticsLastUpdatedAt) }
    func runXRPEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingXRPEndpointHealth, checks: XRPBalanceService.diagnosticsChecks(), resultsKP: \.xrpEndpointHealthResults, tsKP: \.xrpEndpointHealthLastUpdatedAt) }
    func runStellarHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.stellar, isRunningKP: \.isRunningStellarHistoryDiagnostics, chainName: "Stellar", resolveAddress: { self.resolvedStellarAddress(for: $0) }, make: { StellarHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.stellarHistoryDiagnosticsByWallet, tsKP: \.stellarHistoryDiagnosticsLastUpdatedAt) }
    func runStellarHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.stellar, isRunningKP: \.isRunningStellarHistoryDiagnostics, chainName: "Stellar", resolveAddress: { self.resolvedStellarAddress(for: $0) }, make: { StellarHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.stellarHistoryDiagnosticsByWallet, tsKP: \.stellarHistoryDiagnosticsLastUpdatedAt) }
    func runStellarEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingStellarEndpointHealth, checks: StellarBalanceService.diagnosticsChecks(), resultsKP: \.stellarEndpointHealthResults, tsKP: \.stellarEndpointHealthLastUpdatedAt) }
    func runMoneroHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.monero, isRunningKP: \.isRunningMoneroHistoryDiagnostics, chainName: "Monero", resolveAddress: { self.resolvedMoneroAddress(for: $0) }, make: { MoneroHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.moneroHistoryDiagnosticsByWallet, tsKP: \.moneroHistoryDiagnosticsLastUpdatedAt) }
    func runMoneroHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.monero, isRunningKP: \.isRunningMoneroHistoryDiagnostics, chainName: "Monero", resolveAddress: { self.resolvedMoneroAddress(for: $0) }, make: { MoneroHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.moneroHistoryDiagnosticsByWallet, tsKP: \.moneroHistoryDiagnosticsLastUpdatedAt) }
    func runMoneroEndpointReachabilityDiagnostics() async {
        guard !isCheckingMoneroEndpointHealth else { return }
        isCheckingMoneroEndpointHealth = true
        defer { isCheckingMoneroEndpointHealth = false }
        let trimmedBackendURL = moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBackendURL = trimmedBackendURL.isEmpty ? MoneroBalanceService.defaultPublicBackend.baseURL : trimmedBackendURL
        guard let baseURL = URL(string: resolvedBackendURL) else {
            moneroEndpointHealthResults = [
                BitcoinEndpointHealthResult(
                    endpoint: "monero.backend.baseURL", reachable: false, statusCode: nil, detail: "Monero backend is not configured."
                )
            ]
            moneroEndpointHealthLastUpdatedAt = Date()
            return
        }
        let probeURL = baseURL.appendingPathComponent("v1/monero/balance")
        let probe = await probeHTTP(probeURL, profile: .litecoinDiagnostics)
        moneroEndpointHealthResults = [
            BitcoinEndpointHealthResult(
                endpoint: baseURL.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail
            )
        ]
        moneroEndpointHealthLastUpdatedAt = Date()
    }
    func runSuiHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.sui, isRunningKP: \.isRunningSuiHistoryDiagnostics, chainName: "Sui", resolveAddress: { self.resolvedSuiAddress(for: $0) }, make: { SuiHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.suiHistoryDiagnosticsByWallet, tsKP: \.suiHistoryDiagnosticsLastUpdatedAt) }
    func runSuiHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.sui, isRunningKP: \.isRunningSuiHistoryDiagnostics, chainName: "Sui", resolveAddress: { self.resolvedSuiAddress(for: $0) }, make: { SuiHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.suiHistoryDiagnosticsByWallet, tsKP: \.suiHistoryDiagnosticsLastUpdatedAt) }
    func runAptosHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.aptos, isRunningKP: \.isRunningAptosHistoryDiagnostics, chainName: "Aptos", resolveAddress: { self.resolvedAptosAddress(for: $0) }, make: { AptosHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.aptosHistoryDiagnosticsByWallet, tsKP: \.aptosHistoryDiagnosticsLastUpdatedAt) }
    func runAptosHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.aptos, isRunningKP: \.isRunningAptosHistoryDiagnostics, chainName: "Aptos", resolveAddress: { self.resolvedAptosAddress(for: $0) }, make: { AptosHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.aptosHistoryDiagnosticsByWallet, tsKP: \.aptosHistoryDiagnosticsLastUpdatedAt) }
    func runTONHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.ton, isRunningKP: \.isRunningTONHistoryDiagnostics, chainName: "TON", resolveAddress: { self.resolvedTONAddress(for: $0) }, make: { TONHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.tonHistoryDiagnosticsByWallet, tsKP: \.tonHistoryDiagnosticsLastUpdatedAt) }
    func runTONHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.ton, isRunningKP: \.isRunningTONHistoryDiagnostics, chainName: "TON", resolveAddress: { self.resolvedTONAddress(for: $0) }, make: { TONHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.tonHistoryDiagnosticsByWallet, tsKP: \.tonHistoryDiagnosticsLastUpdatedAt) }
    func runICPHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.icp, isRunningKP: \.isRunningICPHistoryDiagnostics, chainName: "Internet Computer", resolveAddress: { self.resolvedICPAddress(for: $0) }, make: { ICPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.icpHistoryDiagnosticsByWallet, tsKP: \.icpHistoryDiagnosticsLastUpdatedAt) }
    func runICPHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.icp, isRunningKP: \.isRunningICPHistoryDiagnostics, chainName: "Internet Computer", resolveAddress: { self.resolvedICPAddress(for: $0) }, make: { ICPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.icpHistoryDiagnosticsByWallet, tsKP: \.icpHistoryDiagnosticsLastUpdatedAt) }
    func runNearHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.near, isRunningKP: \.isRunningNearHistoryDiagnostics, chainName: "NEAR", resolveAddress: { self.resolvedNearAddress(for: $0) }, make: { NearHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.nearHistoryDiagnosticsByWallet, tsKP: \.nearHistoryDiagnosticsLastUpdatedAt) }
    func runNearHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.near, isRunningKP: \.isRunningNearHistoryDiagnostics, chainName: "NEAR", resolveAddress: { self.resolvedNearAddress(for: $0) }, make: { NearHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.nearHistoryDiagnosticsByWallet, tsKP: \.nearHistoryDiagnosticsLastUpdatedAt) }
    func runPolkadotHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.polkadot, isRunningKP: \.isRunningPolkadotHistoryDiagnostics, chainName: "Polkadot", resolveAddress: { self.resolvedPolkadotAddress(for: $0) }, make: { PolkadotHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.polkadotHistoryDiagnosticsByWallet, tsKP: \.polkadotHistoryDiagnosticsLastUpdatedAt) }
    func runPolkadotHistoryDiagnostics(for walletID: UUID) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.polkadot, isRunningKP: \.isRunningPolkadotHistoryDiagnostics, chainName: "Polkadot", resolveAddress: { self.resolvedPolkadotAddress(for: $0) }, make: { PolkadotHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: $2, error: $3) }, diagsKP: \.polkadotHistoryDiagnosticsByWallet, tsKP: \.polkadotHistoryDiagnosticsLastUpdatedAt) }
    func runAddressHistoryDiagnosticsForAllWallets<Diagnostics>(
        isRunning: () -> Bool, setRunning: (Bool) -> Void, chainName: String, resolveAddress: (ImportedWallet) -> String?, fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (UUID, Diagnostics) -> Void, markUpdated: () -> Void
    ) async {
        guard !isRunning() else { return }
        setRunning(true)
        defer { setRunning(false) }
        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return nil }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            markUpdated()
            return
        }
        for (wallet, address) in walletsToRefresh {
            let diagnostics = await fetchDiagnostics(address)
            storeDiagnostics(wallet.id, diagnostics)
        }
        markUpdated()
    }
    func runAddressHistoryDiagnosticsForWallet<Diagnostics>(
        walletID: UUID, isRunning: () -> Bool, setRunning: (Bool) -> Void, chainName: String, resolveAddress: (ImportedWallet) -> String?, fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (UUID, Diagnostics) -> Void, markUpdated: () -> Void
    ) async {
        guard !isRunning() else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return }
        setRunning(true)
        defer { setRunning(false) }
        let diagnostics = await fetchDiagnostics(address)
        storeDiagnostics(wallet.id, diagnostics)
        markUpdated()
    }
    func runSuiEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingSuiEndpointHealth, checks: SuiBalanceService.diagnosticsChecks(), resultsKP: \.suiEndpointHealthResults, tsKP: \.suiEndpointHealthLastUpdatedAt) }
    func runAptosEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingAptosEndpointHealth, checks: AptosBalanceService.diagnosticsChecks(), resultsKP: \.aptosEndpointHealthResults, tsKP: \.aptosEndpointHealthLastUpdatedAt) }
    func runTONEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingTONEndpointHealth, checks: TONBalanceService.diagnosticsChecks(), resultsKP: \.tonEndpointHealthResults, tsKP: \.tonEndpointHealthLastUpdatedAt) }
    func runICPEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingICPEndpointHealth, checks: ICPBalanceService.diagnosticsChecks(), resultsKP: \.icpEndpointHealthResults, tsKP: \.icpEndpointHealthLastUpdatedAt) }
    func runNearEndpointReachabilityDiagnostics() async {
        guard !isCheckingNearEndpointHealth else { return }
        isCheckingNearEndpointHealth = true
        defer { isCheckingNearEndpointHealth = false }
        var results: [BitcoinEndpointHealthResult] = []
        let rpcEndpoints = Set(NearBalanceService.rpcEndpointCatalog())
        for (endpoint, probeURL) in NearBalanceService.diagnosticsChecks() {
            if rpcEndpoints.contains(endpoint) {
                guard let url = URL(string: endpoint) else {
                    results.append(
                        BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")
                    )
                    continue
                }
                do {
                    let payload = try JSONSerialization.data(withJSONObject: [
                        "jsonrpc": "2.0", "id": "spectra-near-health", "method": "status", "params": []
                    ])
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 15
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = payload
                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinDiagnostics)
                    let http = response as? HTTPURLResponse
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let reachable = http.map { (200 ... 299).contains($0.statusCode) } == true && json?["result"] != nil
                    let detail = reachable ? "OK" : ((json?["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "HTTP \(http?.statusCode ?? -1)")
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: detail
                        )
                    )
                } catch {
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription
                        )
                    )
                }
                continue
            }
            guard let url = URL(string: probeURL) else {
                results.append(
                    BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")
                )
                continue
            }
            let probe = await probeHTTP(url, profile: .litecoinDiagnostics)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail
                )
            )
        }
        nearEndpointHealthResults = results
        nearEndpointHealthLastUpdatedAt = Date()
    }
    func runPolkadotEndpointReachabilityDiagnostics() async {
        guard !isCheckingPolkadotEndpointHealth else { return }
        isCheckingPolkadotEndpointHealth = true
        defer { isCheckingPolkadotEndpointHealth = false }
        var results: [BitcoinEndpointHealthResult] = []
        for (endpoint, probeURL) in PolkadotBalanceService.diagnosticsChecks() {
            if PolkadotBalanceService.sidecarEndpointCatalog().contains(endpoint) {
                guard let url = URL(string: probeURL) else {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                    continue
                }
                do {
                    let (_, response) = try await ProviderHTTP.data(from: url, profile: .litecoinDiagnostics)
                    let http = response as? HTTPURLResponse
                    let reachable = http.map { (200 ... 299).contains($0.statusCode) } ?? false
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: reachable ? "OK" : "HTTP \(http?.statusCode ?? -1)"))
                } catch {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
                }
                continue
            }
            guard let url = URL(string: endpoint) else {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                continue
            }
            do {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0", "id": "spectra-dot-health", "method": "chain_getHeader", "params": []
                ])
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinDiagnostics)
                let http = response as? HTTPURLResponse
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let reachable = http.map { (200 ... 299).contains($0.statusCode) } == true && json?["result"] != nil
                let detail = reachable ? "OK" : ((json?["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "HTTP \(http?.statusCode ?? -1)")
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: detail))
            } catch {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
            }}
        polkadotEndpointHealthResults = results
        polkadotEndpointHealthLastUpdatedAt = Date()
    }
    func runEthereumHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "Ethereum", runningPath: \.isRunningEthereumHistoryDiagnostics, resolveAddress: { self.resolvedEthereumAddress(for: $0) }, diagsPath: \.ethereumHistoryDiagnosticsByWallet, tsPath: \.ethereumHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runEthereumHistoryDiagnostics(for walletID: UUID) async {
        await runEVMHistoryDiagnosticsForWallet(
            walletID: walletID, chainName: "Ethereum", runningPath: \.isRunningEthereumHistoryDiagnostics, resolveAddress: { self.resolvedEthereumAddress(for: $0) }, diagsPath: \.ethereumHistoryDiagnosticsByWallet, tsPath: \.ethereumHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runETCHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "Ethereum Classic", runningPath: \.isRunningETCHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Ethereum Classic") }, diagsPath: \.etcHistoryDiagnosticsByWallet, tsPath: \.etcHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runBNBHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "BNB Chain", runningPath: \.isRunningBNBHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "BNB Chain") }, diagsPath: \.bnbHistoryDiagnosticsByWallet, tsPath: \.bnbHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runArbitrumHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "Arbitrum", runningPath: \.isRunningArbitrumHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Arbitrum") }, diagsPath: \.arbitrumHistoryDiagnosticsByWallet, tsPath: \.arbitrumHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runOptimismHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "Optimism", runningPath: \.isRunningOptimismHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Optimism") }, diagsPath: \.optimismHistoryDiagnosticsByWallet, tsPath: \.optimismHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runAvalancheHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "Avalanche", runningPath: \.isRunningAvalancheHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Avalanche") }, diagsPath: \.avalancheHistoryDiagnosticsByWallet, tsPath: \.avalancheHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runHyperliquidHistoryDiagnostics() async {
        await runEVMHistoryDiagnosticsForAllWallets(
            chainName: "Hyperliquid", runningPath: \.isRunningHyperliquidHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Hyperliquid") }, diagsPath: \.hyperliquidHistoryDiagnosticsByWallet, tsPath: \.hyperliquidHistoryDiagnosticsLastUpdatedAt
        )
    }
    func runBNBHistoryDiagnostics(for walletID: UUID) async {
        await runEVMHistoryDiagnosticsForWallet(
            walletID: walletID, chainName: "BNB Chain", runningPath: \.isRunningBNBHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "BNB Chain") }, diagsPath: \.bnbHistoryDiagnosticsByWallet, tsPath: \.bnbHistoryDiagnosticsLastUpdatedAt
        )
    }
    private static func runningEVMDiagnostics(address: String) -> EthereumTokenTransferHistoryDiagnostics {
        EthereumTokenTransferHistoryDiagnostics(
            address: normalizeEVMAddress(address), rpcTransferCount: 0, rpcError: "Running...", blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: 0, etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "running"
        )
    }
    private static func errorEVMDiagnostics(address: String, error: Error) -> EthereumTokenTransferHistoryDiagnostics {
        EthereumTokenTransferHistoryDiagnostics(
            address: normalizeEVMAddress(address), rpcTransferCount: 0, rpcError: error.localizedDescription, blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: 0, etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "none"
        )
    }
    private func runEVMHistoryDiagnosticsForAllWallets(
        chainName: String, runningPath: ReferenceWritableKeyPath<WalletStore, Bool>, resolveAddress: (ImportedWallet) -> String?, diagsPath: ReferenceWritableKeyPath<WalletStore, [UUID: EthereumTokenTransferHistoryDiagnostics]>, tsPath: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        guard !self[keyPath: runningPath] else { return }
        self[keyPath: runningPath] = true
        defer { self[keyPath: runningPath] = false }
        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName, let addr = resolveAddress(wallet) else { return nil }
            return (wallet, addr)
        }
        guard !walletsToRefresh.isEmpty else { self[keyPath: tsPath] = Date(); return }
        for (wallet, address) in walletsToRefresh {
            self[keyPath: diagsPath][wallet.id] = Self.runningEVMDiagnostics(address: address)
            self[keyPath: tsPath] = Date()
            do {
                self[keyPath: diagsPath][wallet.id] = try await Self.rustEVMHistoryDiagnostics(chainName: chainName, address: address)
            } catch {
                self[keyPath: diagsPath][wallet.id] = Self.errorEVMDiagnostics(address: address, error: error)
            }}
        self[keyPath: tsPath] = Date()
    }
    private func runEVMHistoryDiagnosticsForWallet(
        walletID: UUID, chainName: String, runningPath: ReferenceWritableKeyPath<WalletStore, Bool>, resolveAddress: (ImportedWallet) -> String?, diagsPath: ReferenceWritableKeyPath<WalletStore, [UUID: EthereumTokenTransferHistoryDiagnostics]>, tsPath: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        guard !self[keyPath: runningPath] else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return }
        self[keyPath: runningPath] = true
        defer { self[keyPath: runningPath] = false }
        self[keyPath: diagsPath][wallet.id] = Self.runningEVMDiagnostics(address: address)
        self[keyPath: tsPath] = Date()
        do {
            self[keyPath: diagsPath][wallet.id] = try await Self.rustEVMHistoryDiagnostics(chainName: chainName, address: address)
        } catch {
            self[keyPath: diagsPath][wallet.id] = Self.errorEVMDiagnostics(address: address, error: error)
        }
        self[keyPath: tsPath] = Date()
    }
    private static func rustEVMHistoryDiagnostics(chainName: String, address: String) async throws -> EthereumTokenTransferHistoryDiagnostics {
        guard let chainId = SpectraChainID.id(for: chainName) else { throw WalletServiceBridgeError.unsupportedChain(chainName) }
        let historyJSON = try await WalletServiceBridge.shared.fetchEVMHistoryPageJSON(
            chainId: chainId, address: address, tokens: [], page: 1, pageSize: 50
        )
        let count: Int
        if let data = historyJSON.data(using: .utf8), let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let native = obj["native"] as? [[String: Any]] { count = native.count } else { count = 0 }
        return EthereumTokenTransferHistoryDiagnostics(
            address: normalizeEVMAddress(address), rpcTransferCount: 0, rpcError: nil, blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: count, etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "rust"
        )
    }
    func runEthereumEndpointReachabilityDiagnostics() async {
        guard !isCheckingEthereumEndpointHealth else { return }
        isCheckingEthereumEndpointHealth = true
        defer { isCheckingEthereumEndpointHealth = false }
        let context = evmChainContext(for: "Ethereum") ?? .ethereum
        var checks = evmEndpointChecks(chainName: "Ethereum", context: context)
        checks.append(contentsOf: ChainBackendRegistry.EVMExplorerRegistry.diagnosticProbeEntries(for: ChainBackendRegistry.ethereumChainName).map { ($0.0, $0.1, false) })
        await runLabeledEVMEndpointDiagnostics(
            checks: checks, setResults: { self.ethereumEndpointHealthResults = $0 }, markUpdated: { self.ethereumEndpointHealthLastUpdatedAt = Date() }
        )
    }
    func runETCEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingETCEndpointHealth, chainName: "Ethereum Classic", context: .ethereumClassic, resultsKP: \.etcEndpointHealthResults, tsKP: \.etcEndpointHealthLastUpdatedAt) }
    func runArbitrumEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingArbitrumEndpointHealth, chainName: "Arbitrum", context: .arbitrum, resultsKP: \.arbitrumEndpointHealthResults, tsKP: \.arbitrumEndpointHealthLastUpdatedAt) }
    func runOptimismEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingOptimismEndpointHealth, chainName: "Optimism", context: .optimism, resultsKP: \.optimismEndpointHealthResults, tsKP: \.optimismEndpointHealthLastUpdatedAt) }
    func runAvalancheEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingAvalancheEndpointHealth, chainName: "Avalanche", context: .avalanche, resultsKP: \.avalancheEndpointHealthResults, tsKP: \.avalancheEndpointHealthLastUpdatedAt) }
    func runHyperliquidEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingHyperliquidEndpointHealth, chainName: "Hyperliquid", context: .hyperliquid, resultsKP: \.hyperliquidEndpointHealthResults, tsKP: \.hyperliquidEndpointHealthLastUpdatedAt) }
    func runBNBEndpointReachabilityDiagnostics() async {
        guard !isCheckingBNBEndpointHealth else { return }
        isCheckingBNBEndpointHealth = true
        defer { isCheckingBNBEndpointHealth = false }
        var checks = evmEndpointChecks(chainName: "BNB Chain", context: .bnb)
        checks.append(contentsOf: ChainBackendRegistry.EVMExplorerRegistry.diagnosticProbeEntries(for: ChainBackendRegistry.bnbChainName).map { ($0.0, $0.1, false) })
        await runLabeledEVMEndpointDiagnostics(checks: checks, setResults: { self.bnbEndpointHealthResults = $0 }, markUpdated: { self.bnbEndpointHealthLastUpdatedAt = Date() })
    }
    func evmEndpointChecks(chainName: String, context: EVMChainContext) -> [(label: String, endpoint: URL, isRPC: Bool)] {
        var checks: [(label: String, endpoint: URL, isRPC: Bool)] = []
        if let configured = configuredEVMRPCEndpointURL(for: chainName) { checks.append(("Configured RPC", configured, true)) }
        for rpc in context.defaultRPCEndpoints {
            guard let url = URL(string: rpc), !checks.contains(where: { $0.endpoint == url }) else {
                continue
            }
            checks.append(("Fallback RPC", url, true))
        }
        return checks
    }
    func runSimpleEndpointReachabilityDiagnostics(
        checks: [(endpoint: String, probeURL: String)], profile: NetworkRetryProfile, setResults: ([BitcoinEndpointHealthResult]) -> Void, markUpdated: () -> Void
    ) async {
        var results: [BitcoinEndpointHealthResult] = []
        for check in checks {
            guard let url = URL(string: check.probeURL) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: check.endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"
                    )
                )
                continue
            }
            let probe = await probeHTTP(url, profile: profile)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: check.endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail
                )
            )
        }
        setResults(results)
        markUpdated()
    }
    func runLabeledEVMEndpointDiagnostics(
        checks: [(label: String, endpoint: URL, isRPC: Bool)], setResults: ([EthereumEndpointHealthResult]) -> Void, markUpdated: () -> Void
    ) async {
        var results: [EthereumEndpointHealthResult] = []
        for check in checks {
            let probe: (reachable: Bool, statusCode: Int?, detail: String)
            if check.isRPC { probe = await probeEthereumRPC(check.endpoint) } else { probe = await probeHTTP(check.endpoint) }
            results.append(
                EthereumEndpointHealthResult(
                    label: check.label, endpoint: check.endpoint.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail
                )
            )
        }
        setResults(results)
        markUpdated()
    }
    private func runSimpleEndpointDiagnostics(
        isCheckingKP: ReferenceWritableKeyPath<WalletStore, Bool>, checks: [(endpoint: String, probeURL: String)], resultsKP: ReferenceWritableKeyPath<WalletStore, [BitcoinEndpointHealthResult]>, tsKP: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true
        defer { self[keyPath: isCheckingKP] = false }
        await runSimpleEndpointReachabilityDiagnostics(checks: checks, profile: .litecoinDiagnostics, setResults: { self[keyPath: resultsKP] = $0 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runPureEVMEndpointDiagnostics(isCheckingKP: ReferenceWritableKeyPath<WalletStore, Bool>, chainName: String, context: EVMChainContext, resultsKP: ReferenceWritableKeyPath<WalletStore, [EthereumEndpointHealthResult]>, tsKP: ReferenceWritableKeyPath<WalletStore, Date?>) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true
        defer { self[keyPath: isCheckingKP] = false }
        let checks = evmEndpointChecks(chainName: chainName, context: context)
        await runLabeledEVMEndpointDiagnostics(checks: checks, setResults: { self[keyPath: resultsKP] = $0 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    func withTimeout<T>(
        seconds: Double, operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut(seconds: seconds)
            }
            guard let firstResult = try await group.next() else { throw TimeoutError.timedOut(seconds: seconds) }
            group.cancelAll()
            return firstResult
        }}
    func probeHTTP(_ url: URL, profile: NetworkRetryProfile = .diagnostics) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (_, response) = try await NetworkResilience.data(for: request, profile: profile)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                if let statusCode {
                    let isSuccess = (200 ..< 300).contains(statusCode)
                    return (isSuccess, statusCode, "HTTP \(statusCode)")
                }
                return (true, nil, "Connected")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }}
    func probeEthereumRPC(_ url: URL) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = """
                {"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}
                """.data(using: .utf8)
                let (data, response) = try await ProviderHTTP.sessionData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                if let statusCode, (200 ..< 300).contains(statusCode) {
                    let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (true, statusCode, trimmed.isEmpty ? "OK" : String(trimmed.prefix(120)))
                }
                return (false, statusCode, "HTTP \(statusCode ?? -1)")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }}
    func refreshPendingBitcoinTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Bitcoin", chainId: SpectraChainID.bitcoin) }
    func refreshPendingBitcoinCashTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash) }
    func refreshPendingBitcoinSVTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv) }
    func refreshPendingLitecoinTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Litecoin", chainId: SpectraChainID.litecoin, requireSendKind: false) }
    private func refreshPendingUTXOChainTransactions(chainName: String, chainId: UInt32, requireSendKind: Bool = true) async {
        let now = Date()
        let pendingTransactions = transactions.filter { (requireSendKind ? $0.kind == .send : true) && $0.chainName == chainName && $0.status == .pending && $0.transactionHash != nil }
        guard !pendingTransactions.isEmpty else { return }
        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(chainId: chainId, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let confirmed = obj["confirmed"] as? Bool ?? false
                let blockHeight = obj["block_height"] as? Int
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: confirmed ? .confirmed : .pending, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(status: confirmed ? .confirmed : .pending, receiptBlockNumber: blockHeight, confirmations: nil, dogecoinNetworkFeeDOGE: nil)
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
            }}
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: stalePendingFailureIDs(from: pendingTransactions, now: now), now: now)
    }
    func refreshPendingDogecoinTransactions() async {
        let now = Date()
        let trackedTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Dogecoin"
                && (transaction.status == .pending || transaction.status == .confirmed)
                && transaction.transactionHash != nil
        }
        guard !trackedTransactions.isEmpty else {
            statusTrackingByTransactionID = [:]
            return
        }
        let trackedIDs = Set(trackedTransactions.map(\.id))
        statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedIDs.contains($0.key) }
        var resolvedStatuses: [UUID: DogecoinTransactionStatus] = [:]
        for transaction in trackedTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            if !shouldPollDogecoinStatus(for: transaction, now: now) { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(
                    chainId: SpectraChainID.dogecoin, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let status = DogecoinTransactionStatus(
                    confirmed: obj["confirmed"] as? Bool ?? false, blockHeight: obj["block_height"] as? Int, networkFeeDOGE: nil, confirmations: (obj["confirmations"] as? Int)
                )
                resolvedStatuses[transaction.id] = status
                markDogecoinStatusPollSuccess(for: transaction, status: status, now: now)
            } catch {
                markDogecoinStatusPollFailure(for: transaction, now: now)
                continue
            }}
        let staleFailureCandidates = trackedTransactions.filter { transaction in
            guard transaction.status == .pending else { return false }
            let age = now.timeIntervalSince(transaction.createdAt)
            guard age >= Self.pendingFailureTimeoutSeconds else { return false }
            let tracker = statusTrackingByTransactionID[transaction.id]
            return (tracker?.consecutiveFailures ?? 0) >= Self.pendingFailureMinFailures
        }
        let staleFailureIDs = Set(staleFailureCandidates.map { $0.id })
        guard !resolvedStatuses.isEmpty || !staleFailureIDs.isEmpty else { return }
        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        transactions = transactions.map { transaction in
            if let status = resolvedStatuses[transaction.id] {
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                let resolvedConfirmations = status.confirmations ?? transaction.dogecoinConfirmations
                let reachedFinality = (resolvedConfirmations ?? 0) >= Self.standardFinalityConfirmations
                if reachedFinality {
                    var tracker = statusTrackingByTransactionID[transaction.id] ?? DogecoinStatusTrackingState.initial(now: now)
                    tracker.reachedFinality = true
                    tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
                    statusTrackingByTransactionID[transaction.id] = tracker
                }
                return TransactionRecord(
                    id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: resolvedStatus, walletName: transaction.walletName, assetName: transaction.assetName, symbol: transaction.symbol, chainName: transaction.chainName, amount: transaction.amount, address: transaction.address, transactionHash: transaction.transactionHash, receiptBlockNumber: status.blockHeight, receiptGasUsed: transaction.receiptGasUsed, receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei, receiptNetworkFeeETH: transaction.receiptNetworkFeeETH, feePriorityRaw: transaction.feePriorityRaw, feeRateDescription: transaction.feeRateDescription, confirmationCount: resolvedConfirmations, dogecoinConfirmedNetworkFeeDOGE: status.networkFeeDOGE ?? transaction.dogecoinConfirmedNetworkFeeDOGE, dogecoinConfirmations: resolvedConfirmations, dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB, usedChangeOutput: transaction.usedChangeOutput, dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput, dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex, failureReason: nil, transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt
                )
            }
            guard staleFailureIDs.contains(transaction.id) else { return transaction }
            return TransactionRecord(
                id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: .failed, walletName: transaction.walletName, assetName: transaction.assetName, symbol: transaction.symbol, chainName: transaction.chainName, amount: transaction.amount, address: transaction.address, transactionHash: transaction.transactionHash, receiptBlockNumber: transaction.receiptBlockNumber, receiptGasUsed: transaction.receiptGasUsed, receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei, receiptNetworkFeeETH: transaction.receiptNetworkFeeETH, feePriorityRaw: transaction.feePriorityRaw, feeRateDescription: transaction.feeRateDescription, confirmationCount: transaction.confirmationCount, dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE, dogecoinConfirmations: transaction.dogecoinConfirmations, dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB, usedChangeOutput: transaction.usedChangeOutput, dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput, dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex, failureReason: transaction.failureReason ?? localizedStoreString("Dogecoin transaction appears stuck and could not be confirmed after extended retries."), transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt
            )
        }
        for (transactionID, status) in resolvedStatuses {
            guard let oldTransaction = oldByID[transactionID], let newTransaction = transactions.first(where: { $0.id == transactionID }) else {
                continue
            }
            if oldTransaction.status != .confirmed, status.confirmed {
                appendChainOperationalEvent(
                    .info, chainName: "Dogecoin", message: localizedStoreString("DOGE transaction confirmed."), transactionHash: newTransaction.transactionHash
                )
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }
            if oldTransaction.dogecoinConfirmations != newTransaction.dogecoinConfirmations, newTransaction.status == .confirmed, let confirmations = newTransaction.dogecoinConfirmations, confirmations >= Self.standardFinalityConfirmations, oldTransaction.dogecoinConfirmations ?? 0 < Self.standardFinalityConfirmations {
                appendChainOperationalEvent(
                    .info, chainName: "Dogecoin", message: localizedStoreFormat("DOGE transaction reached finality (%d confirmations).", confirmations), transactionHash: newTransaction.transactionHash
                )
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }}
        for failedID in staleFailureIDs {
            guard let oldTransaction = oldByID[failedID], oldTransaction.status != .failed else { continue }
            appendChainOperationalEvent(
                .error, chainName: "Dogecoin", message: localizedStoreString("DOGE transaction marked failed after extended retries."), transactionHash: oldTransaction.transactionHash
            )
            sendTransactionStatusNotification(for: oldTransaction, newStatus: .failed)
        }}
    func refreshPendingTronTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Tron", chainId: SpectraChainID.tron, addressResolver: resolvedTronAddress) }
    func refreshPendingSolanaTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Solana", chainId: SpectraChainID.solana, addressResolver: resolvedSolanaAddress) }
    func refreshPendingCardanoTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Cardano", chainId: SpectraChainID.cardano, addressResolver: resolvedCardanoAddress) }
    func refreshPendingXRPTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "XRP Ledger", chainId: SpectraChainID.xrp, addressResolver: resolvedXRPAddress) }
    func refreshPendingStellarTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Stellar", chainId: SpectraChainID.stellar, addressResolver: resolvedStellarAddress) }
    func refreshPendingMoneroTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Monero", chainId: SpectraChainID.monero, addressResolver: resolvedMoneroAddress) }
    func refreshPendingSuiTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Sui", chainId: SpectraChainID.sui, addressResolver: resolvedSuiAddress) }
    func refreshPendingAptosTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Aptos", chainId: SpectraChainID.aptos, addressResolver: resolvedAptosAddress) }
    func refreshPendingTONTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "TON", chainId: SpectraChainID.ton, addressResolver: resolvedTONAddress) }
    func refreshPendingICPTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Internet Computer", chainId: SpectraChainID.icp, addressResolver: resolvedICPAddress) }
    func refreshPendingNearTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "NEAR", chainId: SpectraChainID.near, addressResolver: resolvedNearAddress) }
    func refreshPendingPolkadotTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Polkadot", chainId: SpectraChainID.polkadot, addressResolver: resolvedPolkadotAddress) }
    private func refreshPendingRustHistoryChainTransactions(chainName: String, chainId: UInt32, addressResolver: (ImportedWallet) -> String?) async {
        await refreshPendingHistoryBackedTransactions(chainName: chainName, addressResolver: addressResolver) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address)
            else { return ([:], true) }
            return (self.rustHistoryStatusMap(json: json), false)
        }}
    private func runRustHistoryDiagnosticsForAllWallets<D>(
        chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<WalletStore, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D, diagsKP: ReferenceWritableKeyPath<WalletStore, [UUID: D]>, tsKP: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) }, storeDiagnostics: { self[keyPath: diagsKP][$0] = $1 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runRustHistoryDiagnosticsForWallet<D>(
        walletID: UUID, chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<WalletStore, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D, diagsKP: ReferenceWritableKeyPath<WalletStore, [UUID: D]>, tsKP: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) }, storeDiagnostics: { self[keyPath: diagsKP][$0] = $1 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnostics(
        chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<WalletStore, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, diagsKP: ReferenceWritableKeyPath<WalletStore, [UUID: BitcoinHistoryDiagnostics]>, tsKP: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { address in
                let count = (try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address)).map { self.decodeRustHistoryJSON(json: $0).count } ?? 0
                return BitcoinHistoryDiagnostics(walletID: UUID(), identifier: address, sourceUsed: "rust", transactionCount: count, nextCursor: nil, error: nil)
            }, storeDiagnostics: { walletID, d in self[keyPath: diagsKP][walletID] = BitcoinHistoryDiagnostics(walletID: walletID, identifier: d.identifier, sourceUsed: d.sourceUsed, transactionCount: d.transactionCount, nextCursor: d.nextCursor, error: d.error) }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnosticsForWallet(
        walletID: UUID, chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<WalletStore, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, diagsKP: ReferenceWritableKeyPath<WalletStore, [UUID: BitcoinHistoryDiagnostics]>, tsKP: ReferenceWritableKeyPath<WalletStore, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { address in
                let count = (try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address)).map { self.decodeRustHistoryJSON(json: $0).count } ?? 0
                return BitcoinHistoryDiagnostics(walletID: walletID, identifier: address, sourceUsed: "rust", transactionCount: count, nextCursor: nil, error: nil)
            }, storeDiagnostics: { _, d in self[keyPath: diagsKP][walletID] = d }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func rustHistoryFetch<D>(
        chainId: UInt32, address: String, make: (String, String, Int, String?) -> D
    ) async -> D {
        if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address) { return make(address, "rust", decodeRustHistoryJSON(json: json).count, nil) }
        return make(address, "none", 0, "History fetch failed")
    }
    private func rustHistoryStatusMap(json: String) -> [String: TransactionStatus] {
        var statusByHash: [String: TransactionStatus] = [:]
        for entry in decodeRustHistoryJSON(json: json) {
            if let txid = (entry["txid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !txid.isEmpty { statusByHash[txid] = .confirmed }}
        return statusByHash
    }
}
