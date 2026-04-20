import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct PriceAlertsView: View {
    @Bindable var store: AppState
    @State private var selectedHoldingKey: String = ""
    @State private var selectedCondition: PriceAlertCondition = .above
    @State private var targetPriceText: String = ""
    @State private var formMessage: String?
    private var alertableHoldingKeys: Set<String> { Set(store.alertableCoins.map(\.holdingKey)) }
    private var selectedCoin: Coin? {
        store.alertableCoins.first(where: { $0.holdingKey == selectedHoldingKey })
    }
    var body: some View {
        Form {
            Section {
                Text(
                    AppLocalization.string(
                        "Create alert rules for imported assets. When the current price reaches your target, Spectra sends a local notification. Alerts depend on price refreshes from your selected pricing source and fall back to built-in prices when live data is unavailable. Spectra refreshes prices when the app becomes active and on a repeating in-app watch cycle while it stays open."
                    )
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Notifications")) {
                Toggle(
                    AppLocalization.string("Enable Price Alerts"),
                    isOn: $store.usePriceAlerts
                )
                Text(
                    AppLocalization.string(
                        "You can keep rules configured even when alerts are disabled. Re-enable this later to resume notifications.")
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("New Alert")) {
                if store.alertableCoins.isEmpty {
                    Text(
                        AppLocalization.string(
                            "Import a wallet with assets first. Alerts are created from assets currently in your portfolio.")
                    ).font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker(AppLocalization.string("Asset"), selection: $selectedHoldingKey) {
                        ForEach(store.alertableCoins, id: \.holdingKey) { coin in
                            Text(AppLocalization.format("%@ on %@", coin.symbol, store.displayChainTitle(for: coin.chainName))).tag(
                                coin.holdingKey)
                        }
                    }
                    Picker(AppLocalization.string("Condition"), selection: $selectedCondition) {
                        ForEach(PriceAlertCondition.allCases) { condition in Text(condition.displayName).tag(condition) }
                    }.pickerStyle(.segmented)
                    TextField(AppLocalization.format("Target Price (%@)", store.selectedFiatCurrency.rawValue), text: $targetPriceText)
                        .keyboardType(.decimalPad)
                    if let selectedCoin {
                        Text(
                            AppLocalization.format(
                                "Current price: %@",
                                store.formattedFiatAmountOrUnavailable(fromUSD: store.currentPriceIfAvailable(for: selectedCoin)))
                        ).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
                    }
                    if let formMessage { Text(formMessage).font(.caption).foregroundStyle(isDuplicateDraftAlert ? .orange : .secondary) }
                    Button(AppLocalization.string("Add Alert")) {
                        addAlert()
                    }.disabled(!canAddAlert)
                }
            }
            Section(AppLocalization.string("Active Alerts")) {
                if store.priceAlerts.isEmpty {
                    Text(AppLocalization.string("No alerts configured yet.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.priceAlerts) { alert in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.titleText).font(.headline)
                                    Text("\(alert.condition.displayName) \(store.formattedFiatAmount(fromUSD: alert.targetPrice))").font(
                                        .caption
                                    ).foregroundStyle(.secondary).spectraNumericTextLayout()
                                }
                                Spacer()
                                Text(alert.statusText).font(.caption.bold()).frame(minWidth: 78).padding(.horizontal, 8).padding(
                                    .vertical, 4
                                ).background(statusColor(for: alert).opacity(0.18), in: Capsule()).foregroundStyle(statusColor(for: alert))
                            }
                            HStack {
                                Button(alert.isEnabled ? AppLocalization.string("Pause") : AppLocalization.string("Resume")) {
                                    store.togglePriceAlertEnabled(id: alert.id)
                                }.buttonStyle(.borderless)
                                Spacer()
                                Button(AppLocalization.string("Remove"), role: .destructive) {
                                    store.removePriceAlert(id: alert.id)
                                }.buttonStyle(.borderless)
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Price Alerts")).onAppear {
            syncSelection()
        }.onChange(of: store.walletsRevision) { _, _ in
            syncSelection()
        }
    }
    private var canAddAlert: Bool {
        guard selectedCoin != nil, let targetPrice = Double(targetPriceText.trimmingCharacters(in: .whitespacesAndNewlines)),
            targetPrice > 0
        else { return false }
        return !isDuplicateDraftAlert
    }
    private var normalizedDraftTargetPrice: Double? {
        guard let targetPriceInSelectedFiat = Double(targetPriceText.trimmingCharacters(in: .whitespacesAndNewlines)),
            targetPriceInSelectedFiat > 0
        else { return nil }
        let targetPriceUSD = store.convertSelectedFiatToUSD(targetPriceInSelectedFiat)
        return (targetPriceUSD * 100).rounded() / 100
    }
    private var isDuplicateDraftAlert: Bool {
        guard let selectedCoin, let normalizedDraftTargetPrice else { return false }
        return store.priceAlerts.contains { alert in
            alert.holdingKey == selectedCoin.holdingKey
                && alert.condition == selectedCondition
                && abs(alert.targetPrice - normalizedDraftTargetPrice) < 0.0001
        }
    }
    private func addAlert() {
        guard let selectedCoin, let targetPrice = normalizedDraftTargetPrice, targetPrice > 0 else { return }
        guard !isDuplicateDraftAlert else {
            formMessage = AppLocalization.string("An identical alert already exists for this asset.")
            return
        }
        store.addPriceAlert(for: selectedCoin, targetPrice: targetPrice, condition: selectedCondition)
        targetPriceText = ""
        selectedCondition = .above
        formMessage = AppLocalization.string("Alert added. Spectra will notify you when this target is hit.")
    }
    private func syncSelection() {
        if !alertableHoldingKeys.contains(selectedHoldingKey) { selectedHoldingKey = store.alertableCoins.first?.holdingKey ?? "" }
    }
    private func statusColor(for alert: PriceAlertRule) -> Color {
        if !alert.isEnabled { return .gray }
        return alert.hasTriggered ? .green : .orange
    }
}
