// MARK: - Wallet/transactions/address-book mutation helpers
//
// Swift's `@Observable` arrays on AppState are the canonical store. These
// helpers exist only to centralise mutation patterns (replace, append, upsert,
// remove) and keep call sites readable. There is no Rust round-trip — direct
// assignment to `self.wallets`, `self.transactions`, `self.addressBook` is
// fine, but going through these helpers preserves the existing call-site
// style.

import Foundation

@MainActor
extension AppState {
    // ── Wallets ────────────────────────────────────────────────────────
    func setWallets(_ new: [ImportedWallet]) {
        self.wallets = new
    }

    func appendWallets(_ new: [ImportedWallet]) {
        self.wallets.append(contentsOf: new)
    }

    func removeWallet(id: String) {
        self.wallets.removeAll { $0.id == id }
    }

    // ── Transactions ──────────────────────────────────────────────────
    func setTransactions(_ new: [TransactionRecord]) {
        self.transactions = new
    }

    func prependTransaction(_ transaction: TransactionRecord) {
        self.transactions.insert(transaction, at: 0)
    }

    func removeTransactions(forWalletID walletID: String) {
        self.transactions.removeAll { $0.walletID == walletID }
    }

    // ── Address book ─────────────────────────────────────────────────
    func setAddressBook(_ new: [AddressBookEntry]) {
        self.addressBook = new
    }

    func prependAddressBookEntry(_ entry: AddressBookEntry) {
        self.addressBook.insert(entry, at: 0)
    }

    func removeAddressBookEntry(byID uuid: UUID) {
        self.addressBook.removeAll { $0.id == uuid }
    }
}
