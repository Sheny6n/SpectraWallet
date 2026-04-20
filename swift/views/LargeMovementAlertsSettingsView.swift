import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
