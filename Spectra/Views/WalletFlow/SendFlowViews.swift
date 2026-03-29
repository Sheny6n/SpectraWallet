import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import VisionKit


struct SendView: View {
    let store: WalletStore
    @ObservedObject private var flowState: WalletFlowState
    @ObservedObject private var sendState: WalletSendState
    @ObservedObject private var runtimeState: WalletRuntimeState
    @ObservedObject private var portfolioState: WalletPortfolioState
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?

    private struct SendLiveActivitySnapshot {
        let walletName: String
        let chainName: String
        let symbol: String
        let amountText: String
        let destinationAddress: String
    }

    private struct PrimaryPresentation {
        let sendWallets: [ImportedWallet]
        let selectedWallet: ImportedWallet?
        let availableSendCoins: [Coin]
        let selectedCoin: Coin?
        let selectedCoinAmountText: String?
        let selectedCoinApproximateFiatText: String?
        let addressBookEntries: [AddressBookEntry]
    }

    init(store: WalletStore) {
        self.store = store
        _flowState = ObservedObject(wrappedValue: store.flowState)
        _sendState = ObservedObject(wrappedValue: store.sendState)
        _runtimeState = ObservedObject(wrappedValue: store.runtimeState)
        _portfolioState = ObservedObject(wrappedValue: store.portfolioState)
    }

    private var sendAdvancedModeBinding: Binding<Bool> {
        Binding(get: { store.sendAdvancedMode }, set: { store.sendAdvancedMode = $0 })
    }

    private var sendUTXOMaxInputCountBinding: Binding<Int> {
        Binding(get: { store.sendUTXOMaxInputCount }, set: { store.sendUTXOMaxInputCount = $0 })
    }

    private var sendEnableRBFBinding: Binding<Bool> {
        Binding(get: { store.sendEnableRBF }, set: { store.sendEnableRBF = $0 })
    }

    private var sendEnableCPFPBinding: Binding<Bool> {
        Binding(get: { store.sendEnableCPFP }, set: { store.sendEnableCPFP = $0 })
    }

    private var sendLitecoinChangeStrategyBinding: Binding<LitecoinWalletEngine.ChangeStrategy> {
        Binding(get: { store.sendLitecoinChangeStrategy }, set: { store.sendLitecoinChangeStrategy = $0 })
    }

    private var bitcoinFeePriorityBinding: Binding<BitcoinFeePriority> {
        Binding(get: { store.bitcoinFeePriority }, set: { store.bitcoinFeePriority = $0 })
    }

    private var useCustomEthereumFeesBinding: Binding<Bool> {
        Binding(get: { store.useCustomEthereumFees }, set: { store.useCustomEthereumFees = $0 })
    }

    private var customEthereumMaxFeeGweiBinding: Binding<String> {
        Binding(get: { store.customEthereumMaxFeeGwei }, set: { store.customEthereumMaxFeeGwei = $0 })
    }

    private var customEthereumPriorityFeeGweiBinding: Binding<String> {
        Binding(get: { store.customEthereumPriorityFeeGwei }, set: { store.customEthereumPriorityFeeGwei = $0 })
    }

    private var ethereumManualNonceEnabledBinding: Binding<Bool> {
        Binding(get: { store.ethereumManualNonceEnabled }, set: { store.ethereumManualNonceEnabled = $0 })
    }

    private var ethereumManualNonceBinding: Binding<String> {
        Binding(get: { store.ethereumManualNonce }, set: { store.ethereumManualNonce = $0 })
    }

    private var dogecoinFeePriorityBinding: Binding<DogecoinWalletEngine.FeePriority> {
        Binding(get: { store.dogecoinFeePriority }, set: { store.dogecoinFeePriority = $0 })
    }

    private var sendPreviewTaskID: String {
        [
            flowState.sendWalletID,
            flowState.sendHoldingKey,
            flowState.sendAddress,
            flowState.sendAmount,
            store.dogecoinFeePriority.rawValue,
            store.useCustomEthereumFees ? "custom-on" : "custom-off",
            store.customEthereumMaxFeeGwei,
            store.customEthereumPriorityFeeGwei,
            store.ethereumManualNonceEnabled ? "manual-nonce-on" : "manual-nonce-off",
            store.ethereumManualNonce,
            store.sendAdvancedMode ? "adv-on" : "adv-off",
            "\(store.sendUTXOMaxInputCount)"
        ].joined(separator: "|")
    }

    private var isSendBusy: Bool {
        sendState.isSendingBitcoin
            || sendState.isSendingBitcoinCash
            || sendState.isSendingLitecoin
            || sendState.isSendingEthereum
            || sendState.isSendingDogecoin
            || sendState.isSendingTron
            || sendState.isSendingXRP
            || sendState.isSendingMonero
            || sendState.isSendingCardano
            || sendState.isSendingNear
            || runtimeState.isPreparingEthereumSend
            || runtimeState.isPreparingDogecoinSend
            || runtimeState.isPreparingTronSend
            || runtimeState.isPreparingXRPSend
            || runtimeState.isPreparingMoneroSend
            || runtimeState.isPreparingCardanoSend
            || runtimeState.isPreparingNearSend
    }

    private var primaryPresentation: PrimaryPresentation {
        let sendWallets = store.sendEnabledWallets
        let selectedWallet = sendWallets.first(where: { $0.id.uuidString == flowState.sendWalletID })
        let availableSendCoins = store.availableSendCoins(for: flowState.sendWalletID)
        let selectedCoin = availableSendCoins.first(where: { $0.holdingKey == flowState.sendHoldingKey })
        let selectedCoinAmountText = selectedCoin.map {
            store.formattedAssetAmount($0.amount, symbol: $0.symbol, chainName: $0.chainName)
        }
        let sendAmount = Double(flowState.sendAmount) ?? 0
        let selectedCoinApproximateFiatText: String?
        if let selectedCoin, !sendAmount.isZero {
            selectedCoinApproximateFiatText = store.formattedFiatAmount(fromNative: sendAmount, symbol: selectedCoin.symbol)
        } else {
            selectedCoinApproximateFiatText = nil
        }

        return PrimaryPresentation(
            sendWallets: sendWallets,
            selectedWallet: selectedWallet,
            availableSendCoins: availableSendCoins,
            selectedCoin: selectedCoin,
            selectedCoinAmountText: selectedCoinAmountText,
            selectedCoinApproximateFiatText: selectedCoinApproximateFiatText,
            addressBookEntries: store.sendAddressBookEntries
        )
    }

    private var sendLiveActivitySnapshot: SendLiveActivitySnapshot? {
        guard let selectedCoin = primaryPresentation.selectedCoin else { return nil }
        guard let selectedWallet = primaryPresentation.selectedWallet else { return nil }
        let trimmedAmount = flowState.sendAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = flowState.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAmount.isEmpty, !trimmedAddress.isEmpty else { return nil }
        return SendLiveActivitySnapshot(
            walletName: selectedWallet.name,
            chainName: selectedCoin.chainName,
            symbol: selectedCoin.symbol,
            amountText: trimmedAmount,
            destinationAddress: trimmedAddress
        )
    }

    @ViewBuilder
    private var primarySendSections: some View {
        let presentation = primaryPresentation

        sendDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let selectedCoin = presentation.selectedCoin {
                        CoinBadge(
                            assetIdentifier: selectedCoin.iconIdentifier,
                            fallbackText: selectedCoin.mark,
                            color: selectedCoin.color,
                            size: 42
                        )
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.mint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send")
                            .font(.title3.weight(.bold))
                        if let wallet = presentation.selectedWallet {
                            Text(wallet.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let selectedCoin = presentation.selectedCoin {
                        Text(selectedCoin.symbol)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedCoin.color.opacity(0.18), in: Capsule())
                            .foregroundStyle(selectedCoin.color)
                    }
                }

                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(presentation.selectedCoinAmountText ?? "")
                                .font(.headline.weight(.semibold))
                                .spectraNumericTextLayout()
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Network")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedCoin.chainName)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } else {
                    Text("Choose a wallet and asset to prepare a transfer with live fee previews and risk checks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }

        sendDetailCard(title: "Wallet & Asset") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Wallet", selection: store.sendWalletIDBinding) {
                    ForEach(presentation.sendWallets) { wallet in
                        Text(wallet.name).tag(wallet.id.uuidString)
                    }
                }
                .onChange(of: store.sendWalletID) { _, _ in
                    store.syncSendAssetSelection()
                }

                Picker("Asset", selection: store.sendHoldingKeyBinding) {
                    ForEach(presentation.availableSendCoins, id: \.holdingKey) { coin in
                        Text("\(coin.name) on \(coin.chainName)").tag(coin.holdingKey)
                    }
                }
            }
        }

        sendDetailCard(title: "Recipient") {
            VStack(alignment: .leading, spacing: 12) {
                if !presentation.addressBookEntries.isEmpty {
                    Picker("Saved Recipient", selection: $selectedAddressBookEntryID) {
                        Text("None").tag("")
                        ForEach(presentation.addressBookEntries) { entry in
                            Text("\(entry.name) • \(entry.chainName)").tag(entry.id.uuidString)
                        }
                    }
                    .onChange(of: selectedAddressBookEntryID) { _, newValue in
                        guard let selectedEntry = primaryPresentation.addressBookEntries.first(where: { $0.id.uuidString == newValue }) else {
                            return
                        }
                        store.sendAddress = selectedEntry.address
                    }
                }

                HStack(spacing: 10) {
                    TextField("Recipient address", text: store.sendAddressBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        guard DataScannerViewController.isSupported else {
                            qrScannerErrorMessage = "QR scanning is not supported on this device."
                            return
                        }
                        guard DataScannerViewController.isAvailable else {
                            qrScannerErrorMessage = "QR scanning is unavailable right now. Check camera permission and try again."
                            return
                        }
                        isShowingQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Scan QR Code")
                }

                if let qrScannerErrorMessage {
                    Text(qrScannerErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if flowState.isCheckingSendDestinationBalance {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking destination on-chain balance...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let sendDestinationRiskWarning = flowState.sendDestinationRiskWarning {
                    Text(sendDestinationRiskWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let sendDestinationInfoMessage = flowState.sendDestinationInfoMessage {
                    Text(sendDestinationInfoMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        sendDetailCard(title: "Amount") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Amount", text: store.sendAmountBinding)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        Text("Using")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedCoin.symbol)
                            .font(.subheadline.weight(.semibold))
                    }

                    if let fiatAmount = presentation.selectedCoinApproximateFiatText {
                        HStack {
                            Text("Approx. Value")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(fiatAmount)
                                .font(.subheadline.weight(.semibold))
                                .spectraNumericTextLayout()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sendStatusSections: some View {
        if let sendError = flowState.sendError {
            sendDetailCard {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        if let sendVerificationNotice = flowState.sendVerificationNotice {
            sendDetailCard(title: "Verification") {
                Text(sendVerificationNotice)
                    .font(.caption)
                    .foregroundStyle(flowState.sendVerificationNoticeIsWarning ? .red : .orange)
            }
        }

        if let lastSentTransaction = sendState.lastSentTransaction {
            sendDetailCard(title: "Last Sent") {
                Text(walletFlowLocalizedFormat("%@ sent to %@", lastSentTransaction.symbol, lastSentTransaction.addressPreviewText))
                    .font(.subheadline)
                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TransactionStatusBadge(status: lastSentTransaction.status)
                }
                if let pendingTransactionRefreshStatusText = store.pendingTransactionRefreshStatusText {
                    Text(pendingTransactionRefreshStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let transactionHash = lastSentTransaction.transactionHash {
                    Text(transactionHash)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }

                if let transactionExplorerURL = lastSentTransaction.transactionExplorerURL,
                   let transactionExplorerLabel = lastSentTransaction.transactionExplorerLabel {
                    Link(destination: transactionExplorerURL) {
                        Label(transactionExplorerLabel, systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                }

                Button {
                    store.saveLastSentRecipientToAddressBook()
                } label: {
                    Label(
                        store.canSaveLastSentRecipientToAddressBook() ? "Save Recipient To Address Book" : "Recipient Already Saved",
                        systemImage: store.canSaveLastSentRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .disabled(!store.canSaveLastSentRecipientToAddressBook())
            }
        }

        if sendState.isSendingBitcoin {
            sendingSection("Broadcasting Bitcoin transaction...")
        }
        if sendState.isSendingBitcoinCash {
            sendingSection("Broadcasting Bitcoin Cash transaction...")
        }
        if sendState.isSendingLitecoin {
            sendingSection("Broadcasting Litecoin transaction...")
        }
        if sendState.isSendingEthereum {
            sendingSection("Broadcasting \(store.selectedSendCoin?.chainName ?? "EVM") transaction...")
        }
        if sendState.isSendingDogecoin {
            sendingSection("Broadcasting Dogecoin transaction...")
        }
        if sendState.isSendingTron {
            sendingSection("Broadcasting Tron transaction...")
        }
        if sendState.isSendingXRP {
            sendingSection("Broadcasting XRP transaction...")
        }
        if sendState.isSendingMonero {
            sendingSection("Broadcasting Monero transaction...")
        }
        if sendState.isSendingCardano {
            sendingSection("Broadcasting Cardano transaction...")
        }
    }

    private func sendingSection(_ title: String) -> some View {
        sendDetailCard {
            HStack(spacing: 10) {
                ProgressView()
                Text(title)
                    .font(.caption)
            }
        }
    }

    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        guard let coin else { return false }
        let chainName = coin.chainName
        return chainName == "Bitcoin"
            || chainName == "Bitcoin Cash"
            || chainName == "Bitcoin SV"
            || chainName == "Litecoin"
            || chainName == "Dogecoin"
            || chainName == "Ethereum"
            || chainName == "Ethereum Classic"
            || chainName == "Arbitrum"
            || chainName == "Optimism"
            || chainName == "BNB Chain"
            || chainName == "Avalanche"
            || chainName == "Hyperliquid"
            || chainName == "Tron"
            || chainName == "XRP Ledger"
            || chainName == "Cardano"
            || chainName == "NEAR"
            || chainName == "Polkadot"
            || chainName == "Stellar"
            || chainName == "Internet Computer"
    }

    private func utxoPreview(for coin: Coin) -> BitcoinSendPreview? {
        if coin.chainName == "Litecoin" {
            return store.litecoinSendPreview
        }
        if coin.chainName == "Bitcoin Cash" {
            return store.bitcoinCashSendPreview
        }
        return store.bitcoinSendPreview
    }

    @ViewBuilder
    private func networkSendSections(selectedCoin: Coin?) -> some View {
        if let selectedCoin,
           selectedCoin.chainName == "Bitcoin" || selectedCoin.chainName == "Bitcoin Cash" || selectedCoin.chainName == "Bitcoin SV" || selectedCoin.chainName == "Litecoin" || selectedCoin.chainName == "Dogecoin" {
            Section("Advanced UTXO Mode") {
                Toggle("Enable Advanced Controls", isOn: sendAdvancedModeBinding)
                if store.sendAdvancedMode {
                    Stepper(
                        "Max Inputs: \(store.sendUTXOMaxInputCount == 0 ? "Auto" : "\(store.sendUTXOMaxInputCount)")",
                        value: sendUTXOMaxInputCountBinding,
                        in: 0 ... 50
                    )
                    if selectedCoin.chainName == "Litecoin" {
                        Toggle("Enable RBF Policy", isOn: sendEnableRBFBinding)
                        Picker("Change Strategy", selection: sendLitecoinChangeStrategyBinding) {
                            ForEach(LitecoinWalletEngine.ChangeStrategy.allCases) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("RBF Intent", isOn: sendEnableRBFBinding)
                        Toggle("CPFP Intent", isOn: sendEnableCPFPBinding)
                        if selectedCoin.chainName == "Bitcoin" {
                            Text("For Bitcoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedCoin.chainName == "Bitcoin Cash" {
                            Text("For Bitcoin Cash sends, advanced mode records RBF intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedCoin.chainName == "Dogecoin" {
                            Text("For Dogecoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if let selectedCoin,
           ((selectedCoin.chainName == "Bitcoin" && selectedCoin.symbol == "BTC")
               || (selectedCoin.chainName == "Bitcoin Cash" && selectedCoin.symbol == "BCH")
               || (selectedCoin.chainName == "Bitcoin SV" && selectedCoin.symbol == "BSV")
               || (selectedCoin.chainName == "Litecoin" && selectedCoin.symbol == "LTC")) {
            let feeSymbol = selectedCoin.symbol
            let utxoPreview = utxoPreview(for: selectedCoin)
            Section(walletFlowLocalizedFormat("%@ Network", selectedCoin.chainName)) {
                Picker("Fee Priority", selection: bitcoinFeePriorityBinding) {
                    ForEach(BitcoinFeePriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                if let utxoPreview {
                    Text(walletFlowLocalizedFormat("Estimated Fee Rate: %llu sat/vB", utxoPreview.estimatedFeeRateSatVb))
                    if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFeeBTC, symbol: feeSymbol) {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBTC, specifier: "%.8f") \(feeSymbol) (~\(fiatFee))")
                    } else {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBTC, specifier: "%.8f") \(feeSymbol)")
                    }
                } else {
                    Text(walletFlowLocalizedFormat("Enter amount to preview estimated %@ network fee.", selectedCoin.chainName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let selectedCoin,
           (selectedCoin.chainName == "Ethereum" || selectedCoin.chainName == "Ethereum Classic" || selectedCoin.chainName == "Arbitrum" || selectedCoin.chainName == "Optimism" || selectedCoin.chainName == "BNB Chain" || selectedCoin.chainName == "Avalanche" || selectedCoin.chainName == "Hyperliquid") {
            Section(walletFlowLocalizedFormat("%@ Network", selectedCoin.chainName)) {
                Toggle("Use Custom Fees", isOn: useCustomEthereumFeesBinding)

                if store.useCustomEthereumFees {
                    TextField("Max Fee (gwei)", text: customEthereumMaxFeeGweiBinding)
                        .keyboardType(.decimalPad)
                    TextField("Priority Fee (gwei)", text: customEthereumPriorityFeeGweiBinding)
                        .keyboardType(.decimalPad)

                    if let customEthereumFeeValidationError = store.customEthereumFeeValidationError {
                        Text(customEthereumFeeValidationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Custom EIP-1559 fees are applied to this send and preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Manual Nonce", isOn: ethereumManualNonceEnabledBinding)
                if store.ethereumManualNonceEnabled {
                    TextField("Nonce", text: ethereumManualNonceBinding)
                        .keyboardType(.numberPad)
                    if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
                        Text(customEthereumNonceValidationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if selectedCoin.chainName == "Ethereum" {
                    if runtimeState.isPreparingEthereumReplacementContext {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing replacement/cancel context...")
                                .font(.caption)
                        }
                    } else if store.hasPendingEthereumSendForSelectedWallet {
                        Button("Speed Up Pending Transaction") {
                            Task { await store.prepareEthereumSpeedUpContext() }
                        }
                        Button("Cancel Pending Transaction") {
                            Task { await store.prepareEthereumCancelContext() }
                        }
                    }

                    if let ethereumReplacementNonceStateMessage = store.ethereumReplacementNonceStateMessage {
                        Text(ethereumReplacementNonceStateMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if runtimeState.isPreparingEthereumSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading nonce and fee estimate...")
                            .font(.caption)
                    }
                } else if let ethereumSendPreview = store.ethereumSendPreview {
                    Text(walletFlowLocalizedFormat("send.preview.nonceLabel", ethereumSendPreview.nonce))
                    Text(walletFlowLocalizedFormat("Gas Limit: %lld", ethereumSendPreview.gasLimit))
                    Text(walletFlowLocalizedFormat("Max Fee: %.2f gwei", ethereumSendPreview.maxFeePerGasGwei))
                    Text(walletFlowLocalizedFormat("Priority Fee: %.2f gwei", ethereumSendPreview.maxPriorityFeePerGasGwei))
                    let feeSymbol = selectedCoin.chainName == "BNB Chain" ? "BNB" : (selectedCoin.chainName == "Ethereum Classic" ? "ETC" : (selectedCoin.chainName == "Avalanche" ? "AVAX" : (selectedCoin.chainName == "Hyperliquid" ? "HYPE" : "ETH")))
                    if let fiatFee = store.formattedFiatAmount(fromNative: ethereumSendPreview.estimatedNetworkFeeETH, symbol: feeSymbol) {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f %@ (~%@)", ethereumSendPreview.estimatedNetworkFeeETH, feeSymbol, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f %@", ethereumSendPreview.estimatedNetworkFeeETH, feeSymbol))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(walletFlowLocalizedFormat("Spectra signs and broadcasts supported %@ transfers. This preview is the live nonce and fee estimate for the transaction you are about to send.", selectedCoin.chainName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Tron" {
            Section("Tron Network") {
                if runtimeState.isPreparingTronSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Tron fee estimate...")
                            .font(.caption)
                    }
                } else if let tronSendPreview = store.tronSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: tronSendPreview.estimatedNetworkFeeTRX, symbol: "TRX") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f TRX (~%@)", tronSendPreview.estimatedNetworkFeeTRX, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f TRX", tronSendPreview.estimatedNetworkFeeTRX))
                            .font(.subheadline.weight(.semibold))
                    }
                    if selectedCoin.symbol == "USDT" {
                        Text("USDT on Tron uses TRX for network fees. Keep a TRX balance for gas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter an amount to load a Tron fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "XRP Ledger" {
            Section("XRP Ledger Network") {
                if runtimeState.isPreparingXRPSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading XRP fee estimate...")
                            .font(.caption)
                    }
                } else if let xrpSendPreview = store.xrpSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: xrpSendPreview.estimatedNetworkFeeXRP, symbol: "XRP") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f XRP (~%@)", xrpSendPreview.estimatedNetworkFeeXRP, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f XRP", xrpSendPreview.estimatedNetworkFeeXRP))
                            .font(.subheadline.weight(.semibold))
                    }
                    if xrpSendPreview.sequence > 0 {
                        Text(walletFlowLocalizedFormat("Sequence: %lld", xrpSendPreview.sequence))
                    }
                    if xrpSendPreview.lastLedgerSequence > 0 {
                        Text(walletFlowLocalizedFormat("Last Ledger Sequence: %lld", xrpSendPreview.lastLedgerSequence))
                    }
                } else {
                    Text("Enter an amount to load an XRP fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts XRP transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Cardano" {
            Section("Cardano Network") {
                if runtimeState.isPreparingCardanoSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Cardano fee estimate...")
                            .font(.caption)
                    }
                } else if let cardanoSendPreview = store.cardanoSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: cardanoSendPreview.estimatedNetworkFeeADA, symbol: "ADA") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f ADA (~%@)", cardanoSendPreview.estimatedNetworkFeeADA, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f ADA", cardanoSendPreview.estimatedNetworkFeeADA))
                            .font(.subheadline.weight(.semibold))
                    }
                    if cardanoSendPreview.ttlSlot > 0 {
                        Text(walletFlowLocalizedFormat("TTL Slot: %lld", cardanoSendPreview.ttlSlot))
                    }
                } else {
                    Text("Enter an amount to load a Cardano fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts ADA transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "NEAR" {
            Section("NEAR Network") {
                if runtimeState.isPreparingNearSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading NEAR fee estimate...")
                            .font(.caption)
                    }
                } else if let nearSendPreview = store.nearSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: nearSendPreview.estimatedNetworkFeeNEAR, symbol: "NEAR") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f NEAR (~%@)", nearSendPreview.estimatedNetworkFeeNEAR, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f NEAR", nearSendPreview.estimatedNetworkFeeNEAR))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a NEAR fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts NEAR transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Polkadot" {
            Section("Polkadot Network") {
                if runtimeState.isPreparingPolkadotSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Polkadot fee estimate...")
                            .font(.caption)
                    }
                } else if let polkadotSendPreview = store.polkadotSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: polkadotSendPreview.estimatedNetworkFeeDOT, symbol: "DOT") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f DOT (~%@)", polkadotSendPreview.estimatedNetworkFeeDOT, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.6f DOT", polkadotSendPreview.estimatedNetworkFeeDOT))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a Polkadot fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Polkadot transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Stellar" {
            Section("Stellar Network") {
                if runtimeState.isPreparingStellarSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Stellar fee estimate...")
                            .font(.caption)
                    }
                } else if let stellarSendPreview = store.stellarSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: stellarSendPreview.estimatedNetworkFeeXLM, symbol: "XLM") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.7f XLM (~%@)", stellarSendPreview.estimatedNetworkFeeXLM, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.7f XLM", stellarSendPreview.estimatedNetworkFeeXLM))
                            .font(.subheadline.weight(.semibold))
                    }
                    if stellarSendPreview.sequence > 0 {
                        Text(walletFlowLocalizedFormat("Sequence: %lld", stellarSendPreview.sequence))
                    }
                } else {
                    Text("Enter an amount to load a Stellar fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Stellar payments in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Internet Computer" {
            Section("Internet Computer Network") {
                if runtimeState.isPreparingICPSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading ICP fee estimate...")
                            .font(.caption)
                    }
                } else if let icpSendPreview = store.icpSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: icpSendPreview.estimatedNetworkFeeICP, symbol: "ICP") {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.8f ICP (~%@)", icpSendPreview.estimatedNetworkFeeICP, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Network Fee: %.8f ICP", icpSendPreview.estimatedNetworkFeeICP))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load an ICP fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts ICP transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Dogecoin" {
            Section("Dogecoin Send") {
                Picker("Fee Priority", selection: dogecoinFeePriorityBinding) {
                    Text("Economy").tag(DogecoinWalletEngine.FeePriority.economy)
                    Text("Normal").tag(DogecoinWalletEngine.FeePriority.normal)
                    Text("Priority").tag(DogecoinWalletEngine.FeePriority.priority)
                }
                .pickerStyle(.segmented)

                if runtimeState.isPreparingDogecoinSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading UTXOs and fee estimate...")
                            .font(.caption)
                    }
                } else if let dogecoinSendPreview = store.dogecoinSendPreview {
                    Text(walletFlowLocalizedFormat("Spendable Balance: %.6f DOGE", dogecoinSendPreview.spendableBalanceDOGE))
                    if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFeeDOGE, symbol: "DOGE") {
                        Text(walletFlowLocalizedFormat("Estimated Fee: %.6f DOGE (~%@)", dogecoinSendPreview.estimatedNetworkFeeDOGE, fiatFee))
                    } else {
                        Text(walletFlowLocalizedFormat("Estimated Fee: %.6f DOGE", dogecoinSendPreview.estimatedNetworkFeeDOGE))
                    }
                    Text(walletFlowLocalizedFormat("Fee Rate: %.4f DOGE/KB", dogecoinSendPreview.estimatedFeeRateDOGEPerKB))
                    Text(walletFlowLocalizedFormat("Estimated Size: %lld bytes", dogecoinSendPreview.estimatedTransactionBytes))
                    Text(walletFlowLocalizedFormat("Selected Inputs: %lld", dogecoinSendPreview.selectedInputCount))
                    Text(walletFlowLocalizedFormat("Change Output: %@", dogecoinSendPreview.usesChangeOutput ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No (dust-safe fee absorption)", comment: "")))
                    Text(walletFlowLocalizedFormat("Confirmation Preference: %@", confirmationPreferenceText(for: dogecoinSendPreview.feePriority)))
                    Text(walletFlowLocalizedFormat("Max Sendable: %.6f DOGE", dogecoinSendPreview.maxSendableDOGE))
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Enter an amount to load a live UTXO and fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Dogecoin in-app. The preview shows estimated network fee and max sendable DOGE for this wallet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        let selectedCoin = store.selectedSendCoin

        ZStack {
            SpectraBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    primarySendSections
                    if hasNetworkSendSections(for: selectedCoin) {
                        VStack(alignment: .leading, spacing: 18) {
                            networkSendSections(selectedCoin: selectedCoin)
                        }
                        .padding(18)
                        .spectraBubbleFill()
                        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                    }
                    sendStatusSections
                }
                .padding(20)
            }
            .navigationTitle("Send")
            .task(id: sendPreviewTaskID) {
                await store.refreshSendPreview()
            }
            .sheet(isPresented: $isShowingQRScanner) {
                SendQRScannerSheet { payload in
                    applyScannedRecipientPayload(payload)
                }
            }
            .alert("QR Scanner", isPresented: qrScannerAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                if let qrScannerErrorMessage {
                    Text(verbatim: qrScannerErrorMessage)
                }
            }
            .onChange(of: flowState.sendHoldingKey) { _, _ in
                selectedAddressBookEntryID = ""
            }
            .onChange(of: isSendBusy) { _, isBusy in
                guard isBusy, let snapshot = sendLiveActivitySnapshot else { return }
                Task {
                    await SendTransactionLiveActivityManager.shared.startSending(
                        walletName: snapshot.walletName,
                        chainName: snapshot.chainName,
                        symbol: snapshot.symbol,
                        amountText: snapshot.amountText,
                        destinationAddress: snapshot.destinationAddress
                    )
                }
            }
            .onChange(of: sendState.lastSentTransaction?.id) { _, _ in
                guard let transaction = sendState.lastSentTransaction,
                      transaction.kind == .send else { return }
                Task {
                    let walletName = transaction.walletID.flatMap { walletID in
                        store.wallet(for: walletID.uuidString)?.name
                    } ?? "Wallet"
                    await SendTransactionLiveActivityManager.shared.complete(
                        walletName: walletName,
                        transactionHash: transaction.transactionHash,
                        chainName: transaction.chainName,
                        symbol: transaction.symbol,
                        amountText: String(format: "%.8f", transaction.amount),
                        destinationAddress: transaction.address
                    )
                }
            }
            .onChange(of: flowState.sendError) { _, sendError in
                guard !isSendBusy,
                      let sendError,
                      !sendError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task {
                    await SendTransactionLiveActivityManager.shared.fail(message: sendError)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            await store.submitSend()
                        }
                    }
                    .disabled(isSendBusy)
                }
            }
            .alert("High-Risk Send", isPresented: store.isShowingHighRiskSendConfirmationBinding) {
                Button("Cancel", role: .cancel) {
                    store.clearHighRiskSendConfirmation()
                }
                Button("Send Anyway", role: .destructive) {
                    Task {
                        await store.confirmHighRiskSendAndSubmit()
                    }
                }
            } message: {
                Text(store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                     ? "This transfer has elevated risk."
                     : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• "))
            }
        }
    }

    @ViewBuilder
    private func sendDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(NSLocalizedString(title, comment: ""))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }

    private var qrScannerAlertBinding: Binding<Bool> {
        Binding(
            get: { qrScannerErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    qrScannerErrorMessage = nil
                }
            }
        )
    }

    private func applyScannedRecipientPayload(_ payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            qrScannerErrorMessage = "The scanned QR code did not contain a usable address."
            return
        }

        let selectedChainName = store.availableSendCoins(for: store.sendWalletID)
            .first(where: { $0.holdingKey == store.sendHoldingKey })?
            .chainName

        guard let resolvedAddress = resolvedRecipientAddress(from: trimmedPayload, chainName: selectedChainName) else {
            qrScannerErrorMessage = "The scanned QR code does not contain a valid address for the selected asset."
            return
        }

        store.sendAddress = resolvedAddress
        qrScannerErrorMessage = nil
    }

    private func resolvedRecipientAddress(from payload: String, chainName: String?) -> String? {
        let candidates = qrAddressCandidates(from: payload)
        guard let chainName else {
            return candidates.first
        }

        for candidate in candidates {
            if isValidScannedAddress(candidate, for: chainName) {
                if chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid" {
                    return EthereumWalletEngine.normalizeAddress(candidate)
                }
                return candidate
            }
        }
        return nil
    }

    private func qrAddressCandidates(from payload: String) -> [String] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [String] = []

        func appendCandidate(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        appendCandidate(trimmed)

        let withoutQuery = trimmed.components(separatedBy: "?").first ?? trimmed
        appendCandidate(withoutQuery)

        if let colonIndex = withoutQuery.firstIndex(of: ":") {
            let suffix = String(withoutQuery[withoutQuery.index(after: colonIndex)...])
            appendCandidate(suffix)
        }

        if let components = URLComponents(string: trimmed) {
            if let host = components.host {
                appendCandidate(host + components.path)
            }
            if let firstPathComponent = components.path.split(separator: "/").first {
                appendCandidate(String(firstPathComponent))
            }
        }

        return candidates
    }

    private func isValidScannedAddress(_ address: String, for chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin":
            return AddressValidation.isValidBitcoinAddress(address, networkMode: store.bitcoinNetworkMode)
        case "Bitcoin Cash":
            return AddressValidation.isValidBitcoinCashAddress(address)
        case "Bitcoin SV":
            return AddressValidation.isValidBitcoinSVAddress(address)
        case "Litecoin":
            return AddressValidation.isValidLitecoinAddress(address)
        case "Dogecoin":
            return AddressValidation.isValidDogecoinAddress(address, allowTestnet: store.dogecoinAllowTestnet)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return AddressValidation.isValidEthereumAddress(address)
        case "Tron":
            return AddressValidation.isValidTronAddress(address)
        case "Solana":
            return AddressValidation.isValidSolanaAddress(address)
        case "Cardano":
            return AddressValidation.isValidCardanoAddress(address)
        case "XRP Ledger":
            return AddressValidation.isValidXRPAddress(address)
        case "Monero":
            return AddressValidation.isValidMoneroAddress(address)
        case "Sui":
            return AddressValidation.isValidSuiAddress(address)
        case "Aptos":
            return AddressValidation.isValidAptosAddress(address)
        case "TON":
            return AddressValidation.isValidTONAddress(address)
        case "Internet Computer":
            return AddressValidation.isValidICPAddress(address)
        case "NEAR":
            return AddressValidation.isValidNearAddress(address)
        default:
            return false
        }
    }

    private func confirmationPreferenceText(for priority: DogecoinWalletEngine.FeePriority) -> String {
        switch priority {
        case .economy:
            return "Economy (cost-optimized)"
        case .normal:
            return "Normal (balanced)"
        case .priority:
            return "Priority (faster confirmation bias)"
        }
    }
}
