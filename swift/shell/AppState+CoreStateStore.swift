// MARK: - Rust-owned core-state helpers
//
// Canonical storage for `wallets`, `transactions`, and `addressBook` lives in
// Rust (`core/src/app_state/store.rs`). The `@Published` arrays on `AppState`
// are *mirrors* that exist only so SwiftUI views can observe them via
// `appState.$wallets` etc.
//
// Every mutation MUST go through the helpers in this file. They:
//   1. Call the corresponding `store*` UniFFI function so Rust stays canonical.
//   2. Update the `@Published` mirror so SwiftUI refreshes.
//
// Do NOT write `self.wallets = …`, `self.wallets.append(…)`, etc. directly
// anywhere else. Use `setWallets(_:)`, `appendWallet(_:)`, `upsertWallet(_:)`,
// `removeWallet(id:)`, `removeWallets(where:)`, and the analogous transactions
// / addressBook helpers instead. Grep for direct assignments will show only
// the didSet-driven internals inside this file and `AppState.swift`.
//
// `transactions` and `addressBook` round-trip through their
// `persistedSnapshot` / `init(snapshot:)` bridges, which is what the Rust
// store natively holds (`CorePersistedTransactionRecord`,
// `CorePersistedAddressBookEntry`). Records that fail to round-trip
// (`init?(snapshot:)` returns nil) are silently dropped on read — same
// behaviour the existing persistence layer has.

import Foundation

@MainActor
extension AppState {
    // ── Wallets ────────────────────────────────────────────────────────
    func setWallets(_ new: [ImportedWallet]) {
        storeWalletsReplaceAll(wallets: new)
        self.wallets = new
    }

    func appendWallet(_ wallet: ImportedWallet) {
        storeWalletsAppend(wallet: wallet)
        self.wallets.append(wallet)
    }

    func appendWallets(_ new: [ImportedWallet]) {
        storeWalletsAppendMany(wallets: new)
        self.wallets.append(contentsOf: new)
    }

    /// Insert or replace by `id`. Preserves position when updating.
    func upsertWallet(_ wallet: ImportedWallet) {
        storeWalletsUpsert(wallet: wallet)
        if let idx = self.wallets.firstIndex(where: { $0.id == wallet.id }) {
            self.wallets[idx] = wallet
        } else {
            self.wallets.append(wallet)
        }
    }

    func removeWallet(id: String) {
        storeWalletsRemove(id: id)
        self.wallets.removeAll { $0.id == id }
    }

    func removeWallets(where predicate: (ImportedWallet) -> Bool) {
        let next = self.wallets.filter { !predicate($0) }
        setWallets(next)
    }

    // ── Transactions ──────────────────────────────────────────────────
    func setTransactions(_ new: [TransactionRecord]) {
        storeTransactionsReplaceAll(transactions: new.map(\.persistedSnapshot))
        self.transactions = new
    }

    func prependTransaction(_ transaction: TransactionRecord) {
        storeTransactionsPrepend(transaction: transaction.persistedSnapshot)
        self.transactions.insert(transaction, at: 0)
    }

    func removeTransactions(forWalletID walletID: String) {
        storeTransactionsRemoveForWallet(walletId: walletID)
        self.transactions.removeAll { $0.walletID == walletID }
    }

    func mapTransactions(_ transform: (TransactionRecord) -> TransactionRecord) {
        setTransactions(self.transactions.map(transform))
    }

    // ── Address book ─────────────────────────────────────────────────
    func setAddressBook(_ new: [AddressBookEntry]) {
        storeAddressBookReplaceAll(entries: new.map(\.persistedSnapshot))
        self.addressBook = new
    }

    func prependAddressBookEntry(_ entry: AddressBookEntry) {
        storeAddressBookPrepend(entry: entry.persistedSnapshot)
        self.addressBook.insert(entry, at: 0)
    }

    func removeAddressBookEntry(byID uuid: UUID) {
        storeAddressBookRemove(id: uuid.uuidString)
        self.addressBook.removeAll { $0.id == uuid }
    }
}
