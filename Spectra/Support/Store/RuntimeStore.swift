import Foundation
import SwiftUI

extension WalletStore {
    var selectedMainTab: MainAppTab {
        get { runtimeState.selectedMainTab }
        set { runtimeState.selectedMainTab = newValue }
    }

    var selectedMainTabBinding: Binding<MainAppTab> {
        Binding(get: { self.runtimeState.selectedMainTab }, set: { self.runtimeState.selectedMainTab = $0 })
    }

    var isAppLocked: Bool {
        get { runtimeState.isAppLocked }
        set { runtimeState.isAppLocked = newValue }
    }

    var appLockError: String? {
        get { runtimeState.appLockError }
        set { runtimeState.appLockError = newValue }
    }

    var isPreparingEthereumReplacementContext: Bool {
        get { runtimeState.isPreparingEthereumReplacementContext }
        set { runtimeState.isPreparingEthereumReplacementContext = newValue }
    }

    var isPreparingEthereumSend: Bool {
        get { runtimeState.isPreparingEthereumSend }
        set { runtimeState.isPreparingEthereumSend = newValue }
    }

    var isPreparingDogecoinSend: Bool {
        get { runtimeState.isPreparingDogecoinSend }
        set { runtimeState.isPreparingDogecoinSend = newValue }
    }

    var isPreparingTronSend: Bool {
        get { runtimeState.isPreparingTronSend }
        set { runtimeState.isPreparingTronSend = newValue }
    }

    var isPreparingSolanaSend: Bool {
        get { runtimeState.isPreparingSolanaSend }
        set { runtimeState.isPreparingSolanaSend = newValue }
    }

    var isPreparingXRPSend: Bool {
        get { runtimeState.isPreparingXRPSend }
        set { runtimeState.isPreparingXRPSend = newValue }
    }

    var isPreparingStellarSend: Bool {
        get { runtimeState.isPreparingStellarSend }
        set { runtimeState.isPreparingStellarSend = newValue }
    }

    var isPreparingMoneroSend: Bool {
        get { runtimeState.isPreparingMoneroSend }
        set { runtimeState.isPreparingMoneroSend = newValue }
    }

    var isPreparingCardanoSend: Bool {
        get { runtimeState.isPreparingCardanoSend }
        set { runtimeState.isPreparingCardanoSend = newValue }
    }

    var isPreparingSuiSend: Bool {
        get { runtimeState.isPreparingSuiSend }
        set { runtimeState.isPreparingSuiSend = newValue }
    }

    var isPreparingAptosSend: Bool {
        get { runtimeState.isPreparingAptosSend }
        set { runtimeState.isPreparingAptosSend = newValue }
    }

    var isPreparingTONSend: Bool {
        get { runtimeState.isPreparingTONSend }
        set { runtimeState.isPreparingTONSend = newValue }
    }

    var isPreparingICPSend: Bool {
        get { runtimeState.isPreparingICPSend }
        set { runtimeState.isPreparingICPSend = newValue }
    }

    var isPreparingNearSend: Bool {
        get { runtimeState.isPreparingNearSend }
        set { runtimeState.isPreparingNearSend = newValue }
    }

    var isPreparingPolkadotSend: Bool {
        get { runtimeState.isPreparingPolkadotSend }
        set { runtimeState.isPreparingPolkadotSend = newValue }
    }

    var statusTrackingByTransactionID: [UUID: TransactionStatusTrackingState] {
        get { runtimeState.statusTrackingByTransactionID }
        set { runtimeState.statusTrackingByTransactionID = newValue }
    }

    var dogecoinStatusTrackingByTransactionID: [UUID: DogecoinStatusTrackingState] {
        get { runtimeState.statusTrackingByTransactionID }
        set { runtimeState.statusTrackingByTransactionID = newValue }
    }

    var pendingSelfSendConfirmation: PendingSelfSendConfirmation? {
        get { runtimeState.pendingSelfSendConfirmation }
        set { runtimeState.pendingSelfSendConfirmation = newValue }
    }

    var pendingDogecoinSelfSendConfirmation: PendingDogecoinSelfSendConfirmation? {
        get { runtimeState.pendingSelfSendConfirmation }
        set { runtimeState.pendingSelfSendConfirmation = newValue }
    }

    var activeEthereumSendWalletIDs: Set<UUID> {
        get { runtimeState.activeEthereumSendWalletIDs }
        set { runtimeState.activeEthereumSendWalletIDs = newValue }
    }

    var lastSendDestinationProbeKey: String? {
        get { runtimeState.lastSendDestinationProbeKey }
        set { runtimeState.lastSendDestinationProbeKey = newValue }
    }

    var lastSendDestinationProbeWarning: String? {
        get { runtimeState.lastSendDestinationProbeWarning }
        set { runtimeState.lastSendDestinationProbeWarning = newValue }
    }

    var lastSendDestinationProbeInfoMessage: String? {
        get { runtimeState.lastSendDestinationProbeInfoMessage }
        set { runtimeState.lastSendDestinationProbeInfoMessage = newValue }
    }

    var cachedResolvedENSAddresses: [String: String] {
        get { runtimeState.cachedResolvedENSAddresses }
        set { runtimeState.cachedResolvedENSAddresses = newValue }
    }

    var bypassHighRiskSendConfirmation: Bool {
        get { runtimeState.bypassHighRiskSendConfirmation }
        set { runtimeState.bypassHighRiskSendConfirmation = newValue }
    }

    var isRefreshingLivePrices: Bool {
        get { runtimeState.isRefreshingLivePrices }
        set { runtimeState.isRefreshingLivePrices = newValue }
    }

    var isRefreshingChainBalances: Bool {
        get { runtimeState.isRefreshingChainBalances }
        set { runtimeState.isRefreshingChainBalances = newValue }
    }

    var allowsBalanceNetworkRefresh: Bool {
        get { runtimeState.allowsBalanceNetworkRefresh }
        set { runtimeState.allowsBalanceNetworkRefresh = newValue }
    }

    var isRefreshingPendingTransactions: Bool {
        get { runtimeState.isRefreshingPendingTransactions }
        set { runtimeState.isRefreshingPendingTransactions = newValue }
    }

    var lastLivePriceRefreshAt: Date? {
        get { runtimeState.lastLivePriceRefreshAt }
        set { runtimeState.lastLivePriceRefreshAt = newValue }
    }

    var lastFiatRatesRefreshAt: Date? {
        get { runtimeState.lastFiatRatesRefreshAt }
        set { runtimeState.lastFiatRatesRefreshAt = newValue }
    }

    var lastFullRefreshAt: Date? {
        get { runtimeState.lastFullRefreshAt }
        set { runtimeState.lastFullRefreshAt = newValue }
    }

    var lastChainBalanceRefreshAt: Date? {
        get { runtimeState.lastChainBalanceRefreshAt }
        set { runtimeState.lastChainBalanceRefreshAt = newValue }
    }

    var lastBackgroundMaintenanceAt: Date? {
        get { runtimeState.lastBackgroundMaintenanceAt }
        set { runtimeState.lastBackgroundMaintenanceAt = newValue }
    }

    var isNetworkReachable: Bool {
        get { runtimeState.isNetworkReachable }
        set { runtimeState.isNetworkReachable = newValue }
    }

    var isConstrainedNetwork: Bool {
        get { runtimeState.isConstrainedNetwork }
        set { runtimeState.isConstrainedNetwork = newValue }
    }

    var isExpensiveNetwork: Bool {
        get { runtimeState.isExpensiveNetwork }
        set { runtimeState.isExpensiveNetwork = newValue }
    }
}
