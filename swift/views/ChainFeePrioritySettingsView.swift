import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
