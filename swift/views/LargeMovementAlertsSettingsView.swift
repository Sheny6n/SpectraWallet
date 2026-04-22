import Foundation
import SwiftUI
struct LargeMovementAlertsSettingsView: View {
    @Bindable var store: AppState
    var body: some View {
        @Bindable var preferences = store.preferences
        return Form {
            Section(AppLocalization.string("Notifications")) {
                Toggle(isOn: $preferences.useLargeMovementNotifications) {
                    Label(AppLocalization.string("Large Portfolio Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                }
                Text(
                    preferences.useLargeMovementNotifications
                        ? AppLocalization.string(
                            "Spectra can notify you when your total portfolio moves beyond your configured thresholds.")
                        : AppLocalization.string("Large movement notifications are currently off.")
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Alert Controls")) {
                Stepper(
                    String(
                        format: AppLocalization.string("Large movement threshold: %@"),
                        (preferences.largeMovementAlertPercentThreshold / 100).formatted(.percent.precision(.fractionLength(0)))
                    ),
                    value: Binding(
                        get: { preferences.largeMovementAlertPercentThreshold }, set: { preferences.largeMovementAlertPercentThreshold = $0 }
                    ), in: 1...90, step: 1
                ).disabled(!preferences.useLargeMovementNotifications)
                Stepper(
                    AppLocalization.format("Large movement minimum: %lld USD", Int(preferences.largeMovementAlertUSDThreshold)),
                    value: Binding(
                        get: { preferences.largeMovementAlertUSDThreshold }, set: { preferences.largeMovementAlertUSDThreshold = $0 }
                    ), in: 1...100_000, step: 5
                ).disabled(!preferences.useLargeMovementNotifications)
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
