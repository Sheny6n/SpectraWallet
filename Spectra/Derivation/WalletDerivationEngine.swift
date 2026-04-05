import Foundation
import WalletCore

struct WalletDerivationRequestedOutputs: OptionSet {
    let rawValue: Int

    static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
}

enum WalletDerivationCurve: String, Codable {
    case secp256k1
    case ed25519
}

enum WalletDerivationNetwork: String, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet
}

private struct WalletDerivationQuery {
    let chain: SeedDerivationChain
    let network: WalletDerivationNetwork
    let derivationPath: String?
    let curve: WalletDerivationCurve
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: WalletDerivationRequestedOutputs

    init(
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork,
        derivationPath: String?,
        curve: WalletDerivationCurve,
        passphrase: String? = nil,
        iterationCount: Int? = nil,
        hmacKeyString: String? = nil,
        requestedOutputs: WalletDerivationRequestedOutputs = .all
    ) {
        self.chain = chain
        self.network = network
        self.derivationPath = derivationPath
        self.curve = curve
        self.passphrase = passphrase
        self.iterationCount = iterationCount
        self.hmacKeyString = hmacKeyString
        self.requestedOutputs = requestedOutputs
    }
}

struct WalletDerivationResult {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}

private struct WalletDerivationJSONRequestPayload: Codable {
    let chain: SeedDerivationChain
    let network: WalletDerivationNetwork
    let seedPhrase: String
    let derivationPath: String?
    let curve: WalletDerivationCurve
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: [String]

    var query: WalletDerivationQuery {
        WalletDerivationQuery(
            chain: chain,
            network: network,
            derivationPath: derivationPath,
            curve: curve,
            passphrase: passphrase,
            iterationCount: iterationCount,
            hmacKeyString: hmacKeyString,
            requestedOutputs: WalletDerivationRequestedOutputs(jsonValues: requestedOutputs)
        )
    }
}

private struct WalletDerivationJSONResponsePayload: Codable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}

enum WalletDerivationEngineError: LocalizedError {
    case emptyRequestedOutputs
    case unsupportedNetwork(chain: SeedDerivationChain, network: WalletDerivationNetwork)
    case unsupportedAddressCurve(chain: SeedDerivationChain, expected: WalletDerivationCurve, provided: WalletDerivationCurve)
    case unsupportedIterationCount(Int)
    case unsupportedHMACKeyString(String)
    case unsupportedBitcoinPurpose(String)
    case invalidJSONRequest

    var errorDescription: String? {
        switch self {
        case .emptyRequestedOutputs:
            return "At least one derivation output must be requested."
        case .unsupportedNetwork(let chain, let network):
            return "\(network.rawValue) is not supported for \(chain.rawValue)."
        case .unsupportedAddressCurve(let chain, let expected, let provided):
            return "\(chain.rawValue) addresses require \(expected.rawValue), not \(provided.rawValue)."
        case .unsupportedIterationCount(let count):
            return "Custom iteration count \(count) is not supported by the current derivation engine."
        case .unsupportedHMACKeyString(let key):
            return "Custom HMAC key string '\(key)' is not supported by the current derivation engine."
        case .unsupportedBitcoinPurpose(let path):
            return "Unsupported Bitcoin derivation purpose for path \(path)."
        case .invalidJSONRequest:
            return "Invalid derivation JSON request."
        }
    }
}

enum WalletDerivationEngine {
    static func derive(jsonData: Data) throws -> Data {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(WalletDerivationJSONRequestPayload.self, from: jsonData)
        let result = try derive(seedPhrase: payload.seedPhrase, query: payload.query)
        return try JSONEncoder().encode(
            WalletDerivationJSONResponsePayload(
                address: result.address,
                publicKeyHex: result.publicKeyHex,
                privateKeyHex: result.privateKeyHex
            )
        )
    }

    static func derive(
        jsonString: String
    ) throws -> String {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw WalletDerivationEngineError.invalidJSONRequest
        }
        let responseData = try derive(jsonData: jsonData)
        guard let responseString = String(data: responseData, encoding: .utf8) else {
            throw WalletDerivationEngineError.invalidJSONRequest
        }
        return responseString
    }

    private static func derive(
        seedPhrase: String,
        query: WalletDerivationQuery
    ) throws -> WalletDerivationResult {
        guard !query.requestedOutputs.isEmpty else {
            throw WalletDerivationEngineError.emptyRequestedOutputs
        }

        try validateAdvancedOptions(query)

        let expectedCurve = curve(for: query.chain)
        try validate(network: query.network, for: query.chain)

        let chainMaterial = try SeedPhraseSigningMaterial.material(
            seedPhrase: seedPhrase,
            coin: walletCoreCoin(for: query.chain),
            derivationPath: query.derivationPath,
            passphrase: query.passphrase
        )

        let signingMaterial: WalletCoreDerivationMaterial
        if query.curve == expectedCurve {
            signingMaterial = chainMaterial
        } else {
            signingMaterial = try SeedPhraseSigningMaterial.material(
                seedPhrase: seedPhrase,
                coin: representativeCoin(for: query.curve),
                derivationPath: query.derivationPath,
                passphrase: query.passphrase
            )
        }

        let address: String?
        if query.requestedOutputs.contains(.address) {
            guard query.curve == expectedCurve else {
                throw WalletDerivationEngineError.unsupportedAddressCurve(
                    chain: query.chain,
                    expected: expectedCurve,
                    provided: query.curve
                )
            }
            address = try deriveAddress(
                chain: query.chain,
                network: query.network,
                derivationPath: query.derivationPath,
                material: chainMaterial
            )
        } else {
            address = nil
        }

        let publicKeyHex: String? = if query.requestedOutputs.contains(.publicKey) {
            hexString(
                try derivePublicKeyData(
                    curve: query.curve,
                    privateKeyData: signingMaterial.privateKeyData
                )
            )
        } else {
            nil
        }

        let privateKeyHex: String? = if query.requestedOutputs.contains(.privateKey) {
            hexString(signingMaterial.privateKeyData)
        } else {
            nil
        }

        return WalletDerivationResult(
            address: address,
            publicKeyHex: publicKeyHex,
            privateKeyHex: privateKeyHex
        )
    }

    static func curve(for chain: SeedDerivationChain) -> WalletDerivationCurve {
        switch chain {
        case .bitcoin,
             .bitcoinCash,
             .bitcoinSV,
             .litecoin,
             .dogecoin,
             .ethereum,
             .ethereumClassic,
             .arbitrum,
             .optimism,
             .avalanche,
             .hyperliquid,
             .tron,
             .xrp:
            return .secp256k1
        case .solana,
             .stellar,
             .cardano,
             .sui,
             .aptos,
             .ton,
             .internetComputer,
             .near,
             .polkadot:
            return .ed25519
        }
    }

    private static func validate(
        network: WalletDerivationNetwork,
        for chain: SeedDerivationChain
    ) throws {
        switch chain {
        case .bitcoin:
            return
        case .dogecoin:
            guard network == .mainnet || network == .testnet else {
                throw WalletDerivationEngineError.unsupportedNetwork(chain: chain, network: network)
            }
        case .bitcoinCash,
             .bitcoinSV,
             .litecoin,
             .ethereum,
             .ethereumClassic,
             .arbitrum,
             .optimism,
             .avalanche,
             .hyperliquid,
             .tron,
             .solana,
             .stellar,
             .xrp,
             .cardano,
             .sui,
             .aptos,
             .ton,
             .internetComputer,
             .near,
             .polkadot:
            guard network == .mainnet else {
                throw WalletDerivationEngineError.unsupportedNetwork(chain: chain, network: network)
            }
        }
    }

    private static func deriveAddress(
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork,
        derivationPath: String?,
        material: WalletCoreDerivationMaterial
    ) throws -> String {
        switch chain {
        case .bitcoin:
            return try deriveBitcoinAddress(
                privateKeyData: material.privateKeyData,
                derivationPath: derivationPath,
                network: network
            )
        case .dogecoin:
            return try UTXOAddressCodec.legacyP2PKHAddress(
                privateKeyData: material.privateKeyData,
                version: dogecoinP2PKHVersion(for: network)
            )
        case .ethereum, .arbitrum, .optimism, .ethereumClassic, .avalanche, .hyperliquid:
            return material.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        case .tron:
            return material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        case .stellar, .ton, .solana, .bitcoinCash, .bitcoinSV, .litecoin, .xrp, .cardano, .polkadot:
            return material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        case .sui, .aptos, .internetComputer, .near:
            return material.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func deriveBitcoinAddress(
        privateKeyData: Data,
        derivationPath: String?,
        network: WalletDerivationNetwork
    ) throws -> String {
        let purpose = derivationPath.flatMap { DerivationPathParser.segmentValue(at: 0, in: $0) } ?? 44
        switch purpose {
        case 44:
            return try UTXOAddressCodec.legacyP2PKHAddress(
                privateKeyData: privateKeyData,
                version: bitcoinLegacyP2PKHVersion(for: network)
            )
        case 49:
            return try UTXOAddressCodec.nestedSegWitP2SHAddress(
                privateKeyData: privateKeyData,
                scriptVersion: bitcoinP2SHVersion(for: network)
            )
        case 84:
            return try UTXOAddressCodec.segWitAddress(
                privateKeyData: privateKeyData,
                hrp: bitcoinBech32HRP(for: network),
                witnessVersion: 0,
                encoding: .bech32
            )
        default:
            throw WalletDerivationEngineError.unsupportedBitcoinPurpose(derivationPath ?? "m")
        }
    }

    private static func derivePublicKeyData(
        curve: WalletDerivationCurve,
        privateKeyData: Data
    ) throws -> Data {
        guard let privateKey = PrivateKey(data: privateKeyData) else {
            throw WalletCoreDerivationError.invalidPrivateKey
        }

        switch curve {
        case .secp256k1:
            return privateKey.getPublicKeySecp256k1(compressed: true).data
        case .ed25519:
            return privateKey.getPublicKeyEd25519().data
        }
    }

    private static func walletCoreCoin(for chain: SeedDerivationChain) -> WalletCoreSupportedCoin {
        switch chain {
        case .bitcoin:
            return .bitcoin
        case .bitcoinCash:
            return .bitcoinCash
        case .bitcoinSV:
            return .bitcoinSV
        case .litecoin:
            return .litecoin
        case .dogecoin:
            return .dogecoin
        case .ethereum, .ethereumClassic, .arbitrum, .optimism, .avalanche, .hyperliquid:
            return .ethereum
        case .tron:
            return .tron
        case .solana:
            return .solana
        case .stellar:
            return .stellar
        case .xrp:
            return .xrp
        case .cardano:
            return .cardano
        case .sui:
            return .sui
        case .aptos:
            return .aptos
        case .ton:
            return .ton
        case .internetComputer:
            return .internetComputer
        case .near:
            return .near
        case .polkadot:
            return .polkadot
        }
    }

    private static func representativeCoin(for curve: WalletDerivationCurve) -> WalletCoreSupportedCoin {
        switch curve {
        case .secp256k1:
            return .bitcoin
        case .ed25519:
            return .solana
        }
    }

    private static func bitcoinBech32HRP(for network: WalletDerivationNetwork) -> String {
        switch network {
        case .mainnet:
            return "bc"
        case .testnet, .testnet4, .signet:
            return "tb"
        }
    }

    private static func bitcoinLegacyP2PKHVersion(for network: WalletDerivationNetwork) -> UInt8 {
        switch network {
        case .mainnet:
            return 0x00
        case .testnet, .testnet4, .signet:
            return 0x6f
        }
    }

    private static func bitcoinP2SHVersion(for network: WalletDerivationNetwork) -> UInt8 {
        switch network {
        case .mainnet:
            return 0x05
        case .testnet, .testnet4, .signet:
            return 0xc4
        }
    }

    private static func dogecoinP2PKHVersion(for network: WalletDerivationNetwork) -> UInt8 {
        switch network {
        case .mainnet:
            return 0x1e
        case .testnet:
            return 0x71
        case .testnet4, .signet:
            return 0x71
        }
    }

    fileprivate static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func validateAdvancedOptions(_ query: WalletDerivationQuery) throws {
        if let iterationCount = query.iterationCount, iterationCount != 2048 {
            throw WalletDerivationEngineError.unsupportedIterationCount(iterationCount)
        }
        if let hmacKeyString = query.hmacKeyString?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !hmacKeyString.isEmpty {
            throw WalletDerivationEngineError.unsupportedHMACKeyString(hmacKeyString)
        }
    }
}
