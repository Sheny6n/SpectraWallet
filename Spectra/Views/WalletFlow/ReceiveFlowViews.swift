import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import VisionKit


struct ReceiveView: View {
    @ObservedObject var store: WalletStore
    @State private var didCopyReceiveAddress: Bool = false
    @State private var isShowingReceiveQRShareSheet: Bool = false
    @State private var receiveQRExportMessage: String?
    @State private var receiveQRImageSaver: PhotoLibraryImageSaver?
    
    var body: some View {
        let resolvedReceiveAddress = store.receiveAddress()
        let canUseReceiveAddress = !resolvedReceiveAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ZStack {
            SpectraBackdrop()

            Form {
                Section("Wallet") {
                    Picker("Wallet", selection: store.receiveWalletIDBinding) {
                        ForEach(store.receiveEnabledWallets) { wallet in
                            Text(wallet.name).tag(wallet.id.uuidString)
                        }
                    }
                    .onChange(of: store.receiveWalletID) { _, _ in
                        store.syncReceiveAssetSelection()
                    }
                }
                receiveAddressSections
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Receive")
            .task(id: store.receiveWalletID) {
                await store.refreshReceiveAddress()
            }
            .sheet(isPresented: $isShowingReceiveQRShareSheet) {
                if let receiveQRImage = QRCodeRenderer.makeImage(from: store.receiveAddress()) {
                    ActivityItemSheet(activityItems: [receiveQRImage])
                }
            }
            .alert("QR Code Export", isPresented: Binding(
                get: { receiveQRExportMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        receiveQRExportMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    receiveQRExportMessage = nil
                }
            } message: {
                if let receiveQRExportMessage {
                    Text(verbatim: receiveQRExportMessage)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = resolvedReceiveAddress
                        didCopyReceiveAddress = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            didCopyReceiveAddress = false
                        }
                    } label: {
                        Label("Copy", systemImage: didCopyReceiveAddress ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(!canUseReceiveAddress || store.isResolvingReceiveAddress)
                }
            }
        }
    }

    @ViewBuilder
    private var receiveAddressSections: some View {
        let resolvedReceiveAddress = store.receiveAddress()
        let canUseReceiveAddress = !resolvedReceiveAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let receiveQRImage = QRCodeRenderer.makeImage(from: resolvedReceiveAddress)
        Section("QR Code") {
            VStack(alignment: .center, spacing: 12) {
                if canUseReceiveAddress {
                    QRCodeImage(address: resolvedReceiveAddress)
                        .frame(width: 184, height: 184)
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text("Scan to receive")
                        .font(.headline)
                    Text("Share this QR code or copy the address below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        guard let receiveQRImage else { return }
                        let saver = PhotoLibraryImageSaver { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    receiveQRExportMessage = "QR code saved to Photos."
                                case .failure(let error):
                                    receiveQRExportMessage = error.localizedDescription
                                }
                                receiveQRImageSaver = nil
                            }
                        }
                        receiveQRImageSaver = saver
                        saver.save(receiveQRImage)
                    } label: {
                        Label("Save QR Code", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .disabled(receiveQRImage == nil)
                } else {
                    ProgressView()
                    Text("Preparing receive address...")
                        .font(.headline)
                    Text("Spectra is resolving the current address for this wallet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }

        Section("Address") {
            Text(resolvedReceiveAddress)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if didCopyReceiveAddress {
                Label("Address copied to clipboard.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }

        if let receiveCoin = store.selectedReceiveCoin(for: store.receiveWalletID) {
            Section("Asset Details") {
                HStack(spacing: 12) {
                    CoinBadge(
                        assetIdentifier: receiveCoin.iconIdentifier,
                        fallbackText: receiveCoin.mark,
                        color: receiveCoin.color,
                        size: 34
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(receiveCoin.name)
                            .font(.headline)
                        Text(receiveCoin.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                LabeledContent("Network", value: receiveCoin.chainName)
                LabeledContent("Standard", value: receiveCoin.tokenStandard)
                let chainAssets = store.availableReceiveCoins(for: store.receiveWalletID)
                    .filter { $0.chainName == receiveCoin.chainName }
                if chainAssets.count > 1 {
                    let chainSymbols = Array(Set(chainAssets.map(\.symbol))).sorted().joined(separator: ", ")
                    LabeledContent("Also Receives") {
                        Text(chainSymbols)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let contractAddress = receiveCoin.contractAddress {
                    LabeledContent("Contract") {
                        Text(contractAddress)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
