import Foundation

enum WalletRustDerivationBridgeError: LocalizedError {
    case unsupportedChain(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let chain): return "Derivation is not yet available for \(chain)."
        }
    }
}

enum WalletRustDerivationBridge {
    static var isAvailable: Bool { true }

    // MARK: — Seed-phrase derive

    static func derive(
        chain: SeedDerivationChain,
        seedPhrase: String,
        derivationPath: String?,
        passphrase: String?,
        hmacKey: String?,
        scriptType: BitcoinScriptType? = nil,
        wantAddress: Bool,
        wantPublicKey: Bool,
        wantPrivateKey: Bool
    ) throws -> WalletRustDerivationResponseModel {
        let path = derivationPath ?? CachedCoreHelpers.chainDerivationPath(chainName: chain.rawValue)
        let result = try dispatch(
            chain: chain, seedPhrase: seedPhrase, path: path,
            passphrase: passphrase?.nonEmpty, hmacKey: hmacKey?.nonEmpty,
            scriptType: scriptType ?? bitcoinScriptType(from: path),
            wa: wantAddress, wp: wantPublicKey, wk: wantPrivateKey
        )
        return WalletRustDerivationResponseModel(
            address: result.address, publicKeyHex: result.publicKeyHex, privateKeyHex: result.privateKeyHex)
    }

    // MARK: — Private-key derive (EVM + UTXO chains that have Rust helpers)

    static func deriveFromPrivateKey(
        chain: SeedDerivationChain, privateKeyHex: String
    ) throws -> WalletRustDerivationResponseModel {
        let result: DerivationResult
        switch chain {
        case .ethereum, .arbitrum, .optimism, .avalanche, .base, .polygon, .hyperliquid,
             .linea, .scroll, .blast, .mantle, .sei, .celo, .cronos, .opBNB, .zkSyncEra,
             .sonic, .berachain, .unichain, .ink, .xLayer,
             .ethereumClassic, .ethereumSepolia, .ethereumHoodi, .arbitrumSepolia,
             .optimismSepolia, .baseSepolia, .bnbChainTestnet, .avalancheFuji, .polygonAmoy,
             .hyperliquidTestnet, .ethereumClassicMordor:
            result = try deriveEvmFromPrivateKey(privateKeyHex: privateKeyHex, wantAddress: true, wantPublicKey: false)
        case .bitcoin, .bitcoinTestnet, .bitcoinTestnet4, .bitcoinSignet:
            result = try deriveBitcoinFromPrivateKey(
                privateKeyHex: privateKeyHex, scriptType: .p2wpkh, wantAddress: true, wantPublicKey: false)
        case .bitcoinCash, .bitcoinCashTestnet:
            result = try deriveBitcoinCashFromPrivateKey(
                privateKeyHex: privateKeyHex, wantAddress: true, wantPublicKey: false)
        case .bitcoinSV, .bitcoinSVTestnet:
            return WalletRustDerivationResponseModel(address: nil, publicKeyHex: nil, privateKeyHex: nil)
        case .litecoin, .litecoinTestnet:
            result = try deriveLitecoinFromPrivateKey(
                privateKeyHex: privateKeyHex, wantAddress: true, wantPublicKey: false)
        case .dogecoin, .dogecoinTestnet:
            result = try deriveDogecoinFromPrivateKey(
                privateKeyHex: privateKeyHex, wantAddress: true, wantPublicKey: false)
        case .decred, .decredTestnet:
            result = try deriveDecredFromPrivateKey(
                privateKeyHex: privateKeyHex, wantAddress: true, wantPublicKey: false)
        default:
            return WalletRustDerivationResponseModel(address: nil, publicKeyHex: nil, privateKeyHex: nil)
        }
        return WalletRustDerivationResponseModel(
            address: result.address, publicKeyHex: result.publicKeyHex, privateKeyHex: result.privateKeyHex)
    }

    // MARK: — Batch derive (all selected chains)

    static func deriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for (chainName, path) in chainPaths {
            guard let chain = SeedDerivationChain(rawValue: chainName) else { continue }
            if let address = try? derive(
                chain: chain, seedPhrase: seedPhrase, derivationPath: path,
                passphrase: nil, hmacKey: nil,
                wantAddress: true, wantPublicKey: false, wantPrivateKey: false
            ).address {
                result[chainName] = address
            }
        }
        return result
    }

    // MARK: — Script type from path

    private static func bitcoinScriptType(from path: String) -> BitcoinScriptType {
        let purpose = path.split(separator: "/")
            .first(where: { $0 != "m" && $0 != "M" })
            .map { String($0).replacingOccurrences(of: "'", with: "") }
        switch purpose {
        case "44": return .p2pkh
        case "49": return .p2shP2wpkh
        case "86": return .p2tr
        default:   return .p2wpkh
        }
    }

    // MARK: — Per-chain dispatch

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func dispatch(
        chain: SeedDerivationChain,
        seedPhrase: String, path: String,
        passphrase: String?, hmacKey: String?,
        scriptType: BitcoinScriptType,
        wa: Bool, wp: Bool, wk: Bool
    ) throws -> DerivationResult {
        switch chain {

        // ── Bitcoin family (script-type aware) ──────────────────────────────
        case .bitcoin:
            return try deriveBitcoin(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .bitcoinTestnet:
            return try deriveBitcoinTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .bitcoinTestnet4:
            return try deriveBitcoinTestnet4(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .bitcoinSignet:
            return try deriveBitcoinSignet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Bitcoin Cash ─────────────────────────────────────────────────────
        case .bitcoinCash:
            return try deriveBitcoinCash(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .bitcoinCashTestnet:
            return try deriveBitcoinCashTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Bitcoin SV ───────────────────────────────────────────────────────
        case .bitcoinSV:
            return try deriveBitcoinSv(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .bitcoinSVTestnet:
            return try deriveBitcoinSvTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Litecoin ─────────────────────────────────────────────────────────
        case .litecoin:
            return try deriveLitecoin(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .litecoinTestnet:
            return try deriveLitecoinTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Dogecoin ─────────────────────────────────────────────────────────
        case .dogecoin:
            return try deriveDogecoin(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .dogecoinTestnet:
            return try deriveDogecoinTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Dash ─────────────────────────────────────────────────────────────
        case .dash:
            return try deriveDash(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .dashTestnet:
            return try deriveDashTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Bitcoin Gold ─────────────────────────────────────────────────────
        case .bitcoinGold:
            return try deriveBitcoinGold(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, scriptType: scriptType, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Zcash ────────────────────────────────────────────────────────────
        case .zcash:
            return try deriveZcash(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .zcashTestnet:
            return try deriveZcashTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Decred ───────────────────────────────────────────────────────────
        case .decred:
            return try deriveDecred(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .decredTestnet:
            return try deriveDecredTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Kaspa ────────────────────────────────────────────────────────────
        case .kaspa:
            return try deriveKaspa(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .kaspaTestnet:
            return try deriveKaspaTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── EVM mainnets ─────────────────────────────────────────────────────
        case .ethereum:
            return try deriveEthereum(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .ethereumClassic:
            return try deriveEthereumClassic(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .arbitrum:
            return try deriveArbitrum(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .optimism:
            return try deriveOptimism(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .avalanche:
            return try deriveAvalanche(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .base:
            return try deriveBase(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .polygon:
            return try derivePolygon(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .hyperliquid:
            return try deriveHyperliquid(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .linea:
            return try deriveLinea(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .scroll:
            return try deriveScroll(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .blast:
            return try deriveBlast(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .mantle:
            return try deriveMantle(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .sei:
            return try deriveSei(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .celo:
            return try deriveCelo(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .cronos:
            return try deriveCronos(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .opBNB:
            return try deriveOpBnb(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .zkSyncEra:
            return try deriveZksyncEra(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .sonic:
            return try deriveSonic(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .berachain:
            return try deriveBerachain(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .unichain:
            return try deriveUnichain(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .ink:
            return try deriveInk(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .xLayer:
            return try deriveXLayer(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── EVM testnets ─────────────────────────────────────────────────────
        case .ethereumSepolia:
            return try deriveEthereumSepolia(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .ethereumHoodi:
            return try deriveEthereumHoodi(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .ethereumClassicMordor:
            return try deriveEthereumClassicMordor(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .arbitrumSepolia:
            return try deriveArbitrumSepolia(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .optimismSepolia:
            return try deriveOptimismSepolia(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .baseSepolia:
            return try deriveBaseSepolia(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .bnbChainTestnet:
            return try deriveBnbTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .avalancheFuji:
            return try deriveAvalancheFuji(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .polygonAmoy:
            return try derivePolygonAmoy(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .hyperliquidTestnet:
            return try deriveHyperliquidTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Tron ─────────────────────────────────────────────────────────────
        case .tron:
            return try deriveTron(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .tronNile:
            return try deriveTronNile(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Solana ───────────────────────────────────────────────────────────
        case .solana:
            return try deriveSolana(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, hmacKey: hmacKey, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .solanaDevnet:
            return try deriveSolanaDevnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, hmacKey: hmacKey, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Stellar ──────────────────────────────────────────────────────────
        case .stellar:
            return try deriveStellar(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, hmacKey: hmacKey, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .stellarTestnet:
            return try deriveStellarTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, hmacKey: hmacKey, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── XRP ──────────────────────────────────────────────────────────────
        case .xrp:
            return try deriveXrp(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .xrpTestnet:
            return try deriveXrpTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Cardano ──────────────────────────────────────────────────────────
        case .cardano:
            return try deriveCardano(seedPhrase: seedPhrase, derivationPath: path.isEmpty ? nil : path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .cardanoPreprod:
            return try deriveCardanoPreprod(seedPhrase: seedPhrase, derivationPath: path.isEmpty ? nil : path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Sui ──────────────────────────────────────────────────────────────
        case .sui:
            return try deriveSui(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .suiTestnet:
            return try deriveSuiTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Aptos ────────────────────────────────────────────────────────────
        case .aptos:
            return try deriveAptos(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .aptosTestnet:
            return try deriveAptosTestnet(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── TON (no derivation path) ─────────────────────────────────────────
        case .ton:
            return try deriveTon(seedPhrase: seedPhrase, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .tonTestnet:
            return try deriveTonTestnet(seedPhrase: seedPhrase, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Internet Computer ────────────────────────────────────────────────
        case .internetComputer:
            return try deriveIcp(seedPhrase: seedPhrase, derivationPath: path, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── NEAR (no derivation path) ────────────────────────────────────────
        case .near:
            return try deriveNear(seedPhrase: seedPhrase, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .nearTestnet:
            return try deriveNearTestnet(seedPhrase: seedPhrase, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Polkadot / Westend (no derivation path) ──────────────────────────
        case .polkadot:
            return try derivePolkadot(seedPhrase: seedPhrase, passphrase: passphrase, hmacKey: hmacKey, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        case .polkadotWestend:
            return try derivePolkadotWestend(seedPhrase: seedPhrase, passphrase: passphrase, hmacKey: hmacKey, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Bittensor (no derivation path) ──────────────────────────────────
        case .bittensor:
            return try deriveBittensor(seedPhrase: seedPhrase, passphrase: passphrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)

        // ── Monero Stagenet (no derivation path) ─────────────────────────────
        case .moneroStagenet:
            return try deriveMoneroStagenet(seedPhrase: seedPhrase, wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
        }
    }
}

// MARK: — Shared result types

struct WalletRustSigningMaterialModel: Sendable {
    let address: String
    let privateKeyHex: String
    let derivationPath: String
    let account: UInt32
    let branch: UInt32
    let index: UInt32
}

struct WalletRustDerivationResponseModel: Sendable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}

// MARK: — CoreWalletDerivationOverrides helpers

extension CoreWalletDerivationOverrides {
    var isEmpty: Bool {
        passphrase == nil && mnemonicWordlist == nil && iterationCount == nil && saltPrefix == nil
            && hmacKey == nil && curve == nil && derivationAlgorithm == nil && addressAlgorithm == nil
            && publicKeyFormat == nil && scriptType == nil
    }
}

// MARK: — String helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
