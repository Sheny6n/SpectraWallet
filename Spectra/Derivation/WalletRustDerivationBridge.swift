import Foundation

enum WalletRustDerivationBridgeError: LocalizedError {
    case rustCoreNotLinked
    case rustCoreBitcoinOnly

    var errorDescription: String? {
        switch self {
        case .rustCoreNotLinked:
            return "The Rust derivation core is not linked yet."
        case .rustCoreBitcoinOnly:
            return "The Rust derivation core currently supports only Bitcoin."
        }
    }
}

enum WalletRustFFIChain: UInt32 {
    case bitcoin = 0
    case ethereum = 1
    case solana = 2
}

enum WalletRustFFINetwork: UInt32 {
    case mainnet = 0
    case testnet = 1
    case testnet4 = 2
    case signet = 3
}

enum WalletRustFFICurve: UInt32 {
    case secp256k1 = 0
    case ed25519 = 1
}

struct WalletRustFFIRequestedOutputs: OptionSet {
    let rawValue: UInt32

    static let address = WalletRustFFIRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletRustFFIRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletRustFFIRequestedOutputs(rawValue: 1 << 2)
}

enum WalletRustFFIDerivationAlgorithm: UInt32 {
    case auto = 0
    case bip32Secp256k1 = 1
    case slip10Ed25519 = 2
}

enum WalletRustFFIAddressAlgorithm: UInt32 {
    case auto = 0
    case bitcoin = 1
    case evm = 2
    case solana = 3
}

enum WalletRustFFIPublicKeyFormat: UInt32 {
    case auto = 0
    case compressed = 1
    case uncompressed = 2
    case xOnly = 3
    case raw = 4
}

enum WalletRustFFIScriptType: UInt32 {
    case auto = 0
    case p2pkh = 1
    case p2shP2wpkh = 2
    case p2wpkh = 3
    case p2tr = 4
    case account = 5
}

struct WalletRustDerivationRequestModel {
    let chain: WalletRustFFIChain
    let network: WalletRustFFINetwork
    let curve: WalletRustFFICurve
    let requestedOutputs: WalletRustFFIRequestedOutputs
    let derivationAlgorithm: WalletRustFFIDerivationAlgorithm
    let addressAlgorithm: WalletRustFFIAddressAlgorithm
    let publicKeyFormat: WalletRustFFIPublicKeyFormat
    let scriptType: WalletRustFFIScriptType
    let seedPhrase: String
    let derivationPath: String?
    let passphrase: String?
    let hmacKey: String?
    let mnemonicWordlist: String?
    let iterationCount: UInt32
}

extension WalletRustFFIChain {
    init?(chain: SeedDerivationChain) {
        switch chain {
        case .bitcoin:
            self = .bitcoin
        case .ethereum:
            self = .ethereum
        case .solana:
            self = .solana
        default:
            return nil
        }
    }
}

extension WalletRustFFINetwork {
    init(network: WalletDerivationNetwork) {
        switch network {
        case .mainnet:
            self = .mainnet
        case .testnet:
            self = .testnet
        case .testnet4:
            self = .testnet4
        case .signet:
            self = .signet
        }
    }
}

extension WalletRustFFICurve {
    init(curve: WalletDerivationCurve) {
        switch curve {
        case .secp256k1:
            self = .secp256k1
        case .ed25519:
            self = .ed25519
        }
    }
}

extension WalletRustFFIRequestedOutputs {
    init(outputs: WalletDerivationRequestedOutputs) {
        var value: WalletRustFFIRequestedOutputs = []
        if outputs.contains(.address) {
            value.insert(.address)
        }
        if outputs.contains(.publicKey) {
            value.insert(.publicKey)
        }
        if outputs.contains(.privateKey) {
            value.insert(.privateKey)
        }
        self = value
    }
}

enum WalletRustDerivationBridge {
    static var isAvailable: Bool {
        false
    }

    static func makeRequestModel(
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork,
        seedPhrase: String,
        derivationPath: String?,
        curve: WalletDerivationCurve,
        passphrase: String?,
        iterationCount: Int?,
        hmacKeyString: String?,
        requestedOutputs: WalletDerivationRequestedOutputs
    ) throws -> WalletRustDerivationRequestModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustDerivationBridgeError.rustCoreBitcoinOnly
        }

        return WalletRustDerivationRequestModel(
            chain: ffiChain,
            network: WalletRustFFINetwork(network: network),
            curve: WalletRustFFICurve(curve: curve),
            requestedOutputs: WalletRustFFIRequestedOutputs(outputs: requestedOutputs),
            derivationAlgorithm: defaultDerivationAlgorithm(for: ffiChain),
            addressAlgorithm: defaultAddressAlgorithm(for: ffiChain),
            publicKeyFormat: defaultPublicKeyFormat(for: ffiChain),
            scriptType: defaultScriptType(for: ffiChain, derivationPath: derivationPath),
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: passphrase,
            hmacKey: hmacKeyString,
            mnemonicWordlist: "english",
            iterationCount: UInt32(iterationCount ?? 2048)
        )
    }

    static func derivePlaceholder() throws -> Never {
        throw WalletRustDerivationBridgeError.rustCoreNotLinked
    }

    private static func defaultDerivationAlgorithm(
        for chain: WalletRustFFIChain
    ) -> WalletRustFFIDerivationAlgorithm {
        switch chain {
        case .bitcoin, .ethereum:
            return .bip32Secp256k1
        case .solana:
            return .slip10Ed25519
        }
    }

    private static func defaultAddressAlgorithm(
        for chain: WalletRustFFIChain
    ) -> WalletRustFFIAddressAlgorithm {
        switch chain {
        case .bitcoin:
            return .bitcoin
        case .ethereum:
            return .evm
        case .solana:
            return .solana
        }
    }

    private static func defaultPublicKeyFormat(
        for chain: WalletRustFFIChain
    ) -> WalletRustFFIPublicKeyFormat {
        switch chain {
        case .bitcoin, .ethereum:
            return .compressed
        case .solana:
            return .raw
        }
    }

    private static func defaultScriptType(
        for chain: WalletRustFFIChain,
        derivationPath: String?
    ) -> WalletRustFFIScriptType {
        switch chain {
        case .bitcoin:
            let purpose = derivationPath
                .flatMap { DerivationPathParser.segmentValue(at: 0, in: $0) } ?? 84
            switch purpose {
            case 44:
                return .p2pkh
            case 49:
                return .p2shP2wpkh
            case 84:
                return .p2wpkh
            case 86:
                return .p2tr
            default:
                return .auto
            }
        case .ethereum, .solana:
            return .account
        }
    }
}
