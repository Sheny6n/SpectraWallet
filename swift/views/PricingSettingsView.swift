import Foundation
import SwiftUI
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
            Section(AppLocalization.string("Provider Notes")) {
                Text(copy.publicProviderNote).font(.caption).foregroundStyle(.secondary)
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
