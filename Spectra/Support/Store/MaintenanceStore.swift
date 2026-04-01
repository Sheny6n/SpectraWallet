import Foundation
import os
import UIKit
import UserNotifications

extension WalletStore {
    private func currentBatteryLevel() -> Float {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 1.0 : level
    }

    private func activePendingRefreshIntervalForProfile() -> TimeInterval {
        switch backgroundSyncProfile {
        case .conservative: return 30
        case .balanced: return Self.activePendingRefreshInterval
        case .aggressive: return 10
        }
    }

    private func activePriceRefreshIntervalForProfile() -> TimeInterval {
        TimeInterval(automaticRefreshFrequencyMinutes * 60)
    }

    private func baseBackgroundMaintenanceInterval() -> TimeInterval {
        TimeInterval(backgroundBalanceRefreshFrequencyMinutes * 60)
    }

    func backgroundMaintenanceInterval(now _: Date = Date()) -> TimeInterval {
        var interval = baseBackgroundMaintenanceInterval()
        if isConstrainedNetwork || isExpensiveNetwork {
            interval = max(interval, Self.constrainedBackgroundMaintenanceInterval)
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            interval = max(interval, Self.lowPowerBackgroundMaintenanceInterval)
        }
        if currentBatteryLevel() < 0.20 {
            interval = max(interval, Self.lowBatteryBackgroundMaintenanceInterval)
        }
        return interval
    }

    // Device/network guardrail for heavy refresh while inactive.
    private func canRunHeavyBackgroundRefresh() -> Bool {
        guard isNetworkReachable else { return false }
        if backgroundSyncProfile == .conservative {
            guard !isConstrainedNetwork, !isExpensiveNetwork else { return false }
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
            return currentBatteryLevel() >= 0.30
        }
        if backgroundSyncProfile == .balanced {
            guard !isConstrainedNetwork else { return false }
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
            return currentBatteryLevel() >= 0.20
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled, currentBatteryLevel() < 0.15 {
            return false
        }
        return currentBatteryLevel() >= 0.15
    }

    private func maybeSendLargeMovementNotification(previousTotalUSD: Double, currentTotalUSD: Double) {
        guard useLargeMovementNotifications else { return }
        guard !appIsActive else { return }
        let currentCompositionSignature = portfolioCompositionSignature()
        guard lastObservedPortfolioCompositionSignature == currentCompositionSignature else {
            resetLargeMovementAlertBaseline()
            return
        }
        guard previousTotalUSD > 0 else { return }

        let delta = currentTotalUSD - previousTotalUSD
        let absoluteDelta = abs(delta)
        let ratio = absoluteDelta / previousTotalUSD
        guard absoluteDelta >= largeMovementAlertUSDThreshold,
              ratio >= (largeMovementAlertPercentThreshold / 100.0) else {
            return
        }

        let direction = delta >= 0 ? "up" : "down"
        let content = UNMutableNotificationContent()
        content.title = "Large portfolio movement detected"
        content.body = "Your portfolio moved \(direction) by \(formattedFiatAmount(fromUSD: absoluteDelta)) (\(Int((ratio * 100).rounded()))%) since last sync."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "portfolio-movement-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func resetLargeMovementAlertBaseline() {
        lastObservedPortfolioTotalUSD = totalBalance
        lastObservedPortfolioCompositionSignature = portfolioCompositionSignature()
    }

    private func portfolioCompositionSignature() -> String {
        portfolio
            .map(\.holdingKey)
            .sorted()
            .joined(separator: "|")
    }

    // Lightweight maintenance entry for inactive/app background periods.
    func performBackgroundMaintenanceTick() async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        logger.log("Running background maintenance tick")
        await refreshPendingTransactions(includeHistoryRefreshes: false, historyRefreshInterval: 300)
        if appIsActive {
            if shouldRunScheduledPriceRefresh {
                await refreshLivePrices()
            }
            await refreshFiatExchangeRatesIfNeeded()
            recordPerformanceSample(
                "background_maintenance_tick",
                startedAt: startedAt,
                metadata: "mode=active"
            )
            return
        }

        guard canRunHeavyBackgroundRefresh() else { return }
        let previousTotal = lastObservedPortfolioTotalUSD ?? totalBalance
        await withBalanceRefreshWindow {
            await refreshChainBalances(
                includeHistoryRefreshes: false,
                historyRefreshInterval: 300,
                forceChainRefresh: false
            )
        }
        await runHistoryRefreshes(for: refreshableChainIDs, interval: 300)
        let didRefreshPrices = shouldRunScheduledPriceRefresh ? await refreshLivePrices() : false
        await refreshFiatExchangeRatesIfNeeded()
        let currentTotal = totalBalance
        if didRefreshPrices || currentTotal != previousTotal {
            maybeSendLargeMovementNotification(previousTotalUSD: previousTotal, currentTotalUSD: currentTotal)
            lastObservedPortfolioTotalUSD = currentTotal
        }
        lastFullRefreshAt = Date()
        recordPerformanceSample(
            "background_maintenance_tick",
            startedAt: startedAt,
            metadata: "mode=background chains=\(refreshableChainIDs.count)"
        )
    }

    // Pull-to-refresh orchestration for the whole app.
    func performUserInitiatedRefresh(forceChainRefresh: Bool = true) async {
        if let existingRefreshTask = userInitiatedRefreshTask {
            await existingRefreshTask.value
            return
        }

        let refreshTask = Task { @MainActor in
            let startedAt = CFAbsoluteTimeGetCurrent()
            isUserInitiatedRefreshInProgress = true
            defer {
                isUserInitiatedRefreshInProgress = false
                recordPerformanceSample(
                    "user_refresh_all",
                    startedAt: startedAt,
                    metadata: "force=\(forceChainRefresh) active=\(appIsActive)"
                )
            }

            if appIsActive {
                await refreshPendingTransactions(includeHistoryRefreshes: true, historyRefreshInterval: 120)
                await withBalanceRefreshWindow {
                    await refreshChainBalances(
                        includeHistoryRefreshes: true,
                        historyRefreshInterval: 120,
                        forceChainRefresh: forceChainRefresh
                    )
                }
                await refreshLivePrices()
                await refreshFiatExchangeRatesIfNeeded()
                lastFullRefreshAt = Date()
            } else {
                await performBackgroundMaintenanceTick()
            }
        }
        userInitiatedRefreshTask = refreshTask
        await refreshTask.value
        userInitiatedRefreshTask = nil
    }

    // Chain-scoped manual refresh for settings diagnostics/actions.
    func performUserInitiatedRefresh(forChain chainName: String) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if appIsActive {
            await refreshPendingTransactions(includeHistoryRefreshes: false)
        }

        await withBalanceRefreshWindow {
            switch chainName {
            case "Bitcoin":
                await refreshBitcoinBalances()
                await refreshBitcoinTransactions(limit: 20)
            case "Bitcoin Cash":
                await refreshBitcoinCashBalances()
                await refreshBitcoinCashTransactions(limit: 20)
            case "Bitcoin SV":
                await refreshBitcoinSVBalances()
                await refreshBitcoinSVTransactions(limit: 20)
            case "Litecoin":
                await refreshLitecoinBalances()
                await refreshLitecoinTransactions(limit: 20)
            case "Dogecoin":
                await refreshDogecoinBalances()
                await refreshDogecoinTransactions(limit: 20)
            case "Ethereum":
                await refreshEthereumBalances()
                await refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: 20, loadMore: false)
            case "Arbitrum":
                await refreshArbitrumBalances()
                await refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: 20, loadMore: false)
            case "Optimism":
                await refreshOptimismBalances()
                await refreshEVMTokenTransactions(chainName: "Optimism", maxResults: 20, loadMore: false)
            case "Ethereum Classic":
                await refreshETCBalances()
            case "BNB Chain":
                await refreshBNBBalances()
                await refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: 20, loadMore: false)
            case "Avalanche":
                await refreshAvalancheBalances()
                await refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: 20, loadMore: false)
            case "Hyperliquid":
                await refreshHyperliquidBalances()
                await refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: 20, loadMore: false)
            case "Tron":
                await refreshTronBalances()
                await refreshTronTransactions(loadMore: false)
            case "Solana":
                await refreshSolanaBalances()
                await refreshSolanaTransactions(loadMore: false)
            case "Cardano":
                await refreshCardanoBalances()
                await refreshCardanoTransactions(loadMore: false)
            case "XRP Ledger":
                await refreshXRPBalances()
                await refreshXRPTransactions(loadMore: false)
            case "Stellar":
                await refreshStellarBalances()
                await refreshStellarTransactions(loadMore: false)
            case "Monero":
                await refreshMoneroBalances()
                await refreshMoneroTransactions(loadMore: false)
            case "Sui":
                await refreshSuiBalances()
                await refreshSuiTransactions(loadMore: false)
            case "Aptos":
                await refreshAptosBalances()
                await refreshAptosTransactions(loadMore: false)
            case "TON":
                await refreshTONBalances()
                await refreshTONTransactions(loadMore: false)
            case "Internet Computer":
                await refreshICPBalances()
                await refreshICPTransactions(loadMore: false)
            case "NEAR":
                await refreshNearBalances()
                await refreshNearTransactions(loadMore: false)
            case "Polkadot":
                await refreshPolkadotBalances()
                await refreshPolkadotTransactions(loadMore: false)
            default:
                await performUserInitiatedRefresh()
                return
            }
        }

        await refreshLivePrices()
        await refreshFiatExchangeRatesIfNeeded()
        recordPerformanceSample(
            "user_refresh_chain",
            startedAt: startedAt,
            metadata: chainName
        )
    }

    func runActiveScheduledMaintenance(now: Date) async {
        let plan = WalletRefreshPlanner.activeMaintenancePlan(
            now: now,
            lastPendingTransactionRefreshAt: lastPendingTransactionRefreshAt,
            lastLivePriceRefreshAt: lastLivePriceRefreshAt,
            hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork,
            shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh,
            pendingRefreshInterval: activePendingRefreshIntervalForProfile(),
            priceRefreshInterval: activePriceRefreshIntervalForProfile()
        )
        if plan.refreshPendingTransactions {
            await refreshPendingTransactions(includeHistoryRefreshes: false)
        }

        if plan.refreshLivePrices {
            await refreshLivePrices()
        }

        await refreshFiatExchangeRatesIfNeeded()
    }
}
