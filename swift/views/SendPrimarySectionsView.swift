import Foundation
import SwiftUI
import VisionKit

struct SendPrimarySectionsView: View {
    @Bindable var store: AppState
    @Binding var selectedAddressBookEntryID: String
    @Binding var isShowingQRScanner: Bool
    @Binding var qrScannerErrorMessage: String?

    private struct Presentation {
        let sendWallets: [ImportedWallet]
        let selectedWallet: ImportedWallet?
        let availableSendCoins: [Coin]
        let selectedCoin: Coin?
        let selectedCoinAmountText: String?
        let selectedCoinApproximateFiatText: String?
        let addressBookEntries: [AddressBookEntry]
    }

    private var presentation: Presentation {
        let sendWallets = store.sendEnabledWallets
        let selectedWallet = sendWallets.first(where: { $0.id == store.sendWalletID })
        let availableSendCoins = store.availableSendCoins(for: store.sendWalletID)
        let selectedCoin = availableSendCoins.first(where: { $0.holdingKey == store.sendHoldingKey })
        let selectedCoinAmountText = selectedCoin.map { store.formattedAssetAmount($0.amount, symbol: $0.symbol, chainName: $0.chainName) }
        let sendAmount = Double(store.sendAmount) ?? 0
        let selectedCoinApproximateFiatText: String?
        if let selectedCoin, !sendAmount.isZero {
            selectedCoinApproximateFiatText = store.formattedFiatAmount(fromNative: sendAmount, symbol: selectedCoin.symbol)
        } else {
            selectedCoinApproximateFiatText = nil
        }
        return Presentation(
            sendWallets: sendWallets, selectedWallet: selectedWallet, availableSendCoins: availableSendCoins,
            selectedCoin: selectedCoin, selectedCoinAmountText: selectedCoinAmountText,
            selectedCoinApproximateFiatText: selectedCoinApproximateFiatText,
            addressBookEntries: store.sendAddressBookEntries
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            fromCard
            toCard
            amountCard
        }
    }

    // MARK: — From card (wallet + asset picker)

    private var fromCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppLocalization.string("From")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if presentation.sendWallets.count > 1 {
                    Picker("", selection: $store.sendWalletID) {
                        ForEach(presentation.sendWallets) { wallet in Text(wallet.name).tag(wallet.id) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: store.sendWalletID) { _, _ in store.syncSendAssetSelection() }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if let selectedWallet = presentation.selectedWallet {
                let badge = Coin.nativeChainBadge(chainName: selectedWallet.selectedChain) ?? (nil, Color.mint)
                HStack(spacing: 10) {
                    CoinBadge(
                        assetIdentifier: badge.assetIdentifier,
                        fallbackText: selectedWallet.selectedChain,
                        color: badge.color,
                        size: 32
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedWallet.name).font(.subheadline.weight(.semibold))
                        Text(selectedWallet.selectedChain).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if !presentation.availableSendCoins.isEmpty {
                Divider().opacity(0.3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presentation.availableSendCoins, id: \.holdingKey) { coin in
                            coinChip(coin: coin, isSelected: coin.holdingKey == store.sendHoldingKey)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 24))
    }

    private func coinChip(coin: Coin, isSelected: Bool) -> some View {
        Button {
            guard !isSelected else { return }
            store.sendHoldingKey = coin.holdingKey
            spectraHaptic(.light)
        } label: {
            HStack(spacing: 8) {
                CoinBadge(
                    assetIdentifier: coin.iconIdentifier,
                    fallbackText: coin.symbol,
                    color: coin.color,
                    size: 26
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(coin.symbol).font(.subheadline.weight(.semibold))
                    Text(store.formattedAssetAmount(coin.amount, symbol: coin.symbol, chainName: coin.chainName))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .spectraNumericTextLayout()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? coin.color.opacity(0.18)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? coin.color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: — To card (recipient address)

    private var toCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("To")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: 10) {
                TextField(AppLocalization.string("Recipient address"), text: $store.sendAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 14))

                Button {
                    guard DataScannerViewController.isSupported else {
                        qrScannerErrorMessage = AppLocalization.string("QR scanning is not supported on this device.")
                        return
                    }
                    guard DataScannerViewController.isAvailable else {
                        qrScannerErrorMessage = AppLocalization.string(
                            "QR scanning is unavailable right now. Check camera permission and try again.")
                        return
                    }
                    isShowingQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(AppLocalization.string("Scan QR Code"))
            }

            if !presentation.addressBookEntries.isEmpty {
                Picker(AppLocalization.string("Saved Recipient"), selection: $selectedAddressBookEntryID) {
                    Text(AppLocalization.string("None")).tag("")
                    ForEach(presentation.addressBookEntries) { entry in
                        Text("\(entry.name) · \(entry.chainName)").tag(entry.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .font(.subheadline)
                .onChange(of: selectedAddressBookEntryID) { _, newValue in
                    guard let entry = presentation.addressBookEntries.first(where: { $0.id.uuidString == newValue }) else { return }
                    store.sendAddress = entry.address
                }
            }

            if let qrScannerErrorMessage {
                Label(qrScannerErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            if presentation.selectedCoin?.chainName == "Litecoin",
               store.sendAddress.hasPrefix("ltcmweb1") || store.sendAddress.hasPrefix("tmweb1") {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill").font(.caption2.weight(.semibold))
                    Text("MWEB · Privacy Send").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing).opacity(0.9)
                )
                .clipShape(.capsule)
            }

            if store.isCheckingSendDestinationBalance {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(AppLocalization.string("Checking destination on-chain balance..."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let warning = store.sendDestinationRiskWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            if let info = store.sendDestinationInfoMessage {
                Text(info).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 24))
    }

    // MARK: — Amount card

    private var amountCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                TextField("0", text: $store.sendAmount)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .spectraNumericTextLayout()
                    .frame(maxWidth: .infinity)

                if let selectedCoin = presentation.selectedCoin {
                    Text(selectedCoin.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selectedCoin.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(selectedCoin.color)
                }
            }

            if let fiatText = presentation.selectedCoinApproximateFiatText {
                Text("≈ \(fiatText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .spectraNumericTextLayout()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider().opacity(0.3)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Available")).font(.caption).foregroundStyle(.secondary)
                    if let amountText = presentation.selectedCoinAmountText {
                        Text(amountText)
                            .font(.subheadline.weight(.semibold))
                            .spectraNumericTextLayout()
                    }
                }
                Spacer()
                if let selectedCoin = presentation.selectedCoin, selectedCoin.amount > 0 {
                    HStack(spacing: 6) {
                        ForEach([0.1, 0.5, 1.0], id: \.self) { fraction in
                            percentButton(fraction: fraction, coin: selectedCoin)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 24))
    }

    private func percentButton(fraction: Double, coin: Coin) -> some View {
        let label = fraction == 1.0 ? "MAX" : "\(Int(fraction * 100))%"
        let isActive: Bool = {
            guard let current = Double(store.sendAmount), coin.amount > 0 else { return false }
            return abs(current - coin.amount * fraction) < 1e-12
        }()
        return Button {
            let value = coin.amount * fraction
            store.sendAmount = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(value)
            spectraHaptic(.light)
        } label: {
            Text(label)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    isActive ? coin.color.opacity(0.28) : Color.primary.opacity(0.08),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? coin.color : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
