import Foundation
extension WalletStore {
    @discardableResult
    func applyIndexedWalletHoldingUpdates(
        _ updates: [(index: Int, holdings: [Coin])], to walletSnapshot: [ImportedWallet]
    ) -> Bool {
        guard !updates.isEmpty else { return false }
        var updatedWallets = walletSnapshot
        var changed = false
        for update in updates {
            guard updatedWallets.indices.contains(update.index) else { continue }
            let existingWallet = updatedWallets[update.index]
            guard !walletHoldingSnapshotsMatch(existingWallet.holdings, update.holdings) else { continue }
            updatedWallets[update.index] = walletByReplacingHoldings(existingWallet, with: update.holdings)
            changed = true
        }
        if changed { wallets = updatedWallets }
        return changed
    }
    private func walletHoldingSnapshotsMatch(_ lhs: [Coin], _ rhs: [Coin]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.name == right.name, left.symbol == right.symbol, left.marketDataID == right.marketDataID, left.coinGeckoID == right.coinGeckoID, left.chainName == right.chainName, left.tokenStandard == right.tokenStandard, left.contractAddress == right.contractAddress, abs(left.amount - right.amount) < 0.0000000001, abs(left.priceUSD - right.priceUSD) < 0.0000000001, left.mark == right.mark else { return false }}
        return true
    }
    func firstActivityDate(for walletID: UUID) -> Date? { cachedFirstActivityDateByWalletID[walletID] }
    @discardableResult
    func setTransactionsIfChanged(_ newTransactions: [TransactionRecord]) -> Bool {
        guard !transactionSnapshotsMatch(transactions, newTransactions) else { return false }
        transactions = newTransactions
        return true
    }
    private func transactionSnapshotsMatch(_ lhs: [TransactionRecord], _ rhs: [TransactionRecord]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.persistedSnapshot == $1.persistedSnapshot }
    }
}
