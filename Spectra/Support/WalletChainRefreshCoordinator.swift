import Foundation

private struct WalletChainRefreshDescriptor {
    let chainName: String
    let executeRefresh: (WalletStore, Bool) async -> Void
    let executeBalancesOnly: (WalletStore) async -> Void
    let executeHistoryOnly: ((WalletStore) async -> Void)?
}

extension WalletStore {
    private var plannedChainRefreshDescriptors: [WalletChainRefreshDescriptor] {
        [
            WalletChainRefreshDescriptor(
                chainName: "Bitcoin",
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
                chainName: "Bitcoin Cash",
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
                chainName: "Bitcoin SV",
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
                chainName: "Litecoin",
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
                chainName: "Dogecoin",
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
                chainName: "Ethereum",
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
                chainName: "Arbitrum",
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
                chainName: "Optimism",
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
                chainName: "Ethereum Classic",
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
                chainName: "BNB Chain",
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
                chainName: "Avalanche",
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
                chainName: "Hyperliquid",
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
                chainName: "Tron",
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
                chainName: "Solana",
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
                chainName: "Cardano",
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
                chainName: "XRP Ledger",
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
                chainName: "Stellar",
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
                chainName: "Monero",
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
                chainName: "Sui",
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
                chainName: "NEAR",
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
                chainName: "Polkadot",
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
                chainName: "Aptos",
                executeRefresh: { store, _ in
                    await store.refreshAptosBalances()
                },
                executeBalancesOnly: { store in
                    await store.refreshAptosBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainName: "Internet Computer",
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
        using refreshPlanByChain: [String: Bool],
        timeout: Double
    ) async {
        for descriptor in plannedChainRefreshDescriptors {
            guard let refreshHistory = refreshPlanByChain[descriptor.chainName] else { continue }
            await runTimedChainRefresh(
                descriptor.chainName,
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
        for trackedChains: Set<String>,
        interval: TimeInterval
    ) async {
        let plannedHistoryChains = Set(
            WalletRefreshPlanner.historyPlans(
                for: trackedChains,
                interval: interval,
                lastHistoryRefreshAtByChain: lastHistoryRefreshAtByChain
            )
        )
        guard !plannedHistoryChains.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for descriptor in plannedChainRefreshDescriptors {
                guard plannedHistoryChains.contains(descriptor.chainName),
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
        _ chainName: String,
        refreshHistory: Bool,
        timeout: Double,
        operation: @escaping () async -> Void
    ) async {
        do {
            try await withTimeout(seconds: timeout) {
                await operation()
                return ()
            }
            if refreshHistory {
                lastHistoryRefreshAtByChain[chainName] = Date()
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
