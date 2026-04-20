import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
    @Bindable private var preferences = TokenIconPreferences.shared
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
                    preferences.resetAll()
                    TokenIconImageRevision.shared.bump()
                }.disabled(preferences.isEmpty)
            }
        }
    }
}
