import Foundation
import Combine
import SwiftUI

struct DiagnosticsHubView: View {
    let store: WalletStore
    @State private var searchText: String = ""
    private let copy = DiagnosticsContentCopy.current

    private struct DiagnosticsDestination: Identifiable {
        let id: String
        let title: String
        let keywords: [String]
        let makeView: () -> AnyView
    }

    private var chainDestinations: [DiagnosticsDestination] {
        ChainBackendRegistry.diagnosticsChains.compactMap { descriptor in
            guard let chain = StandardDiagnosticsChain(chainID: descriptor.id) else { return nil }
            return DiagnosticsDestination(
                id: descriptor.title,
                title: descriptor.title,
                keywords: descriptor.searchKeywords,
                makeView: { AnyView(StandardChainDiagnosticsView(store: store, chain: chain)) }
            )
        }
    }

    private var crossChainDestinations: [DiagnosticsDestination] {
        [
            DiagnosticsDestination(
                id: copy.crossChainHistoryTitle,
                title: copy.crossChainHistoryTitle,
                keywords: copy.crossChainHistoryKeywords,
                makeView: { AnyView(HistorySourceConfidenceDiagnosticsView(store: store)) }
            )
        ]
    }

    private func filteredDestinations(_ destinations: [DiagnosticsDestination]) -> [DiagnosticsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return destinations }
        return destinations.filter { destination in
            destination.title.localizedCaseInsensitiveContains(query)
                || destination.keywords.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    @ViewBuilder
    private func destinationSection(_ title: String, destinations: [DiagnosticsDestination]) -> some View {
        Section(title) {
            ForEach(filteredDestinations(destinations)) { destination in
                NavigationLink {
                    destination.makeView()
                } label: {
                    Text(destination.title)
                }
            }
        }
    }

    var body: some View {
        Form {
            destinationSection(copy.chainsSectionTitle, destinations: chainDestinations)
            destinationSection(copy.crossChainSectionTitle, destinations: crossChainDestinations)
        }
        .navigationTitle(copy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: copy.searchPrompt)
    }
}

enum StandardDiagnosticsChain: Hashable, CaseIterable {
    case dogecoin
    case bitcoin
    case bitcoinCash
    case litecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    case tron
    case solana
    case cardano
    case xrp
    case stellar
    case monero
    case sui
    case aptos
    case ton
    case icp
    case near
    case polkadot

    var chainID: AppChainID {
        switch self {
        case .dogecoin: return .dogecoin
        case .bitcoin: return .bitcoin
        case .bitcoinCash: return .bitcoinCash
        case .litecoin: return .litecoin
        case .ethereum: return .ethereum
        case .ethereumClassic: return .ethereumClassic
        case .arbitrum: return .arbitrum
        case .optimism: return .optimism
        case .bnb: return .bnb
        case .avalanche: return .avalanche
        case .hyperliquid: return .hyperliquid
        case .tron: return .tron
        case .solana: return .solana
        case .cardano: return .cardano
        case .xrp: return .xrp
        case .stellar: return .stellar
        case .monero: return .monero
        case .sui: return .sui
        case .aptos: return .aptos
        case .ton: return .ton
        case .icp: return .icp
        case .near: return .near
        case .polkadot: return .polkadot
        }
    }

    init?(chainID: AppChainID) {
        switch chainID {
        case .dogecoin: self = .dogecoin
        case .bitcoin: self = .bitcoin
        case .bitcoinCash: self = .bitcoinCash
        case .litecoin: self = .litecoin
        case .ethereum: self = .ethereum
        case .ethereumClassic: self = .ethereumClassic
        case .arbitrum: self = .arbitrum
        case .optimism: self = .optimism
        case .bnb: self = .bnb
        case .avalanche: self = .avalanche
        case .hyperliquid: self = .hyperliquid
        case .tron: self = .tron
        case .solana: self = .solana
        case .cardano: self = .cardano
        case .xrp: self = .xrp
        case .stellar: self = .stellar
        case .monero: self = .monero
        case .sui: self = .sui
        case .aptos: self = .aptos
        case .ton: self = .ton
        case .icp: self = .icp
        case .near: self = .near
        case .polkadot: self = .polkadot
        case .bitcoinSV:
            return nil
        }
    }

    var descriptor: AppChainDescriptor {
        ChainBackendRegistry.appChain(for: chainID)
    }

    var title: String { descriptor.title }

    var shortLabel: String { descriptor.shortLabel }
}

private struct StandardEndpointRow: Identifiable {
    let id = UUID()
    let endpoint: String
    let reachable: Bool
    let detail: String
}

private struct StandardHistorySourceRow: Identifiable {
    let source: String
    let count: Int
    var id: String { source }
}

struct StandardChainDiagnosticsView: View {
    @ObservedObject var store: WalletStore
    let chain: StandardDiagnosticsChain
    private let copy = DiagnosticsContentCopy.current
    @State private var copiedDiagnosticsNotice: String?
    @State private var selectedMoneroBackendID: String = MoneroBalanceService.defaultBackendID
    @State private var cachedEndpointRows: [StandardEndpointRow] = []
    @State private var cachedHistorySourceRows: [StandardHistorySourceRow] = []

    private let moneroCustomBackendID = "custom"

    private var moneroBackendChoices: [(id: String, title: String)] {
        let trusted = MoneroBalanceService.trustedBackends.map { ($0.id, $0.displayName) }
        return trusted + [(moneroCustomBackendID, NSLocalizedString("Custom URL", comment: ""))]
    }

    private var selectedTrustedMoneroBackend: MoneroBalanceService.TrustedBackend? {
        MoneroBalanceService.trustedBackends.first(where: { $0.id == selectedMoneroBackendID })
    }

    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                if chain == .ethereum {
                    Button(
                        store.isRunningEthereumSelfTests
                            ? localizedFormat("Running %@ Diagnostics...", chain.shortLabel)
                            : localizedFormat("Run %@ Diagnostics", chain.shortLabel)
                    ) {
                        Task {
                            await store.runEthereumSelfTests()
                        }
                    }
                    .disabled(store.isRunningEthereumSelfTests)
                }

                Button(
                    isRunningHistory
                        ? localizedFormat("Running %@ History Diagnostics...", chain.shortLabel)
                        : localizedFormat("Run %@ History Diagnostics", chain.shortLabel)
                ) {
                    Task {
                        await runHistoryDiagnostics()
                    }
                }
                .disabled(isRunningHistory)

                Button(localizedFormat("Copy %@ Diagnostics JSON", chain.shortLabel)) {
                    if let payload = diagnosticsJSON {
                        UIPasteboard.general.string = payload
                        copiedDiagnosticsNotice = localizedFormat("%@ diagnostics JSON copied.", chain.shortLabel)
                    } else {
                        copiedDiagnosticsNotice = localizedFormat("No %@ diagnostics available to copy.", chain.shortLabel)
                    }
                }

                Button(
                    isCheckingEndpoints
                        ? localizedFormat("Checking %@ Endpoints...", chain.shortLabel)
                        : localizedFormat("Check %@ Endpoints", chain.shortLabel)
                ) {
                    Task {
                        await runEndpointDiagnostics()
                    }
                }
                .disabled(isCheckingEndpoints)

                if let copiedDiagnosticsNotice {
                    Text(copiedDiagnosticsNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(copy.statusSectionTitle) {
                if let updatedAt = historyLastUpdatedAt {
                    Text(String(format: copy.lastHistoryRunFormat, updatedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(copy.historyNotRunYet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: copy.walletDiagnosticsCoveredFormat, String(historyWalletCount)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let primarySource = historySourceRows.first {
                    Text(String(format: copy.mostUsedHistorySourceFormat, primarySource.source, String(primarySource.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updatedAt = endpointLastUpdatedAt {
                    Text(String(format: copy.lastEndpointCheckFormat, updatedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !endpointRows.isEmpty {
                    let reachableCount = endpointRows.filter(\.reachable).count
                    Text(String(format: copy.endpointHealthFormat, String(reachableCount), String(endpointRows.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localizedFormat("%@ History Sources", chain.shortLabel)) {
                if historySourceRows.isEmpty {
                    Text(copy.noHistoryTelemetryYet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historySourceRows) { item in
                        HStack {
                            Text(item.source)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(localizedFormat("diagnostics.countOnly", item.count))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(localizedFormat("%@ Endpoint Reachability", chain.shortLabel)) {
                if endpointRows.isEmpty {
                    Text(copy.noEndpointChecksYet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(endpointRows) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.reachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.reachable ? .green : .red)
                                Text(result.endpoint)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            chainSpecificSections
        }
        .navigationTitle(chain.title)
        .onAppear {
            if chain == .monero {
                syncSelectedMoneroBackendIDFromStore()
            }
            rebuildCachedRows()
        }
        .onChange(of: copiedDiagnosticsNotice) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copiedDiagnosticsNotice = nil
            }
        }
        .onChange(of: selectedMoneroBackendID) { _, newValue in
            guard chain == .monero else { return }
            if newValue == moneroCustomBackendID {
                return
            }
            if newValue == MoneroBalanceService.defaultBackendID {
                store.moneroBackendBaseURL = ""
                return
            }
            if let trusted = MoneroBalanceService.trustedBackends.first(where: { $0.id == newValue }) {
                store.moneroBackendBaseURL = trusted.baseURL
            }
        }
        .onChange(of: store.moneroBackendBaseURL) { _, _ in
            guard chain == .monero else { return }
            syncSelectedMoneroBackendIDFromStore()
        }
        .onReceive(historyDiagnosticsChangePublisher) { _ in
            rebuildHistorySourceRows()
        }
        .onReceive(endpointDiagnosticsChangePublisher) { _ in
            rebuildEndpointRows()
        }
    }

    private var isRunningHistory: Bool {
        switch chain {
        case .dogecoin: return store.isRunningDogecoinHistoryDiagnostics
        case .bitcoin: return store.isRunningBitcoinHistoryDiagnostics
        case .bitcoinCash: return store.isRunningBitcoinCashHistoryDiagnostics
        case .litecoin: return store.isRunningLitecoinHistoryDiagnostics
        case .ethereum: return store.isRunningEthereumHistoryDiagnostics
        case .ethereumClassic: return store.isRunningETCHistoryDiagnostics
        case .arbitrum: return store.isRunningArbitrumHistoryDiagnostics
        case .optimism: return store.isRunningOptimismHistoryDiagnostics
        case .bnb: return store.isRunningBNBHistoryDiagnostics
        case .avalanche: return store.isRunningAvalancheHistoryDiagnostics
        case .hyperliquid: return store.isRunningHyperliquidHistoryDiagnostics
        case .tron: return store.isRunningTronHistoryDiagnostics
        case .solana: return store.isRunningSolanaHistoryDiagnostics
        case .cardano: return store.isRunningCardanoHistoryDiagnostics
        case .xrp: return store.isRunningXRPHistoryDiagnostics
        case .stellar: return store.isRunningStellarHistoryDiagnostics
        case .monero: return store.isRunningMoneroHistoryDiagnostics
        case .sui: return store.isRunningSuiHistoryDiagnostics
        case .aptos: return store.isRunningAptosHistoryDiagnostics
        case .ton: return store.isRunningTONHistoryDiagnostics
        case .icp: return store.isRunningICPHistoryDiagnostics
        case .near: return store.isRunningNearHistoryDiagnostics
        case .polkadot: return store.isRunningPolkadotHistoryDiagnostics
        }
    }

    private var isCheckingEndpoints: Bool {
        switch chain {
        case .dogecoin: return store.isCheckingDogecoinEndpointHealth
        case .bitcoin: return store.isCheckingBitcoinEndpointHealth
        case .bitcoinCash: return store.isCheckingBitcoinCashEndpointHealth
        case .litecoin: return store.isCheckingLitecoinEndpointHealth
        case .ethereum: return store.isCheckingEthereumEndpointHealth
        case .ethereumClassic: return store.isCheckingETCEndpointHealth
        case .arbitrum: return store.isCheckingArbitrumEndpointHealth
        case .optimism: return store.isCheckingOptimismEndpointHealth
        case .bnb: return store.isCheckingBNBEndpointHealth
        case .avalanche: return store.isCheckingAvalancheEndpointHealth
        case .hyperliquid: return store.isCheckingHyperliquidEndpointHealth
        case .tron: return store.isCheckingTronEndpointHealth
        case .solana: return store.isCheckingSolanaEndpointHealth
        case .cardano: return store.isCheckingCardanoEndpointHealth
        case .xrp: return store.isCheckingXRPEndpointHealth
        case .stellar: return store.isCheckingStellarEndpointHealth
        case .monero: return store.isCheckingMoneroEndpointHealth
        case .sui: return store.isCheckingSuiEndpointHealth
        case .aptos: return store.isCheckingAptosEndpointHealth
        case .ton: return store.isCheckingTONEndpointHealth
        case .icp: return store.isCheckingICPEndpointHealth
        case .near: return store.isCheckingNearEndpointHealth
        case .polkadot: return store.isCheckingPolkadotEndpointHealth
        }
    }

    private var diagnosticsJSON: String? {
        switch chain {
        case .dogecoin: return store.dogecoinDiagnosticsJSON()
        case .bitcoin: return store.bitcoinDiagnosticsJSON()
        case .bitcoinCash: return store.bitcoinCashDiagnosticsJSON()
        case .litecoin: return store.litecoinDiagnosticsJSON()
        case .ethereum: return store.ethereumDiagnosticsJSON()
        case .ethereumClassic: return store.etcDiagnosticsJSON()
        case .arbitrum: return store.arbitrumDiagnosticsJSON()
        case .optimism: return store.optimismDiagnosticsJSON()
        case .bnb: return store.bnbDiagnosticsJSON()
        case .avalanche: return store.avalancheDiagnosticsJSON()
        case .hyperliquid: return store.hyperliquidDiagnosticsJSON()
        case .tron: return store.tronDiagnosticsJSON()
        case .solana: return store.solanaDiagnosticsJSON()
        case .cardano: return store.cardanoDiagnosticsJSON()
        case .xrp: return store.xrpDiagnosticsJSON()
        case .stellar: return store.stellarDiagnosticsJSON()
        case .monero: return store.moneroDiagnosticsJSON()
        case .sui: return store.suiDiagnosticsJSON()
        case .aptos: return store.aptosDiagnosticsJSON()
        case .ton: return store.tonDiagnosticsJSON()
        case .icp: return store.icpDiagnosticsJSON()
        case .near: return store.nearDiagnosticsJSON()
        case .polkadot: return store.polkadotDiagnosticsJSON()
        }
    }

    private var historyLastUpdatedAt: Date? {
        switch chain {
        case .dogecoin: return store.dogecoinHistoryDiagnosticsLastUpdatedAt
        case .bitcoin: return store.bitcoinHistoryDiagnosticsLastUpdatedAt
        case .bitcoinCash: return store.bitcoinCashHistoryDiagnosticsLastUpdatedAt
        case .litecoin: return store.litecoinHistoryDiagnosticsLastUpdatedAt
        case .ethereum: return store.ethereumHistoryDiagnosticsLastUpdatedAt
        case .ethereumClassic: return store.etcHistoryDiagnosticsLastUpdatedAt
        case .arbitrum: return store.arbitrumHistoryDiagnosticsLastUpdatedAt
        case .optimism: return store.optimismHistoryDiagnosticsLastUpdatedAt
        case .bnb: return store.bnbHistoryDiagnosticsLastUpdatedAt
        case .avalanche: return store.avalancheHistoryDiagnosticsLastUpdatedAt
        case .hyperliquid: return store.hyperliquidHistoryDiagnosticsLastUpdatedAt
        case .tron: return store.tronHistoryDiagnosticsLastUpdatedAt
        case .solana: return store.solanaHistoryDiagnosticsLastUpdatedAt
        case .cardano: return store.cardanoHistoryDiagnosticsLastUpdatedAt
        case .xrp: return store.xrpHistoryDiagnosticsLastUpdatedAt
        case .stellar: return store.stellarHistoryDiagnosticsLastUpdatedAt
        case .monero: return store.moneroHistoryDiagnosticsLastUpdatedAt
        case .sui: return store.suiHistoryDiagnosticsLastUpdatedAt
        case .aptos: return store.aptosHistoryDiagnosticsLastUpdatedAt
        case .ton: return store.tonHistoryDiagnosticsLastUpdatedAt
        case .icp: return store.icpHistoryDiagnosticsLastUpdatedAt
        case .near: return store.nearHistoryDiagnosticsLastUpdatedAt
        case .polkadot: return store.polkadotHistoryDiagnosticsLastUpdatedAt
        }
    }

    private var historyWalletCount: Int {
        switch chain {
        case .dogecoin: return store.dogecoinHistoryDiagnosticsByWallet.count
        case .bitcoin: return store.bitcoinHistoryDiagnosticsByWallet.count
        case .bitcoinCash: return store.bitcoinCashHistoryDiagnosticsByWallet.count
        case .litecoin: return store.litecoinHistoryDiagnosticsByWallet.count
        case .ethereum: return store.ethereumHistoryDiagnosticsByWallet.count
        case .ethereumClassic: return store.etcHistoryDiagnosticsByWallet.count
        case .arbitrum: return store.arbitrumHistoryDiagnosticsByWallet.count
        case .optimism: return store.optimismHistoryDiagnosticsByWallet.count
        case .bnb: return store.bnbHistoryDiagnosticsByWallet.count
        case .avalanche: return store.avalancheHistoryDiagnosticsByWallet.count
        case .hyperliquid: return store.hyperliquidHistoryDiagnosticsByWallet.count
        case .tron: return store.tronHistoryDiagnosticsByWallet.count
        case .solana: return store.solanaHistoryDiagnosticsByWallet.count
        case .cardano: return store.cardanoHistoryDiagnosticsByWallet.count
        case .xrp: return store.xrpHistoryDiagnosticsByWallet.count
        case .stellar: return store.stellarHistoryDiagnosticsByWallet.count
        case .monero: return store.moneroHistoryDiagnosticsByWallet.count
        case .sui: return store.suiHistoryDiagnosticsByWallet.count
        case .aptos: return store.aptosHistoryDiagnosticsByWallet.count
        case .ton: return store.tonHistoryDiagnosticsByWallet.count
        case .icp: return store.icpHistoryDiagnosticsByWallet.count
        case .near: return store.nearHistoryDiagnosticsByWallet.count
        case .polkadot: return store.polkadotHistoryDiagnosticsByWallet.count
        }
    }

    private var endpointLastUpdatedAt: Date? {
        switch chain {
        case .dogecoin: return store.dogecoinEndpointHealthLastUpdatedAt
        case .bitcoin: return store.bitcoinEndpointHealthLastUpdatedAt
        case .bitcoinCash: return store.bitcoinCashEndpointHealthLastUpdatedAt
        case .litecoin: return store.litecoinEndpointHealthLastUpdatedAt
        case .ethereum: return store.ethereumEndpointHealthLastUpdatedAt
        case .ethereumClassic: return store.etcEndpointHealthLastUpdatedAt
        case .arbitrum: return store.arbitrumEndpointHealthLastUpdatedAt
        case .optimism: return store.optimismEndpointHealthLastUpdatedAt
        case .bnb: return store.bnbEndpointHealthLastUpdatedAt
        case .avalanche: return store.avalancheEndpointHealthLastUpdatedAt
        case .hyperliquid: return store.hyperliquidEndpointHealthLastUpdatedAt
        case .tron: return store.tronEndpointHealthLastUpdatedAt
        case .solana: return store.solanaEndpointHealthLastUpdatedAt
        case .cardano: return store.cardanoEndpointHealthLastUpdatedAt
        case .xrp: return store.xrpEndpointHealthLastUpdatedAt
        case .stellar: return store.stellarEndpointHealthLastUpdatedAt
        case .monero: return store.moneroEndpointHealthLastUpdatedAt
        case .sui: return store.suiEndpointHealthLastUpdatedAt
        case .aptos: return store.aptosEndpointHealthLastUpdatedAt
        case .ton: return store.tonEndpointHealthLastUpdatedAt
        case .icp: return store.icpEndpointHealthLastUpdatedAt
        case .near: return store.nearEndpointHealthLastUpdatedAt
        case .polkadot: return store.polkadotEndpointHealthLastUpdatedAt
        }
    }

    private var endpointRows: [StandardEndpointRow] {
        cachedEndpointRows
    }

    private var historySourceRows: [StandardHistorySourceRow] {
        cachedHistorySourceRows
    }

    private var historyDiagnosticsChangePublisher: AnyPublisher<Void, Never> {
        switch chain {
        case .dogecoin: return store.$dogecoinHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .bitcoin: return store.$bitcoinHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .bitcoinCash: return store.$bitcoinCashHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .litecoin: return store.$litecoinHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .ethereum: return store.$ethereumHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .ethereumClassic: return store.$etcHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .arbitrum: return store.$arbitrumHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .optimism: return store.$optimismHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .bnb: return store.$bnbHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .avalanche: return store.$avalancheHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .hyperliquid: return store.$hyperliquidHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .tron: return store.$tronHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .solana: return store.$solanaHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .cardano: return store.$cardanoHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .xrp: return store.$xrpHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .stellar: return store.$stellarHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .monero: return store.$moneroHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .sui: return store.$suiHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .aptos: return store.$aptosHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .ton: return store.$tonHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .icp: return store.$icpHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .near: return store.$nearHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        case .polkadot: return store.$polkadotHistoryDiagnosticsByWallet.map { _ in () }.eraseToAnyPublisher()
        }
    }

    private var endpointDiagnosticsChangePublisher: AnyPublisher<Void, Never> {
        switch chain {
        case .dogecoin: return store.$dogecoinEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .bitcoin: return store.$bitcoinEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .bitcoinCash: return store.$bitcoinCashEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .litecoin: return store.$litecoinEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .ethereum: return store.$ethereumEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .ethereumClassic: return store.$etcEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .arbitrum: return store.$arbitrumEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .optimism: return store.$optimismEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .bnb: return store.$bnbEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .avalanche: return store.$avalancheEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .hyperliquid: return store.$hyperliquidEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .tron: return store.$tronEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .solana: return store.$solanaEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .cardano: return store.$cardanoEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .xrp: return store.$xrpEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .stellar: return store.$stellarEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .monero: return store.$moneroEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .sui: return store.$suiEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .aptos: return store.$aptosEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .ton: return store.$tonEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .icp: return store.$icpEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .near: return store.$nearEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        case .polkadot: return store.$polkadotEndpointHealthResults.map { _ in () }.eraseToAnyPublisher()
        }
    }

    private func rebuildCachedRows() {
        rebuildEndpointRows()
        rebuildHistorySourceRows()
    }

    private func rebuildEndpointRows() {
        switch chain {
        case .dogecoin:
            cachedEndpointRows = store.dogecoinEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .bitcoin:
            cachedEndpointRows = store.bitcoinEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .bitcoinCash:
            cachedEndpointRows = store.bitcoinCashEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .litecoin:
            cachedEndpointRows = store.litecoinEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .ethereum:
            cachedEndpointRows = store.ethereumEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .ethereumClassic:
            cachedEndpointRows = store.etcEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .arbitrum:
            cachedEndpointRows = store.arbitrumEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .optimism:
            cachedEndpointRows = store.optimismEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .bnb:
            cachedEndpointRows = store.bnbEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .avalanche:
            cachedEndpointRows = store.avalancheEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .hyperliquid:
            cachedEndpointRows = store.hyperliquidEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .tron:
            cachedEndpointRows = store.tronEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .solana:
            cachedEndpointRows = store.solanaEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .cardano:
            cachedEndpointRows = store.cardanoEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .xrp:
            cachedEndpointRows = store.xrpEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .monero:
            cachedEndpointRows = store.moneroEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .sui:
            cachedEndpointRows = store.suiEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .aptos:
            cachedEndpointRows = store.aptosEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .ton:
            cachedEndpointRows = store.tonEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .icp:
            cachedEndpointRows = store.icpEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .near:
            cachedEndpointRows = store.nearEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .polkadot:
            cachedEndpointRows = store.polkadotEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        case .stellar:
            cachedEndpointRows = store.stellarEndpointHealthResults.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
        }
    }

    private func rebuildHistorySourceRows() {
        let sources: [String]
        switch chain {
        case .dogecoin:
            sources = store.dogecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bitcoin:
            sources = store.bitcoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bitcoinCash:
            sources = store.bitcoinCashHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .litecoin:
            sources = store.litecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .ethereum:
            sources = store.ethereumHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .ethereumClassic:
            sources = store.etcHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .arbitrum:
            sources = store.arbitrumHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .optimism:
            sources = store.optimismHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bnb:
            sources = store.bnbHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .avalanche:
            sources = store.avalancheHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .hyperliquid:
            sources = store.hyperliquidHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .tron:
            sources = store.tronHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .solana:
            sources = store.solanaHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .cardano:
            sources = store.cardanoHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .xrp:
            sources = store.xrpHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .monero:
            sources = store.moneroHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .sui:
            sources = store.suiHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .aptos:
            sources = store.aptosHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .ton:
            sources = store.tonHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .icp:
            sources = store.icpHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .near:
            sources = store.nearHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .polkadot:
            sources = store.polkadotHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .stellar:
            sources = store.stellarHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        }

        var counts: [String: Int] = [:]
        for source in sources {
            let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            counts[normalized, default: 0] += 1
        }
        cachedHistorySourceRows = counts
            .map { StandardHistorySourceRow(source: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.source < rhs.source
            }
    }

    private func runHistoryDiagnostics() async {
        switch chain {
        case .dogecoin: await store.runDogecoinHistoryDiagnostics()
        case .bitcoin: await store.runBitcoinHistoryDiagnostics()
        case .bitcoinCash: await store.runBitcoinCashHistoryDiagnostics()
        case .litecoin: await store.runLitecoinHistoryDiagnostics()
        case .ethereum: await store.runEthereumHistoryDiagnostics()
        case .ethereumClassic: await store.runETCHistoryDiagnostics()
        case .arbitrum: await store.runArbitrumHistoryDiagnostics()
        case .optimism: await store.runOptimismHistoryDiagnostics()
        case .bnb: await store.runBNBHistoryDiagnostics()
        case .avalanche: await store.runAvalancheHistoryDiagnostics()
        case .hyperliquid: await store.runHyperliquidHistoryDiagnostics()
        case .tron: await store.runTronHistoryDiagnostics()
        case .solana: await store.runSolanaHistoryDiagnostics()
        case .cardano: await store.runCardanoHistoryDiagnostics()
        case .xrp: await store.runXRPHistoryDiagnostics()
        case .monero: await store.runMoneroHistoryDiagnostics()
        case .sui: await store.runSuiHistoryDiagnostics()
        case .aptos: await store.runAptosHistoryDiagnostics()
        case .ton: await store.runTONHistoryDiagnostics()
        case .icp: await store.runICPHistoryDiagnostics()
        case .near: await store.runNearHistoryDiagnostics()
        case .polkadot: await store.runPolkadotHistoryDiagnostics()
        case .stellar: await store.runStellarHistoryDiagnostics()
        }
    }

    private func runEndpointDiagnostics() async {
        switch chain {
        case .dogecoin: await store.runDogecoinEndpointReachabilityDiagnostics()
        case .bitcoin: await store.runBitcoinEndpointReachabilityDiagnostics()
        case .bitcoinCash: await store.runBitcoinCashEndpointReachabilityDiagnostics()
        case .litecoin: await store.runLitecoinEndpointReachabilityDiagnostics()
        case .ethereum: await store.runEthereumEndpointReachabilityDiagnostics()
        case .ethereumClassic: await store.runETCEndpointReachabilityDiagnostics()
        case .arbitrum: await store.runArbitrumEndpointReachabilityDiagnostics()
        case .optimism: await store.runOptimismEndpointReachabilityDiagnostics()
        case .bnb: await store.runBNBEndpointReachabilityDiagnostics()
        case .avalanche: await store.runAvalancheEndpointReachabilityDiagnostics()
        case .hyperliquid: await store.runHyperliquidEndpointReachabilityDiagnostics()
        case .tron: await store.runTronEndpointReachabilityDiagnostics()
        case .solana: await store.runSolanaEndpointReachabilityDiagnostics()
        case .cardano: await store.runCardanoEndpointReachabilityDiagnostics()
        case .xrp: await store.runXRPEndpointReachabilityDiagnostics()
        case .monero: await store.runMoneroEndpointReachabilityDiagnostics()
        case .sui: await store.runSuiEndpointReachabilityDiagnostics()
        case .aptos: await store.runAptosEndpointReachabilityDiagnostics()
        case .ton: await store.runTONEndpointReachabilityDiagnostics()
        case .icp: await store.runICPEndpointReachabilityDiagnostics()
        case .near: await store.runNearEndpointReachabilityDiagnostics()
        case .polkadot: await store.runPolkadotEndpointReachabilityDiagnostics()
        case .stellar: await store.runStellarEndpointReachabilityDiagnostics()
        }
    }

    @ViewBuilder
    private var chainSpecificSections: some View {
        if chain == .bitcoin {
            Section(NSLocalizedString("Bitcoin Network", comment: "")) {
                Picker(NSLocalizedString("Mode", comment: ""), selection: $store.bitcoinNetworkMode) {
                    ForEach(BitcoinNetworkMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Stepper(localizedFormat("Address Gap Limit: %lld", store.bitcoinStopGap), value: $store.bitcoinStopGap, in: 1 ... 200)

                Picker(NSLocalizedString("Send Fee Priority", comment: ""), selection: $store.bitcoinFeePriority) {
                    ForEach(BitcoinFeePriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                TextField(NSLocalizedString("Custom Esplora endpoints (comma-separated, optional)", comment: ""), text: $store.bitcoinEsploraEndpoints)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let bitcoinEsploraEndpointsValidationError = store.bitcoinEsploraEndpointsValidationError {
                    Text(bitcoinEsploraEndpointsValidationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(copy.bitcoinEsploraHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if chain == .ethereum {
            Section(NSLocalizedString("Ethereum RPC", comment: "")) {
                TextField(NSLocalizedString("Ethereum RPC URL (Optional)", comment: ""), text: $store.ethereumRPCEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text(copy.ethereumRPCNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let ethereumRPCEndpointValidationError = store.ethereumRPCEndpointValidationError {
                    Text(ethereumRPCEndpointValidationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(NSLocalizedString("Etherscan (Optional)", comment: "")) {
                TextField(NSLocalizedString("Etherscan API Key", comment: ""), text: $store.etherscanAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(copy.etherscanNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if chain == .monero {
            Section(NSLocalizedString("Monero Backend", comment: "")) {
                Picker(NSLocalizedString("Trusted Backend", comment: ""), selection: $selectedMoneroBackendID) {
                    ForEach(moneroBackendChoices, id: \.id) { choice in
                        Text(choice.title).tag(choice.id)
                    }
                }

                if selectedMoneroBackendID == moneroCustomBackendID {
                    TextField(NSLocalizedString("Monero Backend URL (Optional)", comment: ""), text: $store.moneroBackendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    Text(selectedTrustedMoneroBackend?.baseURL ?? MoneroBalanceService.defaultPublicBackend.baseURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if let moneroBackendBaseURLValidationError = store.moneroBackendBaseURLValidationError {
                    Text(moneroBackendBaseURLValidationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(copy.moneroBackendNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField(NSLocalizedString("Monero Backend API Key (Optional)", comment: ""), text: $store.moneroBackendAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(copy.moneroAPIKeyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if chain == .dogecoin {
            Section(NSLocalizedString("Network Policy", comment: "")) {
                Toggle(NSLocalizedString("Allow Testnet Addresses", comment: ""), isOn: $store.dogecoinAllowTestnet)
                Text(copy.dogecoinTestnetNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(NSLocalizedString("Providers", comment: "")) {
                Toggle(NSLocalizedString("Broadcast via Blockchair", comment: ""), isOn: dogecoinBroadcastBlockchairBinding)
                Toggle(NSLocalizedString("Broadcast via BlockCypher", comment: ""), isOn: dogecoinBroadcastBlockcypherBinding)
                Toggle(NSLocalizedString("Status via Blockchair", comment: ""), isOn: dogecoinStatusBlockchairBinding)
                Toggle(NSLocalizedString("Status via BlockCypher", comment: ""), isOn: dogecoinStatusBlockcypherBinding)
            }

            Section(NSLocalizedString("DOGE Exclusive Actions", comment: "")) {
                Button(NSLocalizedString("Reset Provider Reliability", comment: "")) {
                    store.resetDogecoinBroadcastProviderReliability()
                }
                Button(store.isRunningDogecoinSelfTests ? NSLocalizedString("Running Self-Tests...", comment: "") : NSLocalizedString("Run DOGE Self-Tests", comment: "")) {
                    store.runDogecoinSelfTests()
                }
                .disabled(store.isRunningDogecoinSelfTests)

                Button(store.isRunningDogecoinRescan ? NSLocalizedString("Rescanning DOGE...", comment: "") : NSLocalizedString("Run DOGE Rescan", comment: "")) {
                    Task {
                        await store.runDogecoinRescan()
                    }
                }
                .disabled(store.isRunningDogecoinRescan)
            }

            Section(NSLocalizedString("Broadcast Reliability", comment: "")) {
                if store.dogecoinBroadcastProviderReliability.isEmpty {
                    Text(copy.noBroadcastReliabilityYet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.dogecoinBroadcastProviderReliability) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.providerID)
                                .font(.subheadline.weight(.semibold))
                            Text(String(format: copy.broadcastReliabilityFormat, String(item.successCount), String(item.failureCount), successRateString(item.successRate)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func syncSelectedMoneroBackendIDFromStore() {
        let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            selectedMoneroBackendID = MoneroBalanceService.defaultBackendID
            return
        }
        if let trusted = MoneroBalanceService.trustedBackends.first(where: { $0.baseURL.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedMoneroBackendID = trusted.id
            return
        }
        selectedMoneroBackendID = moneroCustomBackendID
    }

    private func successRateString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var dogecoinBroadcastBlockchairBinding: Binding<Bool> {
        Binding(
            get: { store.dogecoinBroadcastUseBlockchair },
            set: { newValue in
                if !newValue && !store.dogecoinBroadcastUseBlockcypher { return }
                store.dogecoinBroadcastUseBlockchair = newValue
            }
        )
    }

    private var dogecoinBroadcastBlockcypherBinding: Binding<Bool> {
        Binding(
            get: { store.dogecoinBroadcastUseBlockcypher },
            set: { newValue in
                if !newValue && !store.dogecoinBroadcastUseBlockchair { return }
                store.dogecoinBroadcastUseBlockcypher = newValue
            }
        )
    }

    private var dogecoinStatusBlockchairBinding: Binding<Bool> {
        Binding(
            get: { store.dogecoinStatusUseBlockchair },
            set: { newValue in
                if !newValue && !store.dogecoinStatusUseBlockcypher { return }
                store.dogecoinStatusUseBlockchair = newValue
            }
        )
    }

    private var dogecoinStatusBlockcypherBinding: Binding<Bool> {
        Binding(
            get: { store.dogecoinStatusUseBlockcypher },
            set: { newValue in
                if !newValue && !store.dogecoinStatusUseBlockchair { return }
                store.dogecoinStatusUseBlockcypher = newValue
            }
        )
    }
}

struct HistorySourceConfidenceDiagnosticsView: View {
    @ObservedObject var store: WalletStore
    private let copy = DiagnosticsContentCopy.current
    @State private var cachedGroupedRows: [(key: String, count: Int)] = []

    private var groupedRows: [(key: String, count: Int)] {
        cachedGroupedRows
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("Summary", comment: "")) {
                Text(String(format: copy.totalNormalizedEntriesFormat, String(store.normalizedHistoryIndex.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(NSLocalizedString("Chain | Source | Confidence", comment: "")) {
                if groupedRows.isEmpty {
                    Text(copy.noNormalizedHistoryYet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedRows, id: \.key) { item in
                        HStack(alignment: .top) {
                            Text(item.key)
                                .font(.subheadline)
                            Spacer(minLength: 12)
                            Text(localizedFormat("diagnostics.countOnly", item.count))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("History Confidence", comment: ""))
        .onAppear {
            rebuildGroupedRows()
        }
        .onReceive(store.transactionState.$normalizedHistoryIndex) { _ in
            rebuildGroupedRows()
        }
    }

    private func rebuildGroupedRows() {
        var counts: [String: Int] = [:]
        for entry in store.normalizedHistoryIndex {
            let key = "\(entry.chainName) | \(entry.sourceTag) | \(entry.sourceConfidenceTag)"
            counts[key, default: 0] += 1
        }
        cachedGroupedRows = counts
            .map { (key: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.key < rhs.key
            }
    }
}

private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
