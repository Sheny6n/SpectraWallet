import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import VisionKit

func localizedWalletFlowString(_ key: String) -> String {
    AppLocalization.string(key)
}

struct TransactionStatusBadge: View {
    let status: TransactionStatus

    private var statusText: String {
        status.rawValue.capitalized
    }

    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .confirmed:
            return .mint
        case .failed:
            return .red
        }
    }

    private var badgeScale: CGFloat {
        switch status {
        case .pending:
            return 1.0
        case .confirmed:
            return 1.05
        case .failed:
            return 0.97
        }
    }

    var body: some View {
        Text(statusText.uppercased())
            .font(.caption2.bold())
            .tracking(0.6)
            .frame(minWidth: 86)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.16), in: Capsule())
            .foregroundStyle(statusColor)
            .scaleEffect(badgeScale)
            .animation(.spring(response: 0.35, dampingFraction: 0.74), value: status)
    }
}

struct SendQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            QRCodeScannerView { payload in
                onScan(payload)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasResolvedPayload = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            resolve(item, from: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let firstItem = addedItems.first else { return }
            resolve(firstItem, from: dataScanner)
        }

        private func resolve(_ item: RecognizedItem, from dataScanner: DataScannerViewController) {
            guard !hasResolvedPayload else { return }
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty else {
                return
            }
            hasResolvedPayload = true
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
}

struct WalletCardView: View {
    @ObservedObject var store: WalletStore
    let wallet: ImportedWallet

    private var isWatchOnly: Bool {
        store.isWatchOnlyWallet(wallet)
    }

    private var isPrivateKeyWallet: Bool {
        store.isPrivateKeyWallet(wallet)
    }

    private var nonZeroAssetCount: Int {
        wallet.holdings.filter { $0.amount > 0 }.count
    }

    private var walletBadge: (assetIdentifier: String?, mark: String, color: Color) {
        Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, "W", .mint)
    }

    private var watchOnlyBadge: some View {
        Image(systemName: "eye")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CoinBadge(assetIdentifier: walletBadge.assetIdentifier, fallbackText: walletBadge.mark, color: walletBadge.color, size: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isWatchOnly {
                            watchOnlyBadge
                        }
                        Text(wallet.name)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                    }
                    Text(wallet.selectedChain)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: wallet)))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .spectraNumericTextLayout()
                    Text(walletFlowLocalizedFormat("%lld assets", nonZeroAssetCount))
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.68))
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}

struct QRCodeRenderer {
    static func makeImage(from string: String, scale: CGFloat = 12) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

struct ActivityItemSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class PhotoLibraryImageSaver: NSObject {
    private let completion: (Result<Void, Error>) -> Void

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc
    private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }
}

struct DonationQRCodeView: View {
    let donation: DonationDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop()

                VStack(spacing: 24) {
                    CoinBadge(
                        assetIdentifier: donation.assetIdentifier,
                        fallbackText: donation.mark,
                        color: donation.color,
                        size: 54
                    )

                    Text(localizedWalletFlowString("Scan to Donate"))
                        .font(.title2.bold())
                        .foregroundStyle(Color.primary)

                    Text(donation.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary.opacity(0.76))

                    QRCodeImage(address: donation.address)
                        .frame(width: 220, height: 220)
                        .padding(18)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    Text(donation.address)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 24)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(localizedWalletFlowString("QR Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizedWalletFlowString("Done")) {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

struct QRCodeImage: View {
    let address: String

    var body: some View {
        Group {
            if let image = qrUIImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .foregroundStyle(.black)
            }
        }
    }

    private var qrUIImage: UIImage? {
        QRCodeRenderer.makeImage(from: address)
    }
}

struct WalletDetailView: View {
    @ObservedObject var store: WalletStore
    let wallet: ImportedWallet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSeedPhrasePasswordPrompt: Bool = false
    @State private var isShowingSeedPhraseSheet: Bool = false
    @State private var seedPhrasePasswordInput: String = ""
    @State private var revealedSeedPhrase: String = ""
    @State private var seedPhraseErrorMessage: String?
    @State private var isRevealingSeedPhrase: Bool = false
    @State private var didCopyWalletAddress: Bool = false
    @State private var isShowingDeleteWalletAlert: Bool = false

    private var isWatchOnly: Bool {
        store.isWatchOnlyWallet(displayedWallet)
    }

    private var isPrivateKeyWallet: Bool {
        store.isPrivateKeyWallet(displayedWallet)
    }

    private var requiresSeedPhrasePassword: Bool {
        store.walletRequiresSeedPhrasePassword(displayedWallet.id)
    }

    private var displayedWallet: ImportedWallet {
        store.wallets.first(where: { $0.id == wallet.id }) ?? wallet
    }

    private var firstActivityDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        guard let firstDate = store.transactions
            .filter({ $0.walletID == wallet.id })
            .map(\.createdAt)
            .min() else {
            return NSLocalizedString("No activity yet", comment: "")
        }
        return formatter.string(from: firstDate)
    }

    private var nonZeroAssetCount: Int {
        displayedWallet.holdings.filter { $0.amount > 0 }.count
    }

    private var walletAddress: String? {
        [
            displayedWallet.bitcoinAddress,
            displayedWallet.bitcoinCashAddress,
            displayedWallet.litecoinAddress,
            displayedWallet.dogecoinAddress,
            displayedWallet.ethereumAddress,
            displayedWallet.tronAddress,
            displayedWallet.solanaAddress,
            displayedWallet.xrpAddress,
            displayedWallet.moneroAddress,
            displayedWallet.cardanoAddress,
            displayedWallet.suiAddress,
            displayedWallet.aptosAddress,
            displayedWallet.tonAddress,
            displayedWallet.nearAddress,
            displayedWallet.polkadotAddress,
            displayedWallet.stellarAddress,
        ]
        .compactMap { $0 }
        .first
    }

    private var derivationPathsText: String? {
        guard !isWatchOnly, !isPrivateKeyWallet else { return nil }

        let chainMappings: [(String, SeedDerivationChain)] = [
            ("Bitcoin", .bitcoin),
            ("Bitcoin Cash", .bitcoinCash),
            ("Bitcoin SV", .bitcoinSV),
            ("Litecoin", .litecoin),
            ("Dogecoin", .dogecoin),
            ("Ethereum", .ethereum),
            ("Ethereum Classic", .ethereumClassic),
            ("Arbitrum", .arbitrum),
            ("Optimism", .optimism),
            ("BNB Chain", .ethereum),
            ("Avalanche", .avalanche),
            ("Hyperliquid", .hyperliquid),
            ("Tron", .tron),
            ("Solana", .solana),
            ("Cardano", .cardano),
            ("XRP Ledger", .xrp),
            ("Sui", .sui),
            ("Aptos", .aptos),
            ("TON", .ton),
            ("Internet Computer", .internetComputer),
            ("NEAR", .near),
            ("Polkadot", .polkadot),
            ("Stellar", .stellar),
        ]

        guard let derivationChain = chainMappings.first(where: { $0.0 == displayedWallet.selectedChain })?.1 else {
            return nil
        }
        return walletFlowLocalizedFormat("wallet.detail.chainPath", displayedWallet.selectedChain, displayedWallet.seedDerivationPaths.path(for: derivationChain))
    }

    private var walletBadge: (assetIdentifier: String?, mark: String, color: Color) {
        Coin.nativeChainBadge(chainName: displayedWallet.selectedChain) ?? (nil, "W", .mint)
    }

    private var visibleHoldings: [Coin] {
        displayedWallet.holdings
            .filter { $0.amount > 0 }
            .sorted {
                let lhsValue = store.currentValueIfAvailable(for: $0) ?? -1
                let rhsValue = store.currentValueIfAvailable(for: $1) ?? -1
                if abs(lhsValue - rhsValue) > 0.000001 {
                    return lhsValue > rhsValue
                }
                return $0.symbol.localizedCaseInsensitiveCompare($1.symbol) == .orderedAscending
            }
    }

    private var watchOnlyBadge: some View {
        Label(NSLocalizedString("Watching", comment: ""), systemImage: "eye")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    private var deleteWalletMessage: String {
        if isWatchOnly {
            return NSLocalizedString("You can't recover this wallet after deletion until you still have this address.", comment: "")
        }
        if isPrivateKeyWallet {
            return NSLocalizedString("Please keep this private key because you can't recover this wallet after deletion.", comment: "")
        }
        return NSLocalizedString("Please take note of your seed phrase because you can't recover this wallet after deletion.", comment: "")
    }

    private func clearSeedRevealState() {
        isShowingSeedPhrasePasswordPrompt = false
        isShowingSeedPhraseSheet = false
        seedPhrasePasswordInput = ""
        revealedSeedPhrase = ""
        seedPhraseErrorMessage = nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    CoinBadge(
                        assetIdentifier: walletBadge.assetIdentifier,
                        fallbackText: walletBadge.mark,
                        color: walletBadge.color,
                        size: 46
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(displayedWallet.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.primary)

                            Spacer(minLength: 0)

                            if isWatchOnly {
                                watchOnlyBadge
                            }
                        }
                        Text(displayedWallet.selectedChain)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .spectraBubbleFill()
                .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Mode", value: isWatchOnly ? "Watch Addresses" : (isPrivateKeyWallet ? "Private Key" : "Seed-Based"))
                    if let derivationPathsText {
                        detailRow(label: "Derivation Paths", value: derivationPathsText)
                    }
                    detailRow(label: "Current Value", value: store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: displayedWallet)))
                    detailRow(label: "Asset Count", value: "\(nonZeroAssetCount)")
                    detailRow(label: "First Activity", value: firstActivityDateText)
                    detailRow(label: "Wallet ID", value: displayedWallet.id.uuidString)
                }
                .padding(16)
                .spectraBubbleFill()
                .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Holdings")
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(visibleHoldings.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.68))
                    }

                    if visibleHoldings.isEmpty {
                        Text("No assets loaded for this wallet yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.72))
                    } else {
                        ForEach(visibleHoldings) { holding in
                            HStack(spacing: 12) {
                                CoinBadge(
                                    assetIdentifier: holding.iconIdentifier,
                                    fallbackText: holding.mark,
                                    color: holding.color,
                                    size: 34
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(holding.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primary)
                                    Text("\(holding.symbol) • \(holding.tokenStandard)")
                                        .font(.caption)
                                        .foregroundStyle(Color.primary.opacity(0.62))
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(store.formattedAssetAmount(holding.amount, symbol: holding.symbol, chainName: holding.chainName))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primary)
                                        .spectraNumericTextLayout()
                                    Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentValueIfAvailable(for: holding)))
                                        .font(.caption)
                                        .foregroundStyle(Color.primary.opacity(0.68))
                                        .spectraNumericTextLayout()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(16)
                .spectraBubbleFill()
                .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))

                if let walletAddress {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Wallet Address")
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = walletAddress
                                didCopyWalletAddress = true
                            } label: {
                                Label(didCopyWalletAddress ? "Copied" : "Copy", systemImage: didCopyWalletAddress ? "checkmark" : "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.primary)
                        }

                        Text(walletAddress)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .spectraBubbleFill()
                    .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.beginEditingWallet(wallet)
                        }
                    } label: {
                        Label("Edit Wallet", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    if !isWatchOnly && !isPrivateKeyWallet {
                        Button {
                            if requiresSeedPhrasePassword {
                                seedPhrasePasswordInput = ""
                                isShowingSeedPhrasePasswordPrompt = true
                            } else {
                                Task {
                                    await revealSeedPhrase()
                                }
                            }
                        } label: {
                            Label(
                                isRevealingSeedPhrase
                                    ? "Checking Face ID..."
                                    : (requiresSeedPhrasePassword ? "Show Seed Phrase (Password)" : "Show Seed Phrase"),
                                systemImage: requiresSeedPhrasePassword ? "lock.shield" : "faceid"
                            )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glass)
                        .disabled(isRevealingSeedPhrase || !store.canRevealSeedPhrase(for: wallet.id))
                    }

                    Button(role: .destructive) {
                        isShowingDeleteWalletAlert = true
                    } label: {
                        Label("Delete Wallet", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(SpectraBackdrop())
        .navigationTitle("Wallet Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { store.isShowingWalletImporter && store.editingWalletID == wallet.id },
            set: { isPresented in
                if !isPresented {
                    store.isShowingWalletImporter = false
                }
            }
        )) {
            SetupView(store: store, draft: store.importDraft)
        }
        .alert("Delete Wallet?", isPresented: $isShowingDeleteWalletAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    store.confirmDeleteWallet(wallet)
                    await store.deletePendingWallet()
                }
            }
            Button("Cancel", role: .cancel) {
                isShowingDeleteWalletAlert = false
            }
        } message: {
            Text(deleteWalletMessage)
        }
        .alert("Cannot Reveal Seed Phrase", isPresented: Binding(
            get: { seedPhraseErrorMessage != nil },
            set: { isPresented in
                if !isPresented { seedPhraseErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(seedPhraseErrorMessage ?? "Unknown error")
        }
        .onChange(of: wallet.id) { _, _ in
            didCopyWalletAddress = false
        }
        .onChange(of: store.wallets.contains(where: { $0.id == wallet.id })) { _, walletStillExists in
            guard !walletStillExists else { return }
            isShowingDeleteWalletAlert = false
            clearSeedRevealState()
            dismiss()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            clearSeedRevealState()
        }
        .sheet(isPresented: $isShowingSeedPhrasePasswordPrompt, onDismiss: {
            seedPhrasePasswordInput = ""
        }) {
            NavigationStack {
                ZStack {
                    SpectraBackdrop()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("This wallet has an optional seed phrase password. Enter it after Face ID to reveal the recovery phrase.")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.76))

                        SecureField("Wallet Password", text: $seedPhrasePasswordInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .privacySensitive()
                            .padding(14)
                            .spectraInputFieldStyle()
                            .foregroundStyle(Color.primary)

                        Button {
                            isShowingSeedPhrasePasswordPrompt = false
                            Task {
                                await revealSeedPhrase(password: seedPhrasePasswordInput)
                            }
                        } label: {
                            Text("Reveal Seed Phrase")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(seedPhrasePasswordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()
                    }
                    .padding(20)
                }
                .navigationTitle("Wallet Password")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            isShowingSeedPhrasePasswordPrompt = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSeedPhraseSheet, onDismiss: {
            revealedSeedPhrase = ""
        }) {
            NavigationStack {
                ZStack {
                    SpectraBackdrop()

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Write this down and keep it offline. Anyone with this phrase can control your funds.")
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.76))

                            Text(revealedSeedPhrase)
                                .font(.body.monospaced())
                                .foregroundStyle(Color.primary)
                                .privacySensitive()
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .spectraInputFieldStyle(cornerRadius: 16)
                        }
                        .padding(16)
                        .spectraBubbleFill()
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
                        .padding(20)
                    }
                }
                .navigationTitle("Seed Phrase")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingSeedPhraseSheet = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString(label, comment: ""))
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.65))
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealSeedPhrase(password: String? = nil) async {
        guard !isRevealingSeedPhrase else { return }
        isRevealingSeedPhrase = true
        defer { isRevealingSeedPhrase = false }

        do {
            let phrase = try await store.revealSeedPhrase(for: wallet, password: password)
            revealedSeedPhrase = phrase
            seedPhrasePasswordInput = ""
            isShowingSeedPhraseSheet = true
        } catch {
            seedPhraseErrorMessage = error.localizedDescription
        }
    }
}

func walletFlowLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}

struct SeedPathSlotEditor: View {
    let title: String
    @Binding var path: String
    let defaultPath: String

    private var segments: [DerivationPathSegment] {
        DerivationPathParser.parse(path) ?? DerivationPathParser.parse(defaultPath) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizedWalletFlowString(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Button("Reset") {
                    path = defaultPath
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("m")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.72))

                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        HStack(spacing: 4) {
                            Text(verbatim: "/")
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.primary.opacity(0.52))
                            TextField(
                                "0",
                                text: Binding(
                                    get: { String(segment.value) },
                                    set: { updateSegment(at: index, value: $0) }
                                )
                            )
                            .keyboardType(.numberPad)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .spectraInputFieldStyle(cornerRadius: 12)

                            if segment.isHardened {
                                Text(verbatim: "'")
                                    .font(.caption.monospaced().weight(.bold))
                                    .foregroundStyle(Color.primary.opacity(0.72))
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateSegment(at index: Int, value: String) {
        guard var resolvedSegments = DerivationPathParser.parse(path) ?? DerivationPathParser.parse(defaultPath),
              resolvedSegments.indices.contains(index),
              let numericValue = UInt32(value.filter(\.isNumber)) else { return }
        resolvedSegments[index].value = numericValue
        path = DerivationPathParser.string(from: resolvedSegments)
    }
}

struct AssetRowView: View {
    @ObservedObject var store: WalletStore
    let coin: Coin
    
    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: coin.iconIdentifier,
                fallbackText: coin.mark,
                color: coin.color,
                size: 46
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(coin.name)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(store.formattedAssetAmount(coin.amount, symbol: coin.symbol, chainName: coin.chainName))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .spectraNumericTextLayout()
                Text(walletFlowLocalizedFormat("wallet.detail.onChainLowercase", coin.chainName))
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.6))
                Text(coin.tokenStandard)
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.55))
                if let contractAddress = coin.contractAddress {
                    Text(contractAddress)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentValueIfAvailable(for: coin)))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .spectraNumericTextLayout()
                Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentPriceIfAvailable(for: coin)))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .spectraNumericTextLayout()
            }
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}
