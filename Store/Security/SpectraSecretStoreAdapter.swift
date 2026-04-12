import Foundation

/// Swift implementation of the UniFFI `SecretStore` callback trait.
///
/// Rust calls through this adapter whenever it needs to read or write a secret.
/// Key routing:
///   - `"wallet.seed.*"`        → `SecureSeedStore`      (AES-GCM encrypted)
///   - `"wallet.privatekey.*"`  → `SecurePrivateKeyStore` (raw hex)
///   - everything else          → `SecureStore`           (generic secure values)
///
/// Call `SpectraSecretStoreAdapter.registerWithBridge()` once at app start
/// (after `WalletServiceBridge` is ready) to wire this into the Rust layer.
final class SpectraSecretStoreAdapter: SecretStoreImpl {

    // MARK: - Registration

    /// Register this adapter with the Rust `WalletService`. Safe to call multiple
    /// times — subsequent calls are no-ops because the actor holds a reference.
    static func registerWithBridge() {
        let adapter = SpectraSecretStoreAdapter(noPointer: .init())
        Task {
            try? await WalletServiceBridge.shared.registerSecretStore(adapter)
        }
    }

    // MARK: - SecretStore protocol

    override func loadSecret(key: String) -> String? {
        if key.hasPrefix("wallet.seed.") {
            return try? SecureSeedStore.loadValue(for: key)
        } else if key.hasPrefix("wallet.privatekey.") {
            let value = SecurePrivateKeyStore.loadValue(for: key)
            return value.isEmpty ? nil : value
        } else {
            let value = SecureStore.loadValue(for: key)
            return value.isEmpty ? nil : value
        }
    }

    override func saveSecret(key: String, value: String) -> Bool {
        if key.hasPrefix("wallet.seed.") {
            return (try? SecureSeedStore.save(value, for: key)) != nil
        } else if key.hasPrefix("wallet.privatekey.") {
            SecurePrivateKeyStore.save(value, for: key)
            return true
        } else {
            SecureStore.save(value, for: key)
            return true
        }
    }

    override func deleteSecret(key: String) -> Bool {
        if key.hasPrefix("wallet.seed.") {
            return (try? SecureSeedStore.deleteValue(for: key)) != nil
        } else if key.hasPrefix("wallet.privatekey.") {
            SecurePrivateKeyStore.deleteValue(for: key)
            return true
        } else {
            SecureStore.deleteValue(for: key)
            return true
        }
    }

    /// Enumerate all keys matching `prefixFilter` across all Keychain services.
    /// Uses `KeychainAccess` allKeys() where available; returns empty on error.
    override func listKeys(prefixFilter: String) -> [String] {
        // KeychainAccess doesn't expose a cross-service key listing in a single call,
        // so we check each service independently.
        var results: [String] = []

        if prefixFilter.isEmpty || prefixFilter.hasPrefix("wallet.seed.") {
            // Seed keys are opaque blobs — we don't enumerate them by default for
            // security. Rust only asks for specific keys it already knows about.
        }
        if prefixFilter.isEmpty || prefixFilter.hasPrefix("wallet.privatekey.") {
            // Same — private key keys are specific by wallet ID.
        }
        // For generic SecureStore keys (API keys, etc.) we can list by prefix
        // if needed. Currently returns empty — Rust doesn't enumerate these yet.
        return results
    }
}
