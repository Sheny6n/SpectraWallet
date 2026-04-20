import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct BackgroundSyncSettingsView: View {
    @Bindable var store: AppState
    var body: some View {
        Form {
            Section(AppLocalization.string("Refresh Frequency")) {
                Text(AppLocalization.string("Choose how often Spectra refreshes balances automatically while the app is active.")).font(
                    .caption
                ).foregroundStyle(.secondary)
                Stepper(
                    value: $store.automaticRefreshFrequencyMinutes,
                    in: 5...60, step: 5
                ) {
                    LabeledContent(AppLocalization.string("Active app refresh"), value: "\(store.automaticRefreshFrequencyMinutes) min")
                }
            }
            Section(AppLocalization.string("Current Timing")) {
                LabeledContent(
                    AppLocalization.string("Active app balance refresh"), value: "\(store.automaticRefreshFrequencyMinutes) min")
                LabeledContent(
                    AppLocalization.string("Background balance refresh"), value: "\(store.backgroundBalanceRefreshFrequencyMinutes) min")
            }
            Section(AppLocalization.string("Hint")) {
                Label(
                    AppLocalization.string("Lower refresh times can increase battery usage and network traffic."),
                    systemImage: "bolt.batteryblock.fill"
                ).foregroundStyle(.orange)
                Text(AppLocalization.string("Choose a longer interval if you want lower background activity and less battery impact."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isTooFrequent(store.automaticRefreshFrequencyMinutes) {
                Section(AppLocalization.string("Warning")) {
                    Label(
                        AppLocalization.string("This refresh speed can increase battery usage and network traffic."),
                        systemImage: "exclamationmark.triangle.fill"
                    ).foregroundStyle(.orange)
                    Text(AppLocalization.string("Use this mode only if you need near-real-time updates.")).font(.caption).foregroundStyle(
                        .secondary)
                }
            }
        }.navigationTitle(AppLocalization.string("Background Sync"))
    }
    private func isTooFrequent(_ minutes: Int) -> Bool { minutes <= 10 }
}
