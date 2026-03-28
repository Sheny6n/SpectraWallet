import SwiftUI
import Combine

private struct HistoryRowPresentation: Identifiable {
    let transaction: TransactionRecord
    let amountText: String?
    let titleText: String
    let subtitleText: String
    let statusText: String
    let fullTimestampText: String
    let dogecoinFeeText: String?

    var id: UUID { transaction.id }
}

private struct HistoryPresentationSection: Identifiable {
    let title: String
    let rows: [HistoryRowPresentation]

    var id: String { title }
}

struct HistoryView: View {
    @ObservedObject var store: WalletStore
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedSortOrder: HistorySortOrder = .newest
    @State private var selectedWalletID: UUID?
    @State private var searchText: String = ""
    @State private var currentPageIndex: Int = 0
    @State private var pendingScrollToTopToken = UUID()
    @State private var visibleTransactions: [TransactionRecord] = []
    @State private var visibleRows: [HistoryRowPresentation] = []

    private let entriesPerPage = 20
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    SpectraBackdrop()

                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Color.clear
                                .frame(height: 1)
                                .id("history-top")

                            controlsCard

                            if visibleTransactions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(emptyStateTitle)
                                        .font(.headline)
                                        .foregroundStyle(Color.primary)
                                    Text(emptyStateMessage)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.primary.opacity(0.76))
                                }
                                .padding(18)
                                .spectraBubbleFill()
                                .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                            } else {
                                ForEach(groupedSections) { section in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(localizedFormat("history.section.titleCount", section.title, section.rows.count))
                                            .font(.headline)
                                            .foregroundStyle(Color.primary.opacity(0.88))

                                        ForEach(section.rows) { row in
                                            VStack(alignment: .leading, spacing: 10) {
                                                NavigationLink {
                                                    HistoryDetailView(store: store, transaction: row.transaction)
                                                } label: {
                                                    transactionRow(row)
                                                }
                                                .buttonStyle(.plain)
                                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                    if row.transaction.kind == .send,
                                                       row.transaction.chainName == "Dogecoin",
                                                              row.transaction.status == .pending || row.transaction.status == .failed {
                                                        Button {
                                                            Task {
                                                                _ = await store.retryDogecoinTransactionStatus(for: row.transaction.id)
                                                            }
                                                        } label: {
                                                            Label("Recheck", systemImage: "arrow.clockwise")
                                                        }
                                                        .tint(.blue)

                                                        if row.transaction.dogecoinRawTransactionHex != nil {
                                                            Button {
                                                                Task {
                                                                    _ = await store.rebroadcastDogecoinTransaction(for: row.transaction.id)
                                                                }
                                                            } label: {
                                                                Label("Rebroadcast", systemImage: "dot.radiowaves.up.forward")
                                                            }
                                                            .tint(.mint)
                                                        }
                                                    }
                                                }

                                            }
                                        }
                                    }
                                    .padding(18)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                                }
                            }

                            if shouldShowPagingControls {
                                historyPagingControls
                            }
                        }
                        .padding(20)
                    }
                    .refreshable {
                        await store.performUserInitiatedRefresh()
                    }
                    .scrollBounceBehavior(.always)
                }
                .onChange(of: pendingScrollToTopToken) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("history-top", anchor: .top)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                rebuildVisibleTransactions(resetPaging: true)
            }
            .onReceive(store.transactionState.$transactions.combineLatest(store.transactionState.$normalizedHistoryIndex)) { _ in
                rebuildVisibleTransactions()
            }
            .onReceive(store.portfolioState.$wallets) { _ in
                rebuildVisibleTransactions()
            }
            .onChange(of: selectedFilter) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }
            .onChange(of: selectedSortOrder) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }
            .onChange(of: selectedWalletID) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }
            .onChange(of: searchText) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }
        }
    }
    
    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Search wallet, asset, symbol, or address", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .spectraInputFieldStyle(cornerRadius: 16)
                .foregroundStyle(Color.primary)
            
            HStack(spacing: 10) {
                Menu {
                    Picker("Wallet", selection: $selectedWalletID) {
                        Text("All Wallets").tag(Optional<UUID>.none)
                        ForEach(store.wallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }
                } label: {
                    filterCapsuleLabel(
                        title: "Wallet",
                        value: selectedWalletName,
                        systemImage: "wallet.pass"
                    )
                }

                Menu {
                    Picker("Type", selection: $selectedFilter) {
                        ForEach(HistoryFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                } label: {
                    filterCapsuleLabel(
                        title: "Type",
                        value: selectedFilter.rawValue,
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }

                Menu {
                    Picker("Sort", selection: $selectedSortOrder) {
                        ForEach(HistorySortOrder.allCases) { sortOrder in
                            Text(sortOrder.rawValue).tag(sortOrder)
                        }
                    }
                } label: {
                    filterCapsuleLabel(
                        title: "Sort",
                        value: selectedSortOrder.rawValue,
                        systemImage: "arrow.up.arrow.down.circle"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if selectedWalletID != nil || selectedFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    Text(localizedFormat("%lld results", visibleTransactions.count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.8))

                    Spacer()

                    Button("Clear Filters") {
                        selectedWalletID = nil
                        selectedFilter = .all
                        selectedSortOrder = .newest
                        searchText = ""
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
    
    private var clampedPageIndex: Int {
        guard totalLoadedPages > 0 else { return 0 }
        return min(currentPageIndex, totalLoadedPages - 1)
    }

    private var totalLoadedPages: Int {
        max(1, Int(ceil(Double(visibleTransactions.count) / Double(entriesPerPage))))
    }

    private var hasNextLoadedPage: Bool {
        clampedPageIndex < totalLoadedPages - 1
    }

    private var shouldShowPagingControls: Bool {
        !visibleRows.isEmpty && (clampedPageIndex > 0 || hasNextLoadedPage || store.canLoadMoreOnChainHistory || store.isLoadingMoreOnChainHistory)
    }

    private var pagedRows: [HistoryRowPresentation] {
        let startIndex = clampedPageIndex * entriesPerPage
        return Array(visibleRows.dropFirst(startIndex).prefix(entriesPerPage))
    }
    
    private var groupedSections: [HistoryPresentationSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: pagedRows) { row in
            if calendar.isDateInToday(row.transaction.createdAt) {
                return NSLocalizedString("Today", comment: "")
            }
            
            if calendar.isDateInYesterday(row.transaction.createdAt) {
                return NSLocalizedString("Yesterday", comment: "")
            }
            
            return NSLocalizedString("Older", comment: "")
        }
        
        let order: [String]
        switch selectedSortOrder {
        case .newest:
            order = [
                NSLocalizedString("Today", comment: ""),
                NSLocalizedString("Yesterday", comment: ""),
                NSLocalizedString("Older", comment: "")
            ]
        case .oldest:
            order = [
                NSLocalizedString("Older", comment: ""),
                NSLocalizedString("Yesterday", comment: ""),
                NSLocalizedString("Today", comment: "")
            ]
        }
        
        return order.compactMap { title in
            guard let rows = grouped[title], !rows.isEmpty else {
                return nil
            }
            return HistoryPresentationSection(title: title, rows: rows)
        }
    }

    private func rebuildVisibleTransactions(resetPaging: Bool = false) {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let rebuiltTransactions: [TransactionRecord]
        if store.wallets.isEmpty {
            rebuiltTransactions = []
        } else {
            let transactionByID = store.cachedTransactionByID
            let filteredTransactions: [TransactionRecord] = store.normalizedHistoryIndex.compactMap { entry in
                guard let transaction = transactionByID[entry.transactionID] else {
                    return nil
                }

                if let selectedWalletID, transaction.walletID != selectedWalletID {
                    return nil
                }

                switch selectedFilter {
                case .all:
                    break
                case .sends:
                    guard entry.kind == .send else { return nil }
                case .receives:
                    guard entry.kind == .receive else { return nil }
                case .pending:
                    guard entry.status == .pending else { return nil }
                }

                if !trimmedQuery.isEmpty && !entry.searchIndex.contains(trimmedQuery) {
                    return nil
                }

                return transaction
            }
            switch selectedSortOrder {
            case .newest:
                rebuiltTransactions = filteredTransactions
            case .oldest:
                rebuiltTransactions = Array(filteredTransactions.reversed())
            }
        }

        visibleTransactions = rebuiltTransactions
        visibleRows = rebuiltTransactions.map(historyRowPresentation)

        if resetPaging {
            currentPageIndex = 0
            pendingScrollToTopToken = UUID()
        } else if currentPageIndex != clampedPageIndex {
            currentPageIndex = clampedPageIndex
        }
    }

    private var historyPagingControls: some View {
        VStack(spacing: 12) {
            Text(localizedFormat("Page %lld", clampedPageIndex + 1))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.72))

            HStack(spacing: 12) {
                Button {
                    currentPageIndex = max(0, clampedPageIndex - 1)
                    pendingScrollToTopToken = UUID()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Last Page")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(clampedPageIndex == 0 || store.isLoadingMoreOnChainHistory)

                Button {
                    Task {
                        if hasNextLoadedPage {
                            currentPageIndex = clampedPageIndex + 1
                            pendingScrollToTopToken = UUID()
                            return
                        }

                        guard store.canLoadMoreOnChainHistory else { return }
                        let previousPageCount = totalLoadedPages
                        await store.loadMoreOnChainHistory()
                        if totalLoadedPages > previousPageCount {
                            currentPageIndex = min(clampedPageIndex + 1, totalLoadedPages - 1)
                            pendingScrollToTopToken = UUID()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.isLoadingMoreOnChainHistory {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(store.isLoadingMoreOnChainHistory ? "Loading..." : "Next Page")
                        if !store.isLoadingMoreOnChainHistory {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled((!hasNextLoadedPage && !store.canLoadMoreOnChainHistory) || store.isLoadingMoreOnChainHistory)
            }
        }
    }
    
    private var emptyStateTitle: String {
        store.normalizedHistoryIndex.isEmpty
            ? NSLocalizedString("No activity yet", comment: "")
            : NSLocalizedString("No matches found", comment: "")
    }
    
    private var emptyStateMessage: String {
        if store.wallets.isEmpty {
            return NSLocalizedString("No wallets are currently loaded. Import a wallet to view activity.", comment: "")
        }
        if store.normalizedHistoryIndex.isEmpty {
            return NSLocalizedString("Send funds or receive funds to build a persistent transaction log.", comment: "")
        }
        return NSLocalizedString("Try a different filter or search term.", comment: "")
    }

    private var selectedWalletName: String {
        guard let selectedWalletID,
              let wallet = store.wallet(for: selectedWalletID.uuidString) else {
            return NSLocalizedString("All Wallets", comment: "")
        }
        return wallet.name
    }
    
    @ViewBuilder
    private func transactionRow(_ row: HistoryRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoinBadge(assetIdentifier: row.transaction.assetIdentifier, fallbackText: row.transaction.symbol, color: row.transaction.badgeColor, size: 40)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.titleText)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(row.subtitleText)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    Text(row.statusText)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(row.transaction.statusColor.opacity(0.85), in: Capsule())
                    Text(row.fullTimestampText)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .multilineTextAlignment(.trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            
            if let amountText = row.amountText {
                Text(amountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .spectraNumericTextLayout()
            }

            if let dogecoinFeeText = row.dogecoinFeeText {
                Text(dogecoinFeeText)
                .font(.caption2)
                .foregroundStyle(Color.primary.opacity(0.62))
                .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private func filterCapsuleLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.62))
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.primary.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .spectraInputFieldStyle(cornerRadius: 16)
    }

    private func historyRowPresentation(for transaction: TransactionRecord) -> HistoryRowPresentation {
        HistoryRowPresentation(
            transaction: transaction,
            amountText: store.formattedTransactionAmount(transaction),
            titleText: transaction.titleText,
            subtitleText: transaction.subtitleText,
            statusText: transaction.statusText,
            fullTimestampText: transaction.fullTimestampText,
            dogecoinFeeText: dogecoinFeeText(for: transaction)
        )
    }

    private func dogecoinFeeText(for transaction: TransactionRecord) -> String? {
        guard transaction.chainName == "Dogecoin",
              transaction.kind == .send,
              let dogecoinFeePriorityRaw = transaction.dogecoinFeePriorityRaw,
              let dogecoinEstimatedFeeRateDOGEPerKB = transaction.dogecoinEstimatedFeeRateDOGEPerKB else {
            return nil
        }

        let changeOutputSuffix = (transaction.dogecoinUsedChangeOutput == false) ? " • no change output" : ""
        let confirmedFeeSuffix = transaction.dogecoinConfirmedNetworkFeeDOGE
            .map { String(format: " • confirmed %.6f", $0) } ?? ""
        let confirmationsSuffix = transaction.dogecoinConfirmations
            .map { " • \($0) conf" } ?? ""
        return String(
            format: "DOGE fee: %@ • %.4f DOGE/KB%@%@%@",
            dogecoinFeePriorityRaw.capitalized,
            dogecoinEstimatedFeeRateDOGEPerKB,
            changeOutputSuffix,
            confirmedFeeSuffix,
            confirmationsSuffix
        )
    }
}

private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String(format: format, locale: Locale.current, arguments: arguments)
}
