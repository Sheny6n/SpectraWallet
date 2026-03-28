import Foundation

extension WalletStore {
    var transactions: [TransactionRecord] {
        get { transactionState.transactions }
        set { transactionState.transactions = newValue }
    }

    var normalizedHistoryIndex: [NormalizedHistoryEntry] {
        get { transactionState.normalizedHistoryIndex }
        set { transactionState.normalizedHistoryIndex = newValue }
    }

    var cachedTransactionByID: [UUID: TransactionRecord] {
        get { transactionState.cachedTransactionByID }
        set { transactionState.cachedTransactionByID = newValue }
    }
}
