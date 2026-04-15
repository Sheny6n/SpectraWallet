import Foundation
final class SpectraSecretStoreAdapter: SecretStoreImpl {
    static func registerWithBridge() {
        let adapter = SpectraSecretStoreAdapter(noPointer: .init())
        Task {
            try? await WalletServiceBridge.shared.registerSecretStore(adapter)
        }}
    override func loadSecret(key: String) -> String? {
        if key.hasPrefix("wallet.seed.") { return try? SecureSeedStore.loadValue(for: key) } else if key.hasPrefix("wallet.privatekey.") {
            let value = SecurePrivateKeyStore.loadValue(for: key)
            return value.isEmpty ? nil : value
        } else {
            let value = SecureStore.loadValue(for: key)
            return value.isEmpty ? nil : value
        }}
    override func saveSecret(key: String, value: String) -> Bool {
        if key.hasPrefix("wallet.seed.") { return (try? SecureSeedStore.save(value, for: key)) != nil } else if key.hasPrefix("wallet.privatekey.") {
            SecurePrivateKeyStore.save(value, for: key)
            return true
        } else {
            SecureStore.save(value, for: key)
            return true
        }}
    override func deleteSecret(key: String) -> Bool {
        if key.hasPrefix("wallet.seed.") { return (try? SecureSeedStore.deleteValue(for: key)) != nil } else if key.hasPrefix("wallet.privatekey.") {
            SecurePrivateKeyStore.deleteValue(for: key)
            return true
        } else {
            SecureStore.deleteValue(for: key)
            return true
        }}
    override func listKeys(prefixFilter: String) -> [String] {
        var results: [String] = []
        if prefixFilter.isEmpty || prefixFilter.hasPrefix("wallet.seed.") {
        }
        if prefixFilter.isEmpty || prefixFilter.hasPrefix("wallet.privatekey.") {
        }
        return results
    }
}
