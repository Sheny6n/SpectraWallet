import SwiftUI

@ViewBuilder
func dashboardDetailRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
        Text(label)
            .foregroundStyle(.secondary)
        Spacer(minLength: 16)
        Text(value)
            .multilineTextAlignment(.trailing)
    }
    .font(.caption)
}

struct DashboardAssetRowView: View {
    @ObservedObject var store: WalletStore
    let assetGroup: DashboardAssetGroup

    private var priceText: String {
        guard let price = store.currentPriceIfAvailable(for: assetGroup.representativeCoin) else {
            return store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: nil)
        }
        return store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: price)
    }

    private var amountText: String {
        store.formattedAssetAmount(
            assetGroup.totalAmount,
            symbol: assetGroup.symbol,
            chainName: assetGroup.representativeCoin.chainName
        )
    }

    private var chainSummaryText: String {
        if assetGroup.chainEntries.isEmpty {
            return NSLocalizedString("No chain balances yet", comment: "")
        }
        if assetGroup.chainEntries.count == 1, let chainName = assetGroup.chainEntries.first?.coin.chainName {
            return dashboardComponentsLocalizedFormat("dashboard.asset.onChain", chainName)
        }
        let names = assetGroup.chainEntries.map(\.coin.chainName)
        let preview = names.prefix(2).joined(separator: ", ")
        let remainder = names.count - min(names.count, 2)
        if remainder > 0 {
            return dashboardComponentsLocalizedFormat("On %@ +%lld more", preview, remainder)
        }
        return dashboardComponentsLocalizedFormat("dashboard.asset.onChain", preview)
    }

    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: assetGroup.iconIdentifier,
                fallbackText: assetGroup.mark,
                color: assetGroup.color,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if assetGroup.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.82))
                            .frame(width: 28, height: 20)
                            .background(Color.red.opacity(0.1), in: Capsule())
                            .clipped()
                    }
                    Text(assetGroup.name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(amountText)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .spectraNumericTextLayout()

                Text(chainSummaryText)
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.58))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: assetGroup.totalValueUSD))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .spectraNumericTextLayout()
                Text(priceText)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .spectraNumericTextLayout()
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.42))
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}

struct DashboardPinnedAssetRowView: View {
    let option: DashboardPinOption
    let subtitleText: String

    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(
                assetIdentifier: option.assetIdentifier,
                fallbackText: option.mark,
                color: option.color,
                size: 34
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(option.name)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PortfolioWalletToggleRowView: View {
    let wallet: ImportedWallet

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(wallet.name)
            Text(wallet.selectedChain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardNoticeCardView: View {
    let notice: AppNoticeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: notice.systemImage)
                    .foregroundStyle(notice.severity.tint)
                Text(notice.title)
                    .font(.headline)
                Spacer()
                Text(notice.severity.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(notice.severity.tint)
            }

            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let timestamp = notice.timestamp {
                Text(dashboardComponentsLocalizedFormat("Last known healthy sync: %@", timestamp.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private func dashboardComponentsLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String(format: format, locale: Locale.current, arguments: arguments)
}
