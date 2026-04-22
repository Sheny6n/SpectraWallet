import Foundation
import SwiftUI
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
