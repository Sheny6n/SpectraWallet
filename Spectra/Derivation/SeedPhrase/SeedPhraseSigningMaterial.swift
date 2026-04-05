import Foundation
import WalletCore

enum SeedPhraseSigningMaterial {
    struct SolanaKeyMaterial {
        let address: String
        let privateKeyData: Data
        let derivationPath: String
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String
    ) throws -> WalletCoreDerivationMaterial {
        try material(
            seedPhrase: seedPhrase,
            coin: coin,
            derivationPath: Optional(derivationPath),
            passphrase: nil
        )
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String?,
        passphrase: String?
    ) throws -> WalletCoreDerivationMaterial {
        try WalletCoreDerivation.deriveMaterial(
            seedPhrase: SeedPhraseSafety.normalizedPhrase(from: seedPhrase),
            coin: coin,
            derivationPath: derivationPath,
            passphrase: passphrase
        )
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        account: UInt32
    ) throws -> WalletCoreDerivationMaterial {
        try WalletCoreDerivation.deriveMaterial(
            seedPhrase: SeedPhraseSafety.normalizedPhrase(from: seedPhrase),
            coin: coin,
            account: account
        )
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        account: UInt32,
        branch: WalletDerivationBranch,
        index: UInt32
    ) throws -> WalletCoreDerivationMaterial {
        try WalletCoreDerivation.deriveMaterial(
            seedPhrase: SeedPhraseSafety.normalizedPhrase(from: seedPhrase),
            coin: coin,
            account: account,
            branch: branch,
            index: index
        )
    }

    static func material(
        privateKeyHex: String,
        coin: WalletCoreSupportedCoin
    ) throws -> WalletCoreDerivationMaterial {
        try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: coin)
    }

    static func resolvedSolanaKeyMaterial(
        seedPhrase: String,
        ownerAddress: String?,
        preferredDerivationPath: String? = nil,
        account: UInt32 = 0
    ) throws -> SolanaKeyMaterial {
        let normalizedMnemonic = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)
        guard let wallet = HDWallet(mnemonic: normalizedMnemonic, passphrase: "") else {
            throw WalletCoreDerivationError.invalidMnemonic
        }

        let normalizedOwner = ownerAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let accountScopedPaths = [
            "m/44'/501'/\(account)'/0'",
            "m/44'/501'/\(account)'"
        ]
        let derivationPathsToTry: [String] = {
            guard let preferredDerivationPath else { return accountScopedPaths }
            var ordered = [preferredDerivationPath]
            for path in accountScopedPaths where path != preferredDerivationPath {
                ordered.append(path)
            }
            return ordered
        }()

        var firstValid: SolanaKeyMaterial?
        for path in derivationPathsToTry {
            let key = wallet.getKey(coin: .solana, derivationPath: path)
            let address = CoinType.solana.deriveAddress(privateKey: key)
            guard AddressValidation.isValidSolanaAddress(address) else { continue }
            let candidate = SolanaKeyMaterial(
                address: address,
                privateKeyData: key.data,
                derivationPath: path
            )
            if firstValid == nil {
                firstValid = candidate
            }
            if let normalizedOwner, address.lowercased() == normalizedOwner {
                return candidate
            }
        }

        if let firstValid, normalizedOwner == nil {
            return firstValid
        }
        if let firstValid, let normalizedOwner, firstValid.address.lowercased() == normalizedOwner {
            return firstValid
        }

        throw WalletCoreDerivationError.invalidMnemonic
    }
}
