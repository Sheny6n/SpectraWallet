import Foundation
struct WalletChainRefreshDescriptor {
    let chainID: WalletChainID
    let executeRefresh: (WalletStore, Bool) async -> Void
    let executeBalancesOnly: (WalletStore) async -> Void
    let executeHistoryOnly: ((WalletStore) async -> Void)?
    var chainName: String { chainID.displayName }
    init(
        chainID: WalletChainID, executeRefresh: @escaping (WalletStore, Bool) async -> Void, executeBalancesOnly: @escaping (WalletStore) async -> Void = { await $0.refreshBalances() }, executeHistoryOnly: ((WalletStore) async -> Void)? = nil
    ) {
        self.chainID = chainID
        self.executeRefresh = executeRefresh
        self.executeBalancesOnly = executeBalancesOnly
        self.executeHistoryOnly = executeHistoryOnly
    }
}
extension WalletStore {
    var lastHistoryRefreshAtByChainID: [WalletChainID: Date] {
        get {
            Dictionary(
                uniqueKeysWithValues: lastHistoryRefreshAtByChain.compactMap { key, value in
                    WalletChainID(key).map { ($0, value) }}
            )
        }
        set {
            lastHistoryRefreshAtByChain = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.displayName, $0.value) }
            )
        }}
    var plannedChainRefreshDescriptors: [WalletChainRefreshDescriptor] {
        [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshBitcoinTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingBitcoinTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin Cash")!, executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin Cash")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin Cash")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshBitcoinCashTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingBitcoinCashTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin SV")!, executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin SV")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin SV")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshBitcoinSVTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingBitcoinSVTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Litecoin")!, executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Litecoin")
                    await store.refreshUTXOReceiveReservationState(chainName: "Litecoin")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshLitecoinTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingLitecoinTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Dogecoin")!, executeRefresh: { store, refreshHistory in
                    await store.refreshDogecoinAddressDiscovery()
                    await store.refreshDogecoinReceiveReservationState()
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshDogecoinTransactions(loadMore: false) }
                    await store.refreshPendingDogecoinTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Ethereum")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshEVMTokenTransactions(chainName: "Ethereum", loadMore: false) }
                    await store.refreshPendingEthereumTransactions()
                }, executeHistoryOnly: { store in await store.refreshEVMTokenTransactions(chainName: "Ethereum") }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Arbitrum")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshEVMTokenTransactions(chainName: "Arbitrum", loadMore: false) }
                    await store.refreshPendingArbitrumTransactions()
                }, executeHistoryOnly: { store in await store.refreshEVMTokenTransactions(chainName: "Arbitrum") }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Optimism")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshEVMTokenTransactions(chainName: "Optimism", loadMore: false) }
                    await store.refreshPendingOptimismTransactions()
                }, executeHistoryOnly: { store in await store.refreshEVMTokenTransactions(chainName: "Optimism") }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Ethereum Classic")!, executeRefresh: { store, _ in
                    await store.refreshBalances()
                    await store.refreshPendingETCTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("BNB Chain")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshEVMTokenTransactions(chainName: "BNB Chain", loadMore: false) }
                    await store.refreshPendingBNBTransactions()
                }, executeHistoryOnly: { store in await store.refreshEVMTokenTransactions(chainName: "BNB Chain") }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Avalanche")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshEVMTokenTransactions(chainName: "Avalanche", loadMore: false) }
                    await store.refreshPendingAvalancheTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Hyperliquid")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", loadMore: false) }
                    await store.refreshPendingHyperliquidTransactions()
                }, executeHistoryOnly: { store in await store.refreshEVMTokenTransactions(chainName: "Hyperliquid") }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Tron")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshTronTransactions(loadMore: false) }
                    await store.refreshPendingTronTransactions()
                }, executeHistoryOnly: { store in await store.refreshTronTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Solana")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshSolanaTransactions(loadMore: false) }
                    await store.refreshPendingSolanaTransactions()
                }, executeHistoryOnly: { store in await store.refreshSolanaTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Cardano")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshCardanoTransactions(loadMore: false) }
                    await store.refreshPendingCardanoTransactions()
                }, executeHistoryOnly: { store in await store.refreshCardanoTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("XRP Ledger")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshXRPTransactions(loadMore: false) }
                    await store.refreshPendingXRPTransactions()
                }, executeHistoryOnly: { store in await store.refreshXRPTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Stellar")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshStellarTransactions(loadMore: false) }
                    await store.refreshPendingStellarTransactions()
                }, executeHistoryOnly: { store in await store.refreshStellarTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Monero")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshMoneroTransactions(loadMore: false) }
                    await store.refreshPendingMoneroTransactions()
                }, executeHistoryOnly: { store in await store.refreshMoneroTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Sui")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshSuiTransactions(loadMore: false) }
                    await store.refreshPendingSuiTransactions()
                }, executeHistoryOnly: { store in await store.refreshSuiTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("NEAR")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshNearTransactions(loadMore: false) }
                    await store.refreshPendingNearTransactions()
                }, executeHistoryOnly: { store in await store.refreshNearTransactions(loadMore: false) }
            ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Polkadot")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshPolkadotTransactions(loadMore: false) }
                    await store.refreshPendingPolkadotTransactions()
                }, )
        ]
    }
    var importedWalletRefreshDescriptors: [WalletChainRefreshDescriptor] {
        plannedChainRefreshDescriptors + [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Aptos")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshAptosTransactions(loadMore: false) }
                    await store.refreshPendingAptosTransactions()
                }, ), WalletChainRefreshDescriptor(
                chainID: WalletChainID("Internet Computer")!, executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshICPTransactions(loadMore: false) }
                    await store.refreshPendingICPTransactions()
                }, )
        ]
    }
}
