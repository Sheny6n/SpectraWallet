import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
