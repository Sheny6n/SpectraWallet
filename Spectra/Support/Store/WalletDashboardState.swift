import Foundation

final class WalletDashboardState {
    var pinnedAssetSymbols: [String] = []
    var pinOptionBySymbol: [String: DashboardPinOption] = [:]
    var availablePinOptions: [DashboardPinOption] = []
    var assetGroups: [DashboardAssetGroup] = []
    var relevantPriceKeys: Set<String> = []
}
