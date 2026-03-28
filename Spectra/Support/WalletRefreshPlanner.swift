import Foundation

struct WalletRefreshChainPlan: Hashable {
    let chainName: String
    let refreshHistory: Bool
}

struct WalletActiveMaintenancePlan {
    let refreshPendingTransactions: Bool
    let refreshLivePrices: Bool
}

struct WalletRefreshPlanner {
    static func activeMaintenancePlan(
        now: Date,
        lastPendingTransactionRefreshAt: Date?,
        lastLivePriceRefreshAt: Date?,
        hasPendingTransactionMaintenanceWork: Bool,
        shouldRunScheduledPriceRefresh: Bool,
        pendingRefreshInterval: TimeInterval,
        priceRefreshInterval: TimeInterval
    ) -> WalletActiveMaintenancePlan {
        let shouldRefreshPendingTransactions: Bool
        if let lastPendingTransactionRefreshAt {
            shouldRefreshPendingTransactions =
                hasPendingTransactionMaintenanceWork &&
                now.timeIntervalSince(lastPendingTransactionRefreshAt) >= pendingRefreshInterval
        } else {
            shouldRefreshPendingTransactions = hasPendingTransactionMaintenanceWork
        }

        let shouldRefreshLivePrices: Bool
        if let lastLivePriceRefreshAt {
            shouldRefreshLivePrices =
                shouldRunScheduledPriceRefresh &&
                now.timeIntervalSince(lastLivePriceRefreshAt) >= priceRefreshInterval
        } else {
            shouldRefreshLivePrices = shouldRunScheduledPriceRefresh
        }

        return WalletActiveMaintenancePlan(
            refreshPendingTransactions: shouldRefreshPendingTransactions,
            refreshLivePrices: shouldRefreshLivePrices
        )
    }

    static func shouldRunBackgroundMaintenance(
        now: Date,
        isNetworkReachable: Bool,
        lastBackgroundMaintenanceAt: Date?,
        interval: TimeInterval
    ) -> Bool {
        guard isNetworkReachable else { return false }
        guard let lastBackgroundMaintenanceAt else { return true }
        return now.timeIntervalSince(lastBackgroundMaintenanceAt) >= interval
    }

    static func chainPlans(
        for chainNames: Set<String>,
        forceChainRefresh: Bool,
        includeHistoryRefreshes: Bool,
        historyRefreshInterval: TimeInterval,
        pendingTransactionMaintenanceChains: Set<String>,
        degradedChains: Set<String>,
        lastGoodChainSyncByName: [String: Date],
        lastHistoryRefreshAtByChain: [String: Date],
        automaticChainRefreshStalenessInterval: TimeInterval
    ) -> [WalletRefreshChainPlan] {
        chainNames
            .sorted()
            .compactMap { chainName in
                guard shouldRefreshChainData(
                    chainName,
                    force: forceChainRefresh,
                    pendingTransactionMaintenanceChains: pendingTransactionMaintenanceChains,
                    degradedChains: degradedChains,
                    lastGoodChainSyncByName: lastGoodChainSyncByName,
                    automaticChainRefreshStalenessInterval: automaticChainRefreshStalenessInterval
                ) else {
                    return nil
                }

                let refreshHistory = includeHistoryRefreshes && shouldRefreshOnChainHistory(
                    for: chainName,
                    interval: historyRefreshInterval,
                    lastHistoryRefreshAtByChain: lastHistoryRefreshAtByChain
                )
                return WalletRefreshChainPlan(chainName: chainName, refreshHistory: refreshHistory)
            }
    }

    static func historyPlans(
        for chainNames: Set<String>,
        interval: TimeInterval,
        lastHistoryRefreshAtByChain: [String: Date]
    ) -> [String] {
        chainNames
            .sorted()
            .filter {
                shouldRefreshOnChainHistory(
                    for: $0,
                    interval: interval,
                    lastHistoryRefreshAtByChain: lastHistoryRefreshAtByChain
                )
            }
    }

    private static func shouldRefreshChainData(
        _ chainName: String,
        force: Bool,
        pendingTransactionMaintenanceChains: Set<String>,
        degradedChains: Set<String>,
        lastGoodChainSyncByName: [String: Date],
        automaticChainRefreshStalenessInterval: TimeInterval
    ) -> Bool {
        if force {
            return true
        }
        if pendingTransactionMaintenanceChains.contains(chainName) {
            return true
        }
        if degradedChains.contains(chainName) {
            return true
        }
        guard let lastGoodSyncAt = lastGoodChainSyncByName[chainName] else {
            return true
        }
        return Date().timeIntervalSince(lastGoodSyncAt) >= automaticChainRefreshStalenessInterval
    }

    private static func shouldRefreshOnChainHistory(
        for chainName: String,
        interval: TimeInterval,
        lastHistoryRefreshAtByChain: [String: Date]
    ) -> Bool {
        guard let lastRefreshAt = lastHistoryRefreshAtByChain[chainName] else {
            return true
        }
        return Date().timeIntervalSince(lastRefreshAt) >= interval
    }
}
