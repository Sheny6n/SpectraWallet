import Foundation
import Combine

final class WalletTransactionState: ObservableObject {
    @Published var transactions: [TransactionRecord] = []
    @Published var normalizedHistoryIndex: [NormalizedHistoryEntry] = []
    var cachedTransactionByID: [UUID: TransactionRecord] = [:]
    var suppressSideEffects = false
    var lastObservedTransactions: [TransactionRecord] = []
}
