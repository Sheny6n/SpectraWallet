import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct MainTabView: View {
    @Bindable var store: AppState
    var body: some View {
        TabView(selection: $store.selectedMainTab) {
            DashboardView(store: store).tabItem {
                Label(AppLocalization.string("Home"), systemImage: "chart.pie.fill")
            }.tag(MainAppTab.home)
            HistoryView(store: store).tabItem {
                Label(AppLocalization.string("History"), systemImage: "clock.arrow.circlepath")
            }.tag(MainAppTab.history)
            StakingView().tabItem {
                Label(AppLocalization.string("Staking"), systemImage: "link.circle.fill")
            }.tag(MainAppTab.staking)
            DonationsView().tabItem {
                Label(AppLocalization.string("Donate"), systemImage: "heart.fill")
            }.tag(MainAppTab.donate)
            SettingsView(store: store).tabItem {
                Label(AppLocalization.string("Settings"), systemImage: "gearshape.fill")
            }.tag(MainAppTab.settings)
        }
    }
}
