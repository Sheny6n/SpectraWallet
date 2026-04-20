import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct PricingSettingsView: View {
    @Bindable var store: AppState
    private var copy: SettingsContentCopy { .current }
    var body: some View {
        Form {
            Section {
                Text(copy.pricingIntro).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Provider")) {
                Picker(selection: $store.pricingProvider) {
                    ForEach(PricingProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }
                } label: {
                    EmptyView()
                }.pickerStyle(.inline).labelsHidden()
            }
            Section(AppLocalization.string("Display Currency")) {
                Picker(
                    AppLocalization.string("Currency"),
                    selection: $store.selectedFiatCurrency
                ) {
                    ForEach(FiatCurrency.allCases) { currency in Text(currency.displayName).tag(currency) }
                }.pickerStyle(.menu)
            }
            Section(AppLocalization.string("Fiat Rate Provider")) {
                Picker(
                    AppLocalization.string("Provider"),
                    selection: $store.fiatRateProvider
                ) {
                    ForEach(FiatRateProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }
                }.pickerStyle(.menu)
                Text(copy.fiatRateProviderNote).font(.caption).foregroundStyle(.secondary)
            }
            if store.pricingProvider == .coinGecko {
                Section(AppLocalization.string("CoinGecko")) {
                    TextField(
                        AppLocalization.string("CoinGecko Pro API Key (Optional)"),
                        text: $store.coinGeckoAPIKey
                    ).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(copy.coinGeckoNote).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(AppLocalization.string("Provider Notes")) {
                    Text(copy.publicProviderNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let quoteRefreshError = store.quoteRefreshError {
                Section {
                    Text(quoteRefreshError).font(.caption).foregroundStyle(.red)
                }
            }
            if let fiatRatesRefreshError = store.fiatRatesRefreshError {
                Section {
                    Text(fiatRatesRefreshError).font(.caption).foregroundStyle(.red)
                }
            }
        }.navigationTitle(AppLocalization.string("Pricing"))
    }
}
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
struct AddressBookView: View {
    let store: AppState
    @State private var contactName: String = ""
    @State private var selectedChainName: String = "Bitcoin"
    @State private var address: String = ""
    @State private var note: String = ""
    @State private var formMessage: String?
    @State private var editingEntry: AddressBookEntry?
    @State private var editedName: String = ""
    @State private var copiedEntryID: UUID?
    private let supportedChains = [
        "Bitcoin", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid",
        "Tron", "Solana", "Cardano", "XRP Ledger", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot", "Stellar",
    ]
    private var addressPrompt: String {
        switch selectedChainName {
        case "Bitcoin": return "bc1q..."
        case "Litecoin": return "ltc1... / L... / M..."
        case "Dogecoin": return "D..."
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Sui", "Aptos": return "0x..."
        case "Tron": return "T..."
        case "Solana": return "So111..."
        case "Cardano": return "addr1..."
        case "XRP Ledger": return "r..."
        case "Monero": return "4... / 8..."
        case "TON": return "UQ... / EQ..."
        case "Internet Computer": return "64-char account identifier"
        case "NEAR": return "alice.near / 64-char hex"
        case "Polkadot": return "1..."
        case "Stellar": return "G..."
        default: return ""
        }
    }
    private var addressValidationMessage: String {
        if store.isDuplicateAddressBookAddress(address, chainName: selectedChainName) {
            return AppLocalization.format("This %@ address is already saved.", selectedChainName)
        }
        return store.addressBookAddressValidationMessage(for: address, chainName: selectedChainName)
    }
    private var addressValidationColor: Color {
        if store.isDuplicateAddressBookAddress(address, chainName: selectedChainName) { return .orange }
        return store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) ? .green : .secondary
    }
    private var canRenameSelectedEntry: Bool {
        guard let editingEntry else { return false }
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedName != editingEntry.name
    }
    var body: some View {
        Form {
            Section {
                Text(
                    AppLocalization.string(
                        "Save trusted recipient addresses here so you can reuse them in Send without retyping. Spectra currently supports address book validation for Bitcoin, Litecoin, Dogecoin, Ethereum, Ethereum Classic, Arbitrum, Optimism, BNB Chain, Avalanche, Hyperliquid, Tron, Solana, Cardano, XRP Ledger, Monero, Sui, Aptos, TON, Internet Computer, NEAR, Polkadot, and Stellar."
                    )
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("New Contact")) {
                TextField(AppLocalization.string("Name"), text: $contactName).textInputAutocapitalization(.words).autocorrectionDisabled()
                Picker(AppLocalization.string("Chain"), selection: $selectedChainName) {
                    ForEach(supportedChains, id: \.self) { chainName in Text(chainName).tag(chainName) }
                }
                TextField(addressPrompt, text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(addressValidationMessage).font(.caption).foregroundStyle(addressValidationColor)
                TextField(AppLocalization.string("Note (Optional)"), text: $note).textInputAutocapitalization(.sentences)
                if let formMessage {
                    Text(formMessage).font(.caption).foregroundStyle(.secondary).foregroundColor(
                        store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) ? nil : .red)
                }
                Button(AppLocalization.string("Save Contact")) {
                    saveContact()
                }.disabled(!store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName))
            }
            Section(AppLocalization.string("Saved Addresses")) {
                if store.addressBook.isEmpty {
                    Text(AppLocalization.string("No saved recipients yet.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.addressBook) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline)
                                    Text(entry.subtitleText).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.address).font(.caption.monospaced()).textSelection(.enabled)
                                }
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = entry.address
                                    copiedEntryID = entry.id
                                } label: {
                                    Label(
                                        copiedEntryID == entry.id ? AppLocalization.string("Copied") : AppLocalization.string("Copy"),
                                        systemImage: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc"
                                    ).font(.caption.weight(.semibold))
                                }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 4).swipeActions {
                            Button(AppLocalization.string("Edit")) {
                                editingEntry = entry
                                editedName = entry.name
                            }
                            Button(AppLocalization.string("Delete"), role: .destructive) {
                                store.removeAddressBookEntry(id: entry.id)
                            }
                        }
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Address Book")).sheet(item: $editingEntry) { entry in
            NavigationView {
                Form {
                    Section {
                        Text(
                            AppLocalization.string(
                                "You can update the label for this saved address. The chain, address, and note stay fixed.")
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    Section(AppLocalization.string("Saved Address")) {
                        Text(entry.chainName)
                        Text(entry.address).font(.caption.monospaced()).textSelection(.enabled)
                        if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary) }
                    }
                    Section(AppLocalization.string("Label")) {
                        TextField(AppLocalization.string("Name"), text: $editedName).textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }.navigationTitle(AppLocalization.string("Edit Label")).toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(AppLocalization.string("Cancel")) {
                            editingEntry = nil
                            editedName = ""
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(AppLocalization.string("Save")) {
                            store.renameAddressBookEntry(id: entry.id, to: editedName)
                            editingEntry = nil
                            editedName = ""
                        }.disabled(!canRenameSelectedEntry)
                    }
                }
            }
        }
    }
    private func saveContact() {
        guard store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) else {
            formMessage = AppLocalization.format("Enter a unique valid %@ address and a contact name.", selectedChainName)
            return
        }
        store.addAddressBookEntry(name: contactName, address: address, chainName: selectedChainName, note: note)
        contactName = ""
        address = ""
        note = ""
        formMessage = AppLocalization.string("Address saved.")
    }
}
struct AboutView: View {
    @State private var isAnimatingHero = false
    private var copy: SettingsContentCopy { .current }
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 22) {
                    aboutHero
                    aboutCard(title: copy.aboutEthosTitle, lines: copy.aboutEthosLines)
                    aboutNarrativeCard
                }.padding(20)
            }
        }.navigationTitle(AppLocalization.string("About Spectra")).navigationBarTitleDisplayMode(.inline).onAppear {
            isAnimatingHero = true
        }
    }
    private var aboutHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(
                    AngularGradient(
                        colors: [
                            .red.opacity(0.85), .orange.opacity(0.92), .yellow.opacity(0.9), .green.opacity(0.82), .blue.opacity(0.82),
                            .indigo.opacity(0.82), .pink.opacity(0.88), .red.opacity(0.85),
                        ], center: .center
                    )
                ).frame(width: 220, height: 220).blur(radius: 26).rotationEffect(.degrees(isAnimatingHero ? 360 : 0)).animation(
                    .linear(duration: 18).repeatForever(autoreverses: false), value: isAnimatingHero)
                Circle().fill(Color.white.opacity(0.08)).frame(width: 178, height: 178).background(.ultraThinMaterial, in: Circle())
                SpectraLogo(size: 96)
            }
            VStack(spacing: 8) {
                Text(copy.aboutTitle).font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Color.primary)
                Text(copy.aboutSubtitle).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color.primary.opacity(0.78))
            }.frame(maxWidth: .infinity)
        }.padding(24).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 30))
    }
    private var aboutNarrativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.aboutNarrativeTitle).font(.headline).foregroundStyle(Color.primary)
            ForEach(copy.aboutNarrativeParagraphs, id: \.self) { paragraph in
                Text(paragraph).font(.subheadline).foregroundStyle(Color.primary.opacity(0.8))
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(
            .regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
    }
    private func aboutCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(Color.primary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.primary.opacity(0.5)).frame(width: 6, height: 6).padding(.top, 7)
                    Text(line).font(.subheadline).foregroundStyle(Color.primary.opacity(0.82))
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(
            .regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
    }
}
struct BackgroundSyncSettingsView: View {
    @Bindable var store: AppState
    var body: some View {
        Form {
            Section(AppLocalization.string("Refresh Frequency")) {
                Text(AppLocalization.string("Choose how often Spectra refreshes balances automatically while the app is active.")).font(
                    .caption
                ).foregroundStyle(.secondary)
                Stepper(
                    value: $store.automaticRefreshFrequencyMinutes,
                    in: 5...60, step: 5
                ) {
                    LabeledContent(AppLocalization.string("Active app refresh"), value: "\(store.automaticRefreshFrequencyMinutes) min")
                }
            }
            Section(AppLocalization.string("Current Timing")) {
                LabeledContent(
                    AppLocalization.string("Active app balance refresh"), value: "\(store.automaticRefreshFrequencyMinutes) min")
                LabeledContent(
                    AppLocalization.string("Background balance refresh"), value: "\(store.backgroundBalanceRefreshFrequencyMinutes) min")
            }
            Section(AppLocalization.string("Hint")) {
                Label(
                    AppLocalization.string("Lower refresh times can increase battery usage and network traffic."),
                    systemImage: "bolt.batteryblock.fill"
                ).foregroundStyle(.orange)
                Text(AppLocalization.string("Choose a longer interval if you want lower background activity and less battery impact."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isTooFrequent(store.automaticRefreshFrequencyMinutes) {
                Section(AppLocalization.string("Warning")) {
                    Label(
                        AppLocalization.string("This refresh speed can increase battery usage and network traffic."),
                        systemImage: "exclamationmark.triangle.fill"
                    ).foregroundStyle(.orange)
                    Text(AppLocalization.string("Use this mode only if you need near-real-time updates.")).font(.caption).foregroundStyle(
                        .secondary)
                }
            }
        }.navigationTitle(AppLocalization.string("Background Sync"))
    }
    private func isTooFrequent(_ minutes: Int) -> Bool { minutes <= 10 }
}
struct ChainFeePrioritySettingsView: View {
    let store: AppState
    private struct ChainFeePrioritySetting: Identifiable {
        let chainName: String
        let title: String
        let detail: String
        var id: String { chainName }
    }
    var body: some View {
        Form {
            ForEach(chainFeePrioritySettings) { item in
                Section(AppLocalization.string(item.chainName)) {
                    Picker(
                        AppLocalization.string(item.title),
                        selection: Binding(
                            get: { store.feePriorityOption(for: item.chainName) },
                            set: { store.setFeePriorityOption($0, for: item.chainName) }
                        )
                    ) {
                        ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
                    }.pickerStyle(.segmented)
                    Text(AppLocalization.string(item.detail)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(AppLocalization.string("Fee Priorities"))
    }
    private var chainFeePrioritySettings: [ChainFeePrioritySetting] {
        func std(_ chain: String) -> ChainFeePrioritySetting {
            ChainFeePrioritySetting(
                chainName: chain, title: "Default Fee Priority", detail: "Stored as the default fee priority for \(chain) sends.")
        }
        return [
            ChainFeePrioritySetting(
                chainName: "Bitcoin", title: "Default Fee Priority",
                detail: "Used as the default for Bitcoin sends. You can still override before broadcasting."),
            std("Bitcoin Cash"),
            std("Bitcoin SV"),
            ChainFeePrioritySetting(
                chainName: "Litecoin", title: "Default Fee Priority",
                detail: "Used as the default for Litecoin sends. You can still override before broadcasting."),
            ChainFeePrioritySetting(
                chainName: "Dogecoin", title: "Dogecoin Default Fee",
                detail: "This is the default in Send. You can still override fee priority per transaction."),
            std("Ethereum"), std("Ethereum Classic"), std("Arbitrum"), std("Optimism"),
            std("BNB Chain"), std("Avalanche"), std("Hyperliquid"), std("Tron"), std("Solana"),
            ChainFeePrioritySetting(
                chainName: "XRP Ledger", title: "Default Fee Priority", detail: "Stored as the default fee priority for XRP sends."),
            std("Cardano"), std("Monero"), std("Sui"), std("Aptos"), std("TON"),
            std("NEAR"), std("Polkadot"), std("Stellar"), std("Internet Computer"),
        ]
    }
}
struct SettingsView: View {
    @Bindable var store: AppState
    @State private var isShowingResetWalletWarning: Bool = false
    private enum Route: Hashable {
        case addressBook
        case trackedTokens
        case feePriorities
        case iconStyles
        case decimalDisplay
        case refreshFrequency
        case priceAlerts
        case largeMovementAlerts
        case pricing
        case endpoints
        case diagnostics
        case operationalLogs
        case reportProblem
        case buyCryptoHelp
        case about
        case chainWiki
        case advanced
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("Wallet & Transfers")) {
                    NavigationLink(value: Route.addressBook) {
                        Label(AppLocalization.string("Address Book"), systemImage: "book.closed")
                    }
                    NavigationLink(value: Route.trackedTokens) {
                        Label(AppLocalization.string("Tracked Tokens"), systemImage: "bitcoinsign.bank.building")
                    }
                    NavigationLink(value: Route.feePriorities) {
                        Label(AppLocalization.string("Fee Priorities"), systemImage: "dial.medium")
                    }
                }
                Section(AppLocalization.string("Display")) {
                    NavigationLink(value: Route.iconStyles) {
                        Label(AppLocalization.string("Icon Styles"), systemImage: "photo.on.rectangle")
                    }
                    Toggle(isOn: $store.hideBalances) {
                        Label(AppLocalization.string("Hide balances"), systemImage: "eye.slash")
                    }
                    NavigationLink(value: Route.decimalDisplay) {
                        Label(AppLocalization.string("Decimal Display"), systemImage: "number")
                    }
                }
                Section(AppLocalization.string("Sync & Automation")) {
                    NavigationLink(value: Route.refreshFrequency) {
                        Label(AppLocalization.string("Refresh Frequency"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section(AppLocalization.string("Notifications")) {
                    NavigationLink(value: Route.priceAlerts) {
                        Label(AppLocalization.string("Price Alerts"), systemImage: "bell.badge")
                    }
                    Toggle(
                        isOn: Binding(
                            get: { store.useTransactionStatusNotifications }, set: { store.useTransactionStatusNotifications = $0 })
                    ) {
                        Label(AppLocalization.string("Transaction Status Updates"), systemImage: "clock.badge.checkmark")
                    }
                    NavigationLink(value: Route.largeMovementAlerts) {
                        Label(AppLocalization.string("Large Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                Section(AppLocalization.string("Security & Privacy")) {
                    Toggle(isOn: $store.useFaceID) {
                        Label(AppLocalization.string("Use Face ID"), systemImage: "faceid")
                    }
                    Toggle(isOn: $store.useAutoLock) {
                        Label(AppLocalization.string("Auto Lock"), systemImage: "lock")
                    }.disabled(!store.useFaceID)
                }
                Section(AppLocalization.string("Data & Connectivity")) {
                    NavigationLink(value: Route.pricing) {
                        Label(AppLocalization.string("Pricing"), systemImage: "dollarsign.circle")
                    }
                    NavigationLink(value: Route.endpoints) {
                        Label(AppLocalization.string("Endpoints"), systemImage: "network")
                    }
                }
                Section(AppLocalization.string("Diagnostics & Support")) {
                    NavigationLink(value: Route.diagnostics) {
                        Label(AppLocalization.string("Diagnostics"), systemImage: "waveform.path.ecg.rectangle")
                    }
                    NavigationLink(value: Route.operationalLogs) {
                        Label(AppLocalization.string("Operational Logs"), systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(value: Route.reportProblem) {
                        Label(AppLocalization.string("Report a Problem"), systemImage: "exclamationmark.bubble")
                    }
                }
                Section(AppLocalization.string("Help")) {
                    NavigationLink(value: Route.buyCryptoHelp) {
                        Label(AppLocalization.string("Where can I buy crypto?"), systemImage: "creditcard")
                    }
                }
                Section(AppLocalization.string("About")) {
                    NavigationLink(value: Route.about) {
                        Label(AppLocalization.string("About Spectra"), systemImage: "info.circle")
                    }
                    NavigationLink(value: Route.chainWiki) {
                        Label(AppLocalization.string("Chain Wiki"), systemImage: "books.vertical")
                    }
                }
                Section(AppLocalization.string("Advanced")) {
                    NavigationLink(value: Route.advanced) {
                        Label(AppLocalization.string("Advanced"), systemImage: "slider.horizontal.3")
                    }
                }
                Section(AppLocalization.string("Reset")) {
                    Button {
                        isShowingResetWalletWarning = true
                    } label: {
                        Label(AppLocalization.string("Reset Wallet"), systemImage: "trash")
                    }.foregroundColor(.red)
                }
            }.navigationTitle(AppLocalization.string("Settings")).navigationDestination(for: Route.self) { route in
                switch route {
                case .addressBook: AddressBookView(store: store)
                case .trackedTokens: TokenRegistrySettingsView(store: store)
                case .feePriorities: ChainFeePrioritySettingsView(store: store)
                case .iconStyles: TokenIconSettingsView()
                case .decimalDisplay: DecimalDisplaySettingsView(store: store)
                case .refreshFrequency: BackgroundSyncSettingsView(store: store)
                case .priceAlerts: PriceAlertsView(store: store)
                case .largeMovementAlerts: LargeMovementAlertsSettingsView(store: store)
                case .pricing: PricingSettingsView(store: store)
                case .endpoints: EndpointCatalogSettingsView(store: store)
                case .diagnostics: DiagnosticsHubView(store: store)
                case .operationalLogs: LogsView(store: store)
                case .reportProblem: ReportProblemView()
                case .buyCryptoHelp: BuyCryptoHelpView()
                case .about: AboutView()
                case .chainWiki: ChainWikiLibraryView()
                case .advanced: AdvancedSettingsView(store: store)
                }
            }.sheet(isPresented: $isShowingResetWalletWarning) {
                ResetWalletWarningView(store: store)
            }
        }
    }
}
struct ReportProblemView: View {
    private var copy: SettingsContentCopy { .current }
    private var reportProblemURL: URL { URL(string: copy.reportProblemURL) ?? URL(string: "https://example.com/spectra/report-problem")! }
    var body: some View {
        Form {
            Section {
                Text(copy.reportProblemDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Support Link")) {
                Link(destination: reportProblemURL) {
                    Label(copy.reportProblemActionTitle, systemImage: "arrow.up.right.square")
                }
                Text(reportProblemURL.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.navigationTitle(AppLocalization.string("Report a Problem"))
    }
}
struct BuyCryptoHelpView: View {
    private var copy: SettingsContentCopy { .current }
    private struct BuyCryptoProvider: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let url: URL
        let urlLabel: String
    }
    private let providers: [BuyCryptoProvider] = BuyCryptoProviderCatalog.loadEntries().compactMap { provider in
        guard let url = URL(string: provider.url) else { return nil }
        return BuyCryptoProvider(name: provider.name, description: provider.description, url: url, urlLabel: provider.urlLabel)
    }
    var body: some View {
        Form {
            Section {
                Text(copy.buyProvidersIntro).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Options")) {
                ForEach(providers) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        Link(destination: provider.url) {
                            Label(provider.name, systemImage: "arrow.up.right.square").font(.headline)
                        }
                        Text(provider.description).font(.subheadline).foregroundStyle(.primary)
                        Text(provider.urlLabel).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
            }
            Section(AppLocalization.string("Reminder")) { Text(copy.buyWarning).font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle(AppLocalization.string("Where can I buy crypto?"))
    }
}
struct AdvancedSettingsView: View {
    @Bindable var store: AppState
    @State private var isRunningMaintenance = false
    @State private var maintenanceNotice: String?
    @State private var isShowingDiagnosticsImporter = false
    @State private var isShowingDiagnosticsExportsBrowser = false
    @State private var lastExportedDiagnosticsURL: URL?
    private let singleChainRefreshNames = [
        "Bitcoin", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid",
        "Tron", "Solana", "Cardano", "XRP Ledger", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot", "Stellar",
    ]
    var body: some View {
        Form {
            Section(AppLocalization.string("Security")) {
                Toggle(
                    AppLocalization.string("Biometric Confirmation For Send Actions"),
                    isOn: Binding(
                        get: { store.requireBiometricForSendActions }, set: { store.requireBiometricForSendActions = $0 }
                    )
                )
                Toggle(
                    AppLocalization.string("Strict RPC Only (Disable Ledger Fallback)"),
                    isOn: $store.useStrictRPCOnly
                )
                Text(AppLocalization.string("When enabled, balances only come from live RPC responses.")).font(.caption).foregroundStyle(
                    .secondary)
                Button(AppLocalization.string("Lock App Now")) {
                    store.isAppLocked = true
                    maintenanceNotice = AppLocalization.string("App locked.")
                }
            }
            Section(AppLocalization.string("Quick Maintenance")) {
                Button(
                    isRunningMaintenance
                        ? AppLocalization.string("Refreshing...") : AppLocalization.string("Refresh Now (Balances + History)")
                ) {
                    Task {
                        isRunningMaintenance = true
                        await store.performUserInitiatedRefresh()
                        isRunningMaintenance = false
                        maintenanceNotice = AppLocalization.string("Manual refresh completed.")
                    }
                }.disabled(isRunningMaintenance)
                Button(
                    isRunningMaintenance
                        ? AppLocalization.string("Running Diagnostics...") : AppLocalization.string("Run All Endpoint Checks")
                ) {
                    Task {
                        isRunningMaintenance = true
                        await store.runBitcoinEndpointReachabilityDiagnostics()
                        await store.runBitcoinCashEndpointReachabilityDiagnostics()
                        await store.runLitecoinEndpointReachabilityDiagnostics()
                        await store.runEthereumEndpointReachabilityDiagnostics()
                        await store.runETCEndpointReachabilityDiagnostics()
                        await store.runArbitrumEndpointReachabilityDiagnostics()
                        await store.runOptimismEndpointReachabilityDiagnostics()
                        await store.runBNBEndpointReachabilityDiagnostics()
                        await store.runAvalancheEndpointReachabilityDiagnostics()
                        await store.runHyperliquidEndpointReachabilityDiagnostics()
                        await store.runTronEndpointReachabilityDiagnostics()
                        await store.runSolanaEndpointReachabilityDiagnostics()
                        await store.runCardanoEndpointReachabilityDiagnostics()
                        await store.runXRPEndpointReachabilityDiagnostics()
                        await store.runMoneroEndpointReachabilityDiagnostics()
                        await store.runSuiEndpointReachabilityDiagnostics()
                        await store.runAptosEndpointReachabilityDiagnostics()
                        await store.runTONEndpointReachabilityDiagnostics()
                        await store.runICPEndpointReachabilityDiagnostics()
                        await store.runNearEndpointReachabilityDiagnostics()
                        await store.runPolkadotEndpointReachabilityDiagnostics()
                        await store.runStellarEndpointReachabilityDiagnostics()
                        isRunningMaintenance = false
                        maintenanceNotice = AppLocalization.string("Endpoint checks completed.")
                    }
                }.disabled(isRunningMaintenance)
                ForEach(singleChainRefreshNames, id: \.self) { chainName in
                    Button(refreshButtonTitle(for: chainName)) {
                        refreshSingleChain(chainName)
                    }.disabled(isRunningMaintenance)
                }
                if let maintenanceNotice { Text(maintenanceNotice).font(.caption).foregroundStyle(.secondary) }
            }
            Section(AppLocalization.string("Diagnostics Bundle")) {
                Button(AppLocalization.string("Export Diagnostics Bundle")) {
                    do {
                        let url = try store.exportDiagnosticsBundle()
                        lastExportedDiagnosticsURL = url
                        maintenanceNotice = AppLocalization.format("Diagnostics exported to %@", url.lastPathComponent)
                    } catch {
                        maintenanceNotice = AppLocalization.format("Export failed: %@", error.localizedDescription)
                    }
                }
                Button(AppLocalization.string("Past Exports")) {
                    isShowingDiagnosticsExportsBrowser = true
                }
                if let lastExportedDiagnosticsURL {
                    ShareLink(item: lastExportedDiagnosticsURL) {
                        Label(AppLocalization.string("Share Last Export"), systemImage: "square.and.arrow.up")
                    }
                }
                Button(AppLocalization.string("Import Diagnostics Bundle")) {
                    isShowingDiagnosticsImporter = true
                }
            }
            Section(AppLocalization.string("Status")) {
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                if let pendingRefresh = store.pendingTransactionRefreshStatusText {
                    Text(pendingRefresh).font(.caption).foregroundStyle(.secondary)
                }
                Text(AppLocalization.format("Wallets: %lld", store.wallets.count)).font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.format("Tracked token checks enabled: %lld", store.tokenPreferences.filter { $0.isEnabled }.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(AppLocalization.string("Advanced")).sheet(isPresented: $isShowingDiagnosticsExportsBrowser) {
            DiagnosticsExportsBrowserView(store: store)
        }.fileImporter(
            isPresented: $isShowingDiagnosticsImporter, allowedContentTypes: [UTType.json], allowsMultipleSelection: false
        ) { result in
            do {
                guard let fileURL = try result.get().first else { return }
                let didAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { fileURL.stopAccessingSecurityScopedResource() }
                }
                let payload = try store.importDiagnosticsBundle(from: fileURL)
                maintenanceNotice = AppLocalization.format(
                    "Imported diagnostics bundle (%@).", payload.generatedAt.formatted(date: .abbreviated, time: .shortened))
            } catch {
                maintenanceNotice = AppLocalization.format("Import failed: %@", error.localizedDescription)
            }
        }
    }
    private func refreshSingleChain(_ chainName: String) {
        Task {
            isRunningMaintenance = true
            await store.performUserInitiatedRefresh(forChain: chainName)
            isRunningMaintenance = false
            maintenanceNotice = AppLocalization.format("%@ refresh completed.", chainName)
        }
    }
    private func refreshButtonTitle(for chainName: String, label: String? = nil) -> String {
        let title = label ?? chainName
        return isRunningMaintenance ? AppLocalization.format("Refreshing %@...", title) : AppLocalization.format("Refresh %@", title)
    }
}
struct DiagnosticsExportsBrowserView: View {
    let store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var exportURLs: [URL] = []
    var body: some View {
        NavigationStack {
            List {
                if exportURLs.isEmpty {
                    Text(AppLocalization.string("No diagnostics exports yet.")).foregroundStyle(.secondary)
                } else {
                    ForEach(exportURLs, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(url.lastPathComponent).font(.subheadline.weight(.semibold))
                            Text(exportTimestamp(for: url)).font(.caption).foregroundStyle(.secondary)
                            ShareLink(item: url) {
                                Label(AppLocalization.string("Share"), systemImage: "square.and.arrow.up")
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }.onDelete(perform: deleteExports)
                }
            }.navigationTitle(AppLocalization.string("Past Exports")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
            }.onAppear(perform: reloadExports)
        }
    }
    private func reloadExports() { exportURLs = store.diagnosticsBundleExportURLs() }
    private func deleteExports(at offsets: IndexSet) {
        for index in offsets {
            let url = exportURLs[index]
            try? store.deleteDiagnosticsBundleExport(at: url)
        }
        reloadExports()
    }
    private func exportTimestamp(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        return date == .distantPast ? AppLocalization.string("Unknown date") : date.formatted(date: .abbreviated, time: .shortened)
    }
}
struct LargeMovementAlertsSettingsView: View {
    @Bindable var store: AppState
    var body: some View {
        Form {
            Section(AppLocalization.string("Notifications")) {
                Toggle(isOn: $store.useLargeMovementNotifications) {
                    Label(AppLocalization.string("Large Portfolio Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                }
                Text(
                    store.useLargeMovementNotifications
                        ? AppLocalization.string(
                            "Spectra can notify you when your total portfolio moves beyond your configured thresholds.")
                        : AppLocalization.string("Large movement notifications are currently off.")
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Alert Controls")) {
                Stepper(
                    String(
                        format: AppLocalization.string("Large movement threshold: %@"),
                        (store.largeMovementAlertPercentThreshold / 100).formatted(.percent.precision(.fractionLength(0)))
                    ),
                    value: Binding(
                        get: { store.largeMovementAlertPercentThreshold }, set: { store.largeMovementAlertPercentThreshold = $0 }
                    ), in: 1...90, step: 1
                ).disabled(!store.useLargeMovementNotifications)
                Stepper(
                    AppLocalization.format("Large movement minimum: %lld USD", Int(store.largeMovementAlertUSDThreshold)),
                    value: Binding(
                        get: { store.largeMovementAlertUSDThreshold }, set: { store.largeMovementAlertUSDThreshold = $0 }
                    ), in: 1...100_000, step: 5
                ).disabled(!store.useLargeMovementNotifications)
            }
            Section {
                Text(
                    AppLocalization.string(
                        "These controls tune when portfolio movement notifications are sent during portfolio balance refreshes.")
                ).font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(AppLocalization.string("Large Movement Alerts"))
    }
}
private enum TokenRegistryGrouping {
    nonisolated static func key(for entry: TokenPreferenceEntry) -> String {
        let geckoID = entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !geckoID.isEmpty { return "gecko:\(geckoID)" }
        return "symbol:\(entry.symbol.lowercased())|\(entry.name.lowercased())"
    }
}
struct TokenRegistrySettingsView: View {
    let store: AppState
    private enum TokenRegistryChainFilter: CaseIterable, Identifiable {
        case all
        case ethereum
        case arbitrum
        case optimism
        case bnb
        case avalanche
        case hyperliquid
        case solana
        case sui
        case aptos
        case ton
        case near
        case tron
        var id: Self { self }
        var title: String { chain?.filterDisplayName ?? AppLocalization.string("All") }
        var chain: TokenTrackingChain? {
            switch self {
            case .all: return nil
            case .ethereum: return .ethereum
            case .arbitrum: return .arbitrum
            case .optimism: return .optimism
            case .bnb: return .bnb
            case .avalanche: return .avalanche
            case .hyperliquid: return .hyperliquid
            case .solana: return .solana
            case .sui: return .sui
            case .aptos: return .aptos
            case .ton: return .ton
            case .near: return .near
            case .tron: return .tron
            }
        }
    }
    private enum TokenRegistrySourceFilter: CaseIterable, Identifiable {
        case all
        case builtIn
        case custom
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return AppLocalization.string("All")
            case .builtIn: return AppLocalization.string("Built-In")
            case .custom: return AppLocalization.string("Custom")
            }
        }
    }
    @State private var searchText: String = ""
    @State private var chainFilter: TokenRegistryChainFilter = .all
    @State private var sourceFilter: TokenRegistrySourceFilter = .all
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(AppLocalization.string("Search name, symbol, chain, or address"), text: $searchText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }.padding(.horizontal, 12).padding(.vertical, 10).background(
                        .thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(spacing: 10) {
                        Picker(AppLocalization.string("Network"), selection: $chainFilter) {
                            ForEach(TokenRegistryChainFilter.allCases) { filter in Text(filter.title).tag(filter) }
                        }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        Picker(AppLocalization.string("Source"), selection: $sourceFilter) {
                            ForEach(TokenRegistrySourceFilter.allCases) { filter in Text(filter.title).tag(filter) }
                        }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if chainFilter != .all || sourceFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack {
                            Spacer(minLength: 0)
                            Button(AppLocalization.string("Clear")) {
                                chainFilter = .all
                                sourceFilter = .all
                                searchText = ""
                            }.font(.caption.weight(.semibold)).foregroundStyle(.mint).buttonStyle(.plain)
                        }
                    }
                }
            }
            Section(AppLocalization.string("Tracked Tokens")) {
                if filteredGroups.isEmpty {
                    Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AppLocalization.string("No tracked tokens match the selected filters.")
                            : AppLocalization.string("No matching tokens.")
                    ).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredGroups) { group in
                        HStack(spacing: 12) {
                            NavigationLink {
                                TokenRegistryDetailView(store: store, groupKey: group.key)
                            } label: {
                                TokenRegistryGroupRowView(group: group)
                            }.buttonStyle(.plain)
                            Toggle(
                                isOn: Binding(
                                    get: { group.isEnabled },
                                    set: { store.setTokenPreferencesEnabled(ids: group.allEntryIDs, isEnabled: $0) }
                                )
                            ) { EmptyView() }.labelsHidden().scaleEffect(0.9)
                        }
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Tracked Tokens")).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddCustomTokenView(store: store)
                } label: {
                    Text(AppLocalization.string("New Token"))
                }
            }
        }
    }
    private func entries(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
        store.resolvedTokenPreferences.filter { $0.chain == chain }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
                if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
                return lhs.symbol < rhs.symbol
            }
    }
    private var filteredGroups: [TokenRegistryGroup] {
        let allEntries = store.resolvedTokenPreferences
        let grouped = Dictionary(grouping: allEntries, by: TokenRegistryGrouping.key(for:))
        let groups = grouped.values.compactMap { entries -> TokenRegistryGroup? in
            let sortedEntries = entries.sorted { lhs, rhs in
                if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
                return lhs.contractAddress < rhs.contractAddress
            }
            guard let representative = sortedEntries.first else { return nil }
            return TokenRegistryGroup(
                key: TokenRegistryGrouping.key(for: representative), name: representative.name, symbol: representative.symbol,
                entries: sortedEntries
            )
        }
        let filtered = groups.filter { group in
            if let selectedChain = chainFilter.chain, !group.entries.contains(where: { $0.chain == selectedChain }) {
                return false
            }
            switch sourceFilter {
            case .all: break
            case .builtIn: guard group.entries.contains(where: \.isBuiltIn) else { return false }
            case .custom: guard group.entries.contains(where: { !$0.isBuiltIn }) else { return false }
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            let haystack =
                ([group.symbol, group.name]
                + group.entries.flatMap { entry in [entry.chain.rawValue, entry.tokenStandard, entry.contractAddress, entry.coinGeckoId] })
                .joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.entries.contains(where: \.isBuiltIn) != rhs.entries.contains(where: \.isBuiltIn) {
                return lhs.entries.contains(where: \.isBuiltIn)
            }
            return lhs.symbol < rhs.symbol
        }
    }
}
struct TokenRegistryDetailView: View {
    let store: AppState
    let groupKey: String
    private var groupEntries: [TokenPreferenceEntry] {
        store.resolvedTokenPreferences.filter { TokenRegistryGrouping.key(for: $0) == groupKey }
            .sorted { lhs, rhs in
                if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
                return lhs.contractAddress < rhs.contractAddress
            }
    }
    private var representativeEntry: TokenPreferenceEntry? { groupEntries.first }
    var body: some View {
        Group {
            if let representativeEntry {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            CoinBadge(
                                assetIdentifier: representativeEntry.settingsAssetIdentifier,
                                fallbackText: representativeEntry.settingsFallbackMark,
                                color: representativeEntry.chain.settingsIconTint, size: 42
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(representativeEntry.name).font(.headline)
                                Text(representativeEntry.symbol).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                    Section(AppLocalization.string("Chain Support")) {
                        ForEach(groupEntries) { entry in
                            TokenRegistryEntryCardView(
                                entry: entry, setEnabled: { store.setTokenPreferenceEnabled(id: entry.id, isEnabled: $0) },
                                updateDecimals: { store.updateCustomTokenPreferenceDecimals(id: entry.id, decimals: $0) },
                                removeToken: { store.removeCustomTokenPreference(id: entry.id) }
                            )
                        }
                    }
                }.navigationTitle(representativeEntry.symbol)
            } else {
                ContentUnavailableView(AppLocalization.string("Token Not Found"), systemImage: "questionmark.circle")
            }
        }
    }
}
struct AddCustomTokenView: View {
    let store: AppState
    @State private var selectedChain: TokenTrackingChain = .ethereum
    @State private var symbolInput: String = ""
    @State private var nameInput: String = ""
    @State private var contractInput: String = ""
    @State private var coinGeckoIdInput: String = ""
    @State private var decimalsInput: Int = 6
    @State private var formMessage: String?
    var body: some View {
        Form {
            Section {
                Text(
                    AppLocalization.string(
                        "Add a custom token contract, mint address, coin type, package address, account ID, or jetton master address for Ethereum, Arbitrum, Optimism, BNB Chain, Avalanche, Hyperliquid, Solana, Sui, Aptos, TON, NEAR, or Tron."
                    )
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Token Details")) {
                Picker(AppLocalization.string("Chain"), selection: $selectedChain) {
                    ForEach(TokenTrackingChain.allCases) { chain in Text(chain.rawValue).tag(chain) }
                }
                TextField(AppLocalization.string("Symbol"), text: $symbolInput).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField(AppLocalization.string("Name"), text: $nameInput)
                TextField(selectedChain.contractAddressPrompt, text: $contractInput).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper(AppLocalization.format("Token Supports: %lld decimals", decimalsInput), value: $decimalsInput, in: 0...30, step: 1)
                TextField(AppLocalization.string("CoinGecko ID (Optional)"), text: $coinGeckoIdInput).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                if let formMessage { Text(formMessage).font(.caption).foregroundStyle(.secondary) }
                Button(AppLocalization.string("Add Token")) {
                    let message = store.addCustomTokenPreference(
                        chain: selectedChain, symbol: symbolInput, name: nameInput, contractAddress: contractInput, marketDataId: "0",
                        coinGeckoId: coinGeckoIdInput, decimals: decimalsInput
                    )
                    if let message {
                        formMessage = message
                    } else {
                        formMessage = AppLocalization.string("Token added.")
                        symbolInput = ""
                        nameInput = ""
                        contractInput = ""
                        coinGeckoIdInput = ""
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("New Token"))
    }
}
struct DecimalDisplaySettingsView: View {
    let store: AppState
    @State private var searchText: String = ""
    private let decimalExamples: [(symbol: String, chainName: String)] = [
        ("BTC", "Bitcoin"), ("BCH", "Bitcoin Cash"), ("LTC", "Litecoin"), ("DOGE", "Dogecoin"), ("ETH", "Ethereum"),
        ("ETC", "Ethereum Classic"), ("BNB", "BNB Chain"), ("AVAX", "Avalanche"), ("HYPE", "Hyperliquid"), ("SOL", "Solana"),
        ("ADA", "Cardano"), ("XRP", "XRP Ledger"), ("TRX", "Tron"), ("XMR", "Monero"), ("SUI", "Sui"), ("APT", "Aptos"), ("TON", "TON"),
        ("ICP", "Internet Computer"), ("NEAR", "NEAR"), ("DOT", "Polkadot"), ("XLM", "Stellar"),
    ]
    var body: some View {
        Form {
            Section {
                Text(
                    AppLocalization.string(
                        "Search native assets and tracked tokens, then adjust how many decimals Spectra shows in portfolio and wallet views."
                    )
                ).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(AppLocalization.string("Search symbol, name, chain, or address"), text: $searchText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }.padding(.horizontal, 12).padding(.vertical, 10).background(
                    .thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Section(AppLocalization.string("Native Asset Display")) {
                Text(
                    AppLocalization.string(
                        "Adjust how many decimals are shown for each chain's native asset. Very small values switch to a threshold marker instead of rounding to zero."
                    )
                ).font(.caption).foregroundStyle(.secondary)
                Button(AppLocalization.string("Reset Native Asset Display")) {
                    store.resetNativeAssetDisplayDecimals()
                }
                if filteredDecimalExamples.isEmpty {
                    Text(AppLocalization.string("No matching native assets.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredDecimalExamples, id: \.symbol) { example in
                        let currentDisplayDecimals = store.assetDisplayDecimalPlaces(for: example.chainName)
                        let supportedDecimals = store.supportedAssetDecimals(symbol: example.symbol, chainName: example.chainName)
                        decimalStepperCard(
                            assetIdentifier: Coin.iconIdentifier(symbol: example.symbol, chainName: example.chainName),
                            fallbackText: Coin.displayMark(for: example.symbol), tint: Coin.displayColor(for: example.symbol),
                            title: example.chainName, subtitle: example.symbol, currentDisplayDecimals: currentDisplayDecimals,
                            supportedDecimals: supportedDecimals, supportedLabel: AppLocalization.string("Asset supports"),
                            onDecrease: {
                                store.setAssetDisplayDecimalPlaces(currentDisplayDecimals - 1, for: example.chainName)
                            },
                            onIncrease: {
                                store.setAssetDisplayDecimalPlaces(currentDisplayDecimals + 1, for: example.chainName)
                            }
                        )
                    }
                }
            }
            Section(AppLocalization.string("Tracked Token Decimals")) {
                Text(
                    AppLocalization.string(
                        "ERC-20 and TRC-20 tokens expose decimals on the contract, and Solana tokens store decimals on the mint account. Manage tracked token decimal support separately from native asset display precision."
                    )
                ).font(.caption).foregroundStyle(.secondary)
                Button(AppLocalization.string("Reset Tracked Token Display")) {
                    store.resetTrackedTokenDisplayDecimals()
                }
                if filteredTokenDecimalEntries.isEmpty {
                    Text(
                        store.enabledTrackedTokenPreferences.isEmpty
                            ? AppLocalization.string("No tokens are currently enabled for tracking.")
                            : AppLocalization.string("No matching tracked tokens.")
                    ).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTokenDecimalEntries, id: \.id) { entry in
                        let currentDisplayDecimals = store.displayAssetDecimals(symbol: entry.symbol, chainName: entry.chain.rawValue)
                        let supportedDecimals = Int(entry.decimals)
                        decimalStepperCard(
                            assetIdentifier: decimalTokenAssetIdentifier(for: entry),
                            fallbackText: String(entry.symbol.prefix(2)).uppercased(), tint: decimalTokenTint(for: entry.chain),
                            title: entry.name, subtitle: "\(entry.chain.rawValue) · \(entry.symbol)",
                            currentDisplayDecimals: currentDisplayDecimals, supportedDecimals: supportedDecimals,
                            supportedLabel: AppLocalization.string("Token supports"), detailText: entry.contractAddress,
                            onDecrease: {
                                store.updateTokenPreferenceDisplayDecimals(id: entry.id, decimals: currentDisplayDecimals - 1)
                            },
                            onIncrease: {
                                store.updateTokenPreferenceDisplayDecimals(id: entry.id, decimals: currentDisplayDecimals + 1)
                            }
                        )
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Decimal Display"))
    }
    private var filteredDecimalExamples: [(symbol: String, chainName: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return decimalExamples }
        return decimalExamples.filter { example in [example.symbol, example.chainName].joined(separator: " ").lowercased().contains(query) }
    }
    private var filteredTokenDecimalEntries: [TokenPreferenceEntry] {
        let entries = store.enabledTrackedTokenPreferences.sorted { lhs, rhs in
            if lhs.chain.rawValue != rhs.chain.rawValue { return lhs.chain.rawValue < rhs.chain.rawValue }
            return lhs.symbol < rhs.symbol
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            [
                entry.symbol, entry.name, entry.chain.rawValue, entry.contractAddress, entry.coinGeckoId,
            ].joined(separator: " ").lowercased().contains(query)
        }
    }
    @ViewBuilder
    private func decimalStepperCard(
        assetIdentifier: String?, fallbackText: String, tint: Color, title: String, subtitle: String, currentDisplayDecimals: Int,
        supportedDecimals: Int, supportedLabel: String, detailText: String? = nil, onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CoinBadge(assetIdentifier: assetIdentifier, fallbackText: fallbackText, color: tint, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if let detailText, !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(detailText).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).disabled(currentDisplayDecimals <= 0)
                    Text("\(currentDisplayDecimals)").font(.subheadline.monospacedDigit()).frame(minWidth: 30)
                    Button(action: onIncrease) {
                        Image(systemName: "plus.circle")
                    }.buttonStyle(.plain).disabled(currentDisplayDecimals >= supportedDecimals)
                }.font(.title3)
            }
            HStack {
                Text(supportedLabel)
                Spacer()
                Text(AppLocalization.format("%lld decimals", supportedDecimals)).foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(.vertical, 4)
    }
    private func decimalTokenAssetIdentifier(for entry: TokenPreferenceEntry) -> String? {
        let slug = entry.chain.slug
        let symbol = entry.symbol.lowercased()
        if !entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(slug):\(entry.coinGeckoId.lowercased()):\(symbol)"
        }
        return "\(slug):\(symbol)"
    }
    private func decimalTokenTint(for chain: TokenTrackingChain) -> Color {
        switch chain {
        case .ethereum, .ton: return .blue
        case .arbitrum, .aptos: return .cyan
        case .optimism, .avalanche, .tron: return .red
        case .bnb: return .yellow
        case .hyperliquid, .sui: return .mint
        case .solana: return .purple
        case .near: return .indigo
        }
    }
}
struct LogsView: View {
    let store: AppState
    @State private var searchText: String = ""
    @State private var selectedLevelFilter: LogLevelFilter = .all
    private let allCategoryFilter = "__all__"
    @State private var selectedCategoryFilter: String = "__all__"
    @State private var copiedNotice: String?
    @State private var cachedAvailableCategories: [String] = ["__all__"]
    @State private var cachedFilteredLogs: [AppState.OperationalLogEvent] = []
    private var diagnosticsState: WalletDiagnosticsState { store.diagnostics }
    private enum LogLevelFilter: CaseIterable, Identifiable {
        case all
        case debug
        case info
        case warning
        case error
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return AppLocalization.string("All")
            case .debug: return AppLocalization.string("Debug")
            case .info: return AppLocalization.string("Info")
            case .warning: return AppLocalization.string("Warning")
            case .error: return AppLocalization.string("Error")
            }
        }
    }
    private var availableCategories: [String] { cachedAvailableCategories }
    private var filteredLogs: [AppState.OperationalLogEvent] { cachedFilteredLogs }
    private func rebuildLogPresentation() {
        let categories = Set(diagnosticsState.operationalLogs.map { $0.category })
        cachedAvailableCategories = [allCategoryFilter] + categories.sorted()
        if selectedCategoryFilter != allCategoryFilter, !cachedAvailableCategories.contains(selectedCategoryFilter) {
            selectedCategoryFilter = allCategoryFilter
        }
        cachedFilteredLogs = diagnosticsState.operationalLogs.filter { event in
            let levelMatches: Bool
            switch selectedLevelFilter {
            case .all: levelMatches = true
            case .debug: levelMatches = event.level == .debug
            case .info: levelMatches = event.level == .info
            case .warning: levelMatches = event.level == .warning
            case .error: levelMatches = event.level == .error
            }
            let categoryMatches = selectedCategoryFilter == allCategoryFilter || event.category == selectedCategoryFilter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatches: Bool
            if query.isEmpty {
                searchMatches = true
            } else {
                let haystack = [
                    event.message, event.category, event.chainName ?? "", event.source ?? "", event.metadata ?? "", event.walletID ?? "",
                    event.transactionHash ?? "",
                ].joined(separator: " ").lowercased()
                searchMatches = haystack.contains(query)
            }
            return levelMatches && categoryMatches && searchMatches
        }
    }
    private var summaryText: String {
        let debugCount = filteredLogs.filter { $0.level == .debug }.count
        let infoCount = filteredLogs.filter { $0.level == .info }.count
        let warningCount = filteredLogs.filter { $0.level == .warning }.count
        let errorCount = filteredLogs.filter { $0.level == .error }.count
        return AppLocalization.format(
            "Showing %lld logs • D:%lld I:%lld W:%lld E:%lld", filteredLogs.count, debugCount, infoCount, warningCount, errorCount)
    }
    var body: some View {
        List {
            Section(AppLocalization.string("Status")) {
                Text(store.pendingTransactionRefreshStatusText ?? AppLocalization.string("No refresh status yet")).font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
                if let copiedNotice { Text(copiedNotice).font(.caption).foregroundStyle(.secondary) }
            }
            Section(AppLocalization.string("Filters")) {
                Picker(AppLocalization.string("Level"), selection: $selectedLevelFilter) {
                    ForEach(LogLevelFilter.allCases) { level in Text(level.title).tag(level) }
                }
                Picker(AppLocalization.string("Category"), selection: $selectedCategoryFilter) {
                    ForEach(availableCategories, id: \.self) { category in
                        let label: String = category == allCategoryFilter ? AppLocalization.string("All") : category
                        Text(label).tag(category)
                    }
                }
            }
            if filteredLogs.isEmpty {
                Section(AppLocalization.string("Events")) {
                    Text(AppLocalization.string("No operational events yet.")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(AppLocalization.string("Events")) {
                    ForEach(filteredLogs) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: event.level)).foregroundStyle(color(for: event.level))
                                Text(event.timestamp.formatted(date: .abbreviated, time: .standard)).font(.caption.bold()).foregroundStyle(
                                    .secondary)
                                Text(event.category).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6)
                                    .padding(.vertical, 2).background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            Text(event.message).font(.subheadline)
                            if let source = event.source, !source.isEmpty {
                                Text(AppLocalization.format("source: %@", source)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            if let chainName = event.chainName, !chainName.isEmpty {
                                Text(AppLocalization.format("chain: %@", chainName)).font(.caption.monospaced()).foregroundStyle(
                                    .secondary)
                            }
                            if let walletID = event.walletID {
                                Text(AppLocalization.format("wallet: %@", walletID)).font(.caption.monospaced()).foregroundStyle(
                                    .secondary
                                ).textSelection(.enabled)
                            }
                            if let transactionHash = event.transactionHash, !transactionHash.isEmpty {
                                Text(transactionHash).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if let metadata = event.metadata, !metadata.isEmpty {
                                Text(metadata).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Logs")).searchable(
            text: $searchText, prompt: AppLocalization.string("Search message, chain, tx hash, wallet")
        ).onAppear {
            rebuildLogPresentation()
        }.onChange(of: diagnosticsState.operationalLogsRevision) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: selectedLevelFilter) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: selectedCategoryFilter) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: searchText) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: copiedNotice) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copiedNotice = nil
            }
        }.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Copy")) {
                    UIPasteboard.general.string = store.exportOperationalLogsText(events: filteredLogs)
                    copiedNotice = AppLocalization.format("Copied %lld log entries", filteredLogs.count)
                }.disabled(filteredLogs.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Clear"), role: .destructive) {
                    store.clearOperationalLogs()
                }.disabled(diagnosticsState.operationalLogs.isEmpty)
            }
        }
    }
    private func iconName(for level: AppState.OperationalLogEvent.Level) -> String {
        switch level {
        case .debug: return "ladybug.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    private func color(for level: AppState.OperationalLogEvent.Level) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
struct ResetWalletWarningView: View {
    let store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScopes = Set(AppState.ResetScope.allCases)
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(
                        AppLocalization.string(
                            "Choose which categories to remove from this device. Selected items are deleted locally and some options also clear secure keychain data."
                        )
                    ).font(.body)
                    Text(
                        AppLocalization.string(
                            "You must have your seed phrase backed up. Without it, you cannot recover your funds after reset.")
                    ).font(.body.weight(.semibold)).foregroundStyle(.red)
                } header: {
                    Text(AppLocalization.string("Before You Continue"))
                }
                Section(AppLocalization.string("Choose What To Reset")) {
                    ForEach(AppState.ResetScope.allCases) { scope in
                        Toggle(isOn: binding(for: scope)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.title)
                                Text(scope.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section(AppLocalization.string("Selected Reset Summary")) {
                    if selectedScopes.contains(.walletsAndSecrets) {
                        Label(
                            AppLocalization.string("Imported wallets, watched addresses, and secure seed material"),
                            systemImage: "wallet.pass")
                    }
                    if selectedScopes.contains(.historyAndCache) {
                        Label(
                            AppLocalization.string("Transaction history, chain snapshots, diagnostics, and network caches"),
                            systemImage: "clock.arrow.circlepath")
                    }
                    if selectedScopes.contains(.alertsAndContacts) {
                        Label(
                            AppLocalization.string("Price alerts, notification rules, and address book recipients"),
                            systemImage: "bell.slash")
                    }
                    if selectedScopes.contains(.settingsAndEndpoints) {
                        Label(
                            AppLocalization.string("Tracked tokens, API keys, endpoint settings, preferences, and custom icons"),
                            systemImage: "slider.horizontal.3")
                    }
                    if selectedScopes.contains(.dashboardCustomization) {
                        Label(AppLocalization.string("Pinned assets and dashboard customization choices"), systemImage: "square.grid.2x2")
                    }
                    if selectedScopes.contains(.providerState) {
                        Label(
                            AppLocalization.string("Provider selections, reliability memory, and low-level network state"),
                            systemImage: "network")
                    }
                    if selectedScopes.isEmpty {
                        Text(AppLocalization.string("Select at least one category to enable reset.")).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(AppLocalization.string("Reset Selected Data"), role: .destructive) {
                        Task {
                            await store.resetSelectedData(scopes: selectedScopes)
                            dismiss()
                        }
                    }.disabled(selectedScopes.isEmpty)
                }
            }.navigationTitle(AppLocalization.string("Reset Wallet")).toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
    private func binding(for scope: AppState.ResetScope) -> Binding<Bool> {
        Binding(
            get: { selectedScopes.contains(scope) },
            set: { isSelected in
                if isSelected { selectedScopes.insert(scope) } else { selectedScopes.remove(scope) }
            }
        )
    }
}
struct TokenIconSettingsView: View {
    private let availableSettings: [TokenIconSetting] =
        ChainRegistryEntry.all.map {
            TokenIconSetting(
                title: $0.name, symbol: $0.symbol, assetIdentifier: $0.assetIdentifier, mark: $0.mark, color: $0.color
            )
        }
        + TokenVisualRegistryEntry.all.map {
            TokenIconSetting(
                title: $0.title, symbol: $0.symbol, assetIdentifier: $0.assetIdentifier, mark: $0.mark, color: $0.color
            )
        }
    @AppStorage(TokenIconPreferenceStore.defaultsKey) private var tokenIconPreferencesStorage = ""
    @State private var searchText = ""
    private var filteredSettings: [TokenIconSetting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableSettings }
        return availableSettings.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.symbol.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        Form {
            Section {
                ForEach(filteredSettings) { setting in TokenIconCustomizationRow(setting: setting) }
            } header: {
                Text(AppLocalization.string("Token Icons"))
            } footer: {
                Text(
                    AppLocalization.string(
                        "Choose custom artwork, your own photo, or the classic generated badge style. Uploaded images must be 3 MB or smaller."
                    ))
            }
        }.navigationTitle(AppLocalization.string("Icon Styles")).searchable(
            text: $searchText, prompt: AppLocalization.string("Search icons")
        ).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Reset")) {
                    tokenIconPreferencesStorage = ""
                }.disabled(tokenIconPreferencesStorage.isEmpty)
            }
        }
    }
}
struct MainTabView: View {
    @Bindable var store: AppState
    var body: some View {
        TabView(selection: $store.selectedMainTab) {
            DashboardView(store: store).tabItem {
                Label(AppLocalization.string("Home"), systemImage: "chart.pie.fill")
            }.tag(MainAppTab.home)
            HistoryView(store: store).tabItem {
                Label(AppLocalization.string("History"), systemImage: "clock.arrow.circlepath")
            }.tag(MainAppTab.history)
            StakingView().tabItem {
                Label(AppLocalization.string("Staking"), systemImage: "link.circle.fill")
            }.tag(MainAppTab.staking)
            DonationsView().tabItem {
                Label(AppLocalization.string("Donate"), systemImage: "heart.fill")
            }.tag(MainAppTab.donate)
            SettingsView(store: store).tabItem {
                Label(AppLocalization.string("Settings"), systemImage: "gearshape.fill")
            }.tag(MainAppTab.settings)
        }
    }
}
