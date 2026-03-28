import Foundation

private struct WalletChainRefreshDescriptor {
    let chainID: WalletChainID
    let executeRefresh: (WalletStore, Bool) async -> Void
    let executeBalancesOnly: (WalletStore) async -> Void
    let executeHistoryOnly: ((WalletStore) async -> Void)?

    var chainName: String { chainID.displayName }
}

extension WalletStore {
    private var lastHistoryRefreshAtByChainID: [WalletChainID: Date] {
        get {
            Dictionary(
                uniqueKeysWithValues: lastHistoryRefreshAtByChain.compactMap { key, value in
                    WalletChainID(key).map { ($0, value) }
                }
            )
        }
        set {
            lastHistoryRefreshAtByChain = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.displayName, $0.value) }
            )
        }
    }

    private var plannedChainRefreshDescriptors: [WalletChainRefreshDescriptor] {
        [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBitcoinBalances()
                    if refreshHistory {
                        await store.refreshBitcoinTransactions(limit: store.bitcoinHistoryFetchLimit, loadMore: false)
                    }
                    await store.refreshPendingBitcoinTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBitcoinBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin Cash")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBitcoinCashBalances()
                    if refreshHistory {
                        await store.refreshBitcoinCashTransactions(limit: store.bitcoinHistoryFetchLimit, loadMore: false)
                    }
                    await store.refreshPendingBitcoinCashTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBitcoinCashBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin SV")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBitcoinSVBalances()
                    if refreshHistory {
                        await store.refreshBitcoinSVTransactions(limit: store.bitcoinHistoryFetchLimit, loadMore: false)
                    }
                    await store.refreshPendingBitcoinSVTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBitcoinSVBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Litecoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshLitecoinBalances()
                    if refreshHistory {
                        await store.refreshLitecoinTransactions(limit: store.litecoinHistoryFetchLimit, loadMore: false)
                    }
                    await store.refreshPendingLitecoinTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshLitecoinBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Dogecoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshDogecoinAddressDiscovery()
                    await store.refreshDogecoinReceiveReservationState()
                    await store.refreshDogecoinBalances()
                    if refreshHistory {
                        await store.refreshDogecoinTransactions(loadMore: false)
                    }
                    await store.refreshPendingDogecoinTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshDogecoinBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Ethereum")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshEthereumBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Ethereum", loadMore: false)
                    }
                    await store.refreshPendingEthereumTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshEthereumBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Ethereum")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Arbitrum")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshArbitrumBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Arbitrum", loadMore: false)
                    }
                    await store.refreshPendingArbitrumTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshArbitrumBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Arbitrum")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Optimism")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshOptimismBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Optimism", loadMore: false)
                    }
                    await store.refreshPendingOptimismTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshOptimismBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Optimism")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Ethereum Classic")!,
                executeRefresh: { store, _ in
                    await store.refreshETCBalances()
                    await store.refreshPendingETCTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshETCBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("BNB Chain")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBNBBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "BNB Chain", loadMore: false)
                    }
                    await store.refreshPendingBNBTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBNBBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "BNB Chain")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Avalanche")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshAvalancheBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Avalanche", loadMore: false)
                    }
                    await store.refreshPendingAvalancheTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshAvalancheBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Hyperliquid")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshHyperliquidBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", loadMore: false)
                    }
                    await store.refreshPendingHyperliquidTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshHyperliquidBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Hyperliquid")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Tron")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshTronBalances()
                    if refreshHistory {
                        await store.refreshTronTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshTronBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshTronTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Solana")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshSolanaBalances()
                    if refreshHistory {
                        await store.refreshSolanaTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshSolanaBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshSolanaTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Cardano")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshCardanoBalances()
                    if refreshHistory {
                        await store.refreshCardanoTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshCardanoBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshCardanoTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("XRP Ledger")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshXRPBalances()
                    if refreshHistory {
                        await store.refreshXRPTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshXRPBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshXRPTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Stellar")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshStellarBalances()
                    if refreshHistory {
                        await store.refreshStellarTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshStellarBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshStellarTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Monero")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshMoneroBalances()
                    if refreshHistory {
                        await store.refreshMoneroTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshMoneroBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshMoneroTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Sui")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshSuiBalances()
                    if refreshHistory {
                        await store.refreshSuiTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshSuiBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshSuiTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("NEAR")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshNearBalances()
                    if refreshHistory {
                        await store.refreshNearTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshNearBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshNearTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Polkadot")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshPolkadotBalances()
                    if refreshHistory {
                        await store.refreshPolkadotTransactions(loadMore: false)
                    }
                },
                executeBalancesOnly: { store in
                    await store.refreshPolkadotBalances()
                },
                executeHistoryOnly: nil
            )
        ]
    }

    private var importedWalletRefreshDescriptors: [WalletChainRefreshDescriptor] {
        plannedChainRefreshDescriptors + [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Aptos")!,
                executeRefresh: { store, _ in
                    await store.refreshAptosBalances()
                },
                executeBalancesOnly: { store in
                    await store.refreshAptosBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Internet Computer")!,
                executeRefresh: { store, _ in
                    await store.refreshICPBalances()
                },
                executeBalancesOnly: { store in
                    await store.refreshICPBalances()
                },
                executeHistoryOnly: nil
            )
        ]
    }

    func runPlannedChainRefreshes(
        using refreshPlanByChain: [WalletChainID: Bool],
        timeout: Double
    ) async {
        for descriptor in plannedChainRefreshDescriptors {
            guard let refreshHistory = refreshPlanByChain[descriptor.chainID] else { continue }
            await runTimedChainRefresh(
                descriptor.chainID,
                refreshHistory: refreshHistory,
                timeout: timeout
            ) {
                await descriptor.executeRefresh(self, refreshHistory)
            }
        }
    }

    func refreshImportedWalletBalances(forChains chainNames: Set<String>) async {
        for descriptor in importedWalletRefreshDescriptors where chainNames.contains(descriptor.chainName) {
            await descriptor.executeBalancesOnly(self)
        }
    }

    func runPendingTransactionHistoryRefreshes(
        for trackedChains: Set<WalletChainID>,
        interval: TimeInterval
    ) async {
        let plannedHistoryChains = Set(
            WalletRefreshPlanner.historyPlans(
                for: trackedChains,
                now: Date(),
                interval: interval,
                lastHistoryRefreshAtByChainID: lastHistoryRefreshAtByChainID
            )
        )
        guard !plannedHistoryChains.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for descriptor in plannedChainRefreshDescriptors {
                guard plannedHistoryChains.contains(descriptor.chainID),
                      let executeHistoryOnly = descriptor.executeHistoryOnly else {
                    continue
                }
                group.addTask {
                    await executeHistoryOnly(self)
                }
            }
            await group.waitForAll()
        }
    }

    private func runTimedChainRefresh(
        _ chainID: WalletChainID,
        refreshHistory: Bool,
        timeout: Double,
        operation: @escaping () async -> Void
    ) async {
        let chainName = chainID.displayName
        do {
            try await withTimeout(seconds: timeout) {
                await operation()
                return ()
            }
            if refreshHistory {
                lastHistoryRefreshAtByChainID[chainID] = Date()
            }
        } catch {
            markChainDegraded(chainName, detail: "\(chainName) refresh timed out. Using cached balances and history.")
            appendOperationalLog(
                .warning,
                category: "Chain Sync",
                message: "\(chainName) refresh timeout",
                chainName: chainName,
                source: "timeout",
                metadata: error.localizedDescription
            )
        }
    }
}
