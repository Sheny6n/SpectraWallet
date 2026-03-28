// MARK: - File Overview
// Core domain models shared across app features: wallets, coins, transactions, alerts, and diagnostics entities.
//
// Responsibilities:
// - Defines strongly-typed data contracts between UI, store, and services.
// - Holds persistence snapshots and helper types for state transformations.

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// --- DATA MODELS ---
// This defines what a "Coin" looks like in our app
struct Coin: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let marketDataID: String
    let coinGeckoID: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let amount: Double
    let priceUSD: Double
    let mark: String
    var color: Color
    
    // Calculates the value of this specific holding
    var valueUSD: Double {
        return amount * priceUSD
    }

    // Asset visibility must be driven by token units, not rounded fiat value.
    var hasVisibleBalance: Bool {
        amount > 0
    }
    
    var holdingKey: String {
        "\(chainName)|\(symbol)"
    }
    
    var accentMarks: [String] {
        switch symbol {
        case "BTC":
            return ["L1", "S", "P"]
        case "LTC":
            return ["L1", "S", "F"]
        case "ETH":
            return ["SC", "VM", "D"]
        case "SOL":
            return ["F", "RT", "+"]
        case "MATIC":
            return ["L2", "ZK", "G"]
        case "AVAX":
            return ["C", "X", "S"]
        case "HYPE":
            return ["L1", "DEX", "P"]
        case "ARB":
            return ["L2", "OP", "A"]
        case "BNB":
            return ["B", "DEX", "+"]
        case "DOGE":
            return ["M", "P2P", "+"]
        case "ADA":
            return ["POS", "SC", "L1"]
        case "TRX":
            return ["TVM", "NET", "+"]
        case "XMR":
            return ["PRV", "POW", "S"]
        case "SUI":
            return ["OBJ", "MOVE", "ZK"]
        case "APT":
            return ["MOVE", "ACC", "L1"]
        case "ICP":
            return ["NS", "LED", "L1"]
        case "NEAR":
            return ["SHD", "ACC", "POS"]
        default:
            return ["+", "+", "+"]
        }
    }
}

struct ImportedWallet: Identifiable {
    let id: UUID
    let name: String
    let bitcoinAddress: String?
    let bitcoinXPub: String?
    let bitcoinCashAddress: String?
    let bitcoinSVAddress: String?
    let litecoinAddress: String?
    let dogecoinAddress: String?
    let ethereumAddress: String?
    let tronAddress: String?
    let solanaAddress: String?
    let stellarAddress: String?
    let xrpAddress: String?
    let moneroAddress: String?
    let cardanoAddress: String?
    let suiAddress: String?
    let aptosAddress: String?
    let tonAddress: String?
    let icpAddress: String?
    let nearAddress: String?
    let polkadotAddress: String?
    let seedDerivationPreset: SeedDerivationPreset
    let seedDerivationPaths: SeedDerivationPaths
    let selectedChain: String
    let holdings: [Coin]
    let includeInPortfolioTotal: Bool
    
    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        id: UUID = UUID(),
        name: String,
        bitcoinAddress: String? = nil,
        bitcoinXPub: String? = nil,
        bitcoinCashAddress: String? = nil,
        bitcoinSVAddress: String? = nil,
        litecoinAddress: String? = nil,
        dogecoinAddress: String? = nil,
        ethereumAddress: String? = nil,
        tronAddress: String? = nil,
        solanaAddress: String? = nil,
        stellarAddress: String? = nil,
        xrpAddress: String? = nil,
        moneroAddress: String? = nil,
        cardanoAddress: String? = nil,
        suiAddress: String? = nil,
        aptosAddress: String? = nil,
        tonAddress: String? = nil,
        icpAddress: String? = nil,
        nearAddress: String? = nil,
        polkadotAddress: String? = nil,
        seedDerivationPreset: SeedDerivationPreset = .standard,
        seedDerivationPaths: SeedDerivationPaths = .defaults,
        selectedChain: String,
        holdings: [Coin],
        includeInPortfolioTotal: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bitcoinAddress = bitcoinAddress
        self.bitcoinXPub = bitcoinXPub
        self.bitcoinCashAddress = bitcoinCashAddress
        self.bitcoinSVAddress = bitcoinSVAddress
        self.litecoinAddress = litecoinAddress
        self.dogecoinAddress = dogecoinAddress
        self.ethereumAddress = ethereumAddress
        self.tronAddress = tronAddress
        self.solanaAddress = solanaAddress
        self.stellarAddress = stellarAddress
        self.xrpAddress = xrpAddress
        self.moneroAddress = moneroAddress
        self.cardanoAddress = cardanoAddress
        self.suiAddress = suiAddress
        self.aptosAddress = aptosAddress
        self.tonAddress = tonAddress
        self.icpAddress = icpAddress
        self.nearAddress = nearAddress
        self.polkadotAddress = polkadotAddress
        self.seedDerivationPreset = seedDerivationPreset
        self.seedDerivationPaths = seedDerivationPaths
        self.selectedChain = selectedChain
        self.holdings = holdings
        self.includeInPortfolioTotal = includeInPortfolioTotal
    }

    var totalBalance: Double {
        holdings.reduce(0) { $0 + $1.valueUSD }
    }
}

struct PersistedCoin: Codable {
    let name: String
    let symbol: String
    let marketDataID: String
    let coinGeckoID: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let amount: Double
    let priceUSD: Double
}

enum TokenTrackingChain: String, CaseIterable, Codable, Identifiable {
    case ethereum = "Ethereum"
    case arbitrum = "Arbitrum"
    case optimism = "Optimism"
    case bnb = "BNB Chain"
    case avalanche = "Avalanche"
    case hyperliquid = "Hyperliquid"
    case solana = "Solana"
    case sui = "Sui"
    case aptos = "Aptos"
    case ton = "TON"
    case near = "NEAR"
    case tron = "Tron"

    var id: String { rawValue }

    var tokenStandard: String {
        switch self {
        case .ethereum:
            return "ERC-20"
        case .arbitrum:
            return "ERC-20"
        case .optimism:
            return "ERC-20"
        case .bnb:
            return "BEP-20"
        case .avalanche:
            return "ARC-20"
        case .hyperliquid:
            return "ERC-20"
        case .solana:
            return "SPL"
        case .sui:
            return "Coin Standard"
        case .aptos:
            return "Fungible Asset"
        case .ton:
            return "Jetton"
        case .near:
            return "NEP-141"
        case .tron:
            return "TRC-20"
        }
    }

    var filterDisplayName: String {
        "\(rawValue) (\(tokenStandard))"
    }

    var contractAddressPrompt: String {
        switch self {
        case .solana:
            return "Mint Address"
        case .sui:
            return "Coin Standard Type"
        case .aptos:
            return "Fungible Asset Metadata or Package Address"
        case .ton:
            return "Jetton Master Address"
        case .near:
            return "Contract Account ID"
        default:
            return "Contract Address"
        }
    }

    static func forChainName(_ chainName: String) -> TokenTrackingChain? {
        let normalized = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        return byNormalizedName[normalized.lowercased()]
    }

    private static let byNormalizedName: [String: TokenTrackingChain] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.rawValue.lowercased(), $0) }
    )
}

private struct ChainRegistryVisualMetadata {
    let mark: String
    let color: Color
    let assetName: String

    static let byID: [String: ChainRegistryVisualMetadata] = ChainVisualRegistryCatalog.loadEntries().mapValues {
        ChainRegistryVisualMetadata(mark: $0.mark, color: $0.color, assetName: $0.assetName)
    }
}

struct ChainRegistryEntry: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let mark: String
    let color: Color
    let assetName: String
    let family: String
    let consensus: String
    let stateModel: String
    let primaryUse: String
    let slip44CoinType: String
    let derivationPath: String
    let alternateDerivationPath: String?
    let totalCirculationModel: String
    let notableDetails: [String]

    var assetIdentifier: String {
        Coin.iconIdentifier(symbol: symbol, chainName: name)
    }

    var nativeIconDescriptor: NativeChainIconDescriptor {
        NativeChainIconDescriptor(
            registryID: id,
            title: name,
            symbol: symbol,
            chainName: name,
            mark: mark,
            color: color,
            assetName: assetName
        )
    }

    private static var cachedAllByLocalization: [String: [ChainRegistryEntry]] = [:]
    private static var cachedEntriesByLowercasedID: [String: [String: ChainRegistryEntry]] = [:]

    static var all: [ChainRegistryEntry] {
        let cacheKey = AppLocalization.preferredLocalizationIdentifiers().joined(separator: "|")
        if let cachedEntries = cachedAllByLocalization[cacheKey] {
            return cachedEntries
        }

        let entries: [ChainRegistryEntry] = ChainWikiEntry.all.compactMap { wiki in
            guard let visual = ChainRegistryVisualMetadata.byID[wiki.id] else { return nil }
            return ChainRegistryEntry(
                id: wiki.id,
                name: wiki.name,
                symbol: wiki.symbol,
                mark: visual.mark,
                color: visual.color,
                assetName: visual.assetName,
                family: wiki.family,
                consensus: wiki.consensus,
                stateModel: wiki.stateModel,
                primaryUse: wiki.primaryUse,
                slip44CoinType: wiki.slip44CoinType,
                derivationPath: wiki.derivationPath,
                alternateDerivationPath: wiki.alternateDerivationPath,
                totalCirculationModel: wiki.totalCirculationModel,
                notableDetails: wiki.notableDetails
            )
        }
        cachedAllByLocalization[cacheKey] = entries
        cachedEntriesByLowercasedID[cacheKey] = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.lowercased(), $0) })
        return entries
    }

    private static var entriesByLowercasedID: [String: ChainRegistryEntry] {
        let cacheKey = AppLocalization.preferredLocalizationIdentifiers().joined(separator: "|")
        if let cachedEntries = cachedEntriesByLowercasedID[cacheKey] {
            return cachedEntries
        }
        _ = all
        return cachedEntriesByLowercasedID[cacheKey] ?? [:]
    }

    static func entry(id: String) -> ChainRegistryEntry? {
        entriesByLowercasedID[id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}

struct TokenVisualRegistryEntry: Identifiable {
    let title: String
    let symbol: String
    let referenceChain: TokenTrackingChain
    let mark: String
    let color: Color
    let assetName: String

    var id: String { symbol }

    var assetIdentifier: String {
        Coin.iconIdentifier(
            symbol: symbol,
            chainName: referenceChain.rawValue,
            tokenStandard: referenceChain.tokenStandard
        )
    }

    static let all: [TokenVisualRegistryEntry] = TokenVisualRegistryCatalog.loadEntries()
    private static let entriesByLowercasedSymbol: [String: TokenVisualRegistryEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.symbol.lowercased(), $0) }
    )
    private static let assetIdentifierFragments: [(fragment: String, entry: TokenVisualRegistryEntry)] = all.map {
        (":\($0.symbol.lowercased())", $0)
    }

    static func entry(symbol: String) -> TokenVisualRegistryEntry? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entriesByLowercasedSymbol[normalized]
    }

    static func entry(matchingAssetIdentifier assetIdentifier: String) -> TokenVisualRegistryEntry? {
        let normalized = assetIdentifier.lowercased()
        return assetIdentifierFragments.first { normalized.contains($0.fragment) }?.entry
    }
}

enum SeedDerivationPreset: String, CaseIterable, Codable, Identifiable {
    case standard
    case account1
    case account2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .account1:
            return "Account 1"
        case .account2:
            return "Account 2"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            return "Use account 0 default paths."
        case .account1:
            return "Use account 1 paths for all supported chains."
        case .account2:
            return "Use account 2 paths for all supported chains."
        }
    }

    var accountIndex: UInt32 {
        switch self {
        case .standard:
            return 0
        case .account1:
            return 1
        case .account2:
            return 2
        }
    }
}

enum SeedDerivationChain: String, CaseIterable, Codable, Identifiable {
    case bitcoin = "Bitcoin"
    case bitcoinCash = "Bitcoin Cash"
    case bitcoinSV = "Bitcoin SV"
    case litecoin = "Litecoin"
    case dogecoin = "Dogecoin"
    case ethereum = "Ethereum"
    case ethereumClassic = "Ethereum Classic"
    case arbitrum = "Arbitrum"
    case optimism = "Optimism"
    case avalanche = "Avalanche"
    case hyperliquid = "Hyperliquid"
    case tron = "Tron"
    case solana = "Solana"
    case stellar = "Stellar"
    case xrp = "XRP Ledger"
    case cardano = "Cardano"
    case sui = "Sui"
    case aptos = "Aptos"
    case ton = "TON"
    case internetComputer = "Internet Computer"
    case near = "NEAR"
    case polkadot = "Polkadot"

    var id: String { rawValue }

    var defaultPath: String {
        switch self {
        case .bitcoin:
            return "m/84'/0'/0'/0/0"
        case .bitcoinCash:
            return "m/44'/145'/0'/0/0"
        case .bitcoinSV:
            return "m/44'/236'/0'/0/0"
        case .litecoin:
            return "m/44'/2'/0'/0/0"
        case .dogecoin:
            return "m/44'/3'/0'/0/0"
        case .ethereum:
            return "m/44'/60'/0'/0/0"
        case .ethereumClassic:
            return "m/44'/61'/0'/0/0"
        case .arbitrum:
            return "m/44'/60'/0'/0/0"
        case .optimism:
            return "m/44'/60'/0'/0/0"
        case .avalanche:
            return "m/44'/60'/0'/0/0"
        case .hyperliquid:
            return "m/44'/60'/0'/0/0"
        case .tron:
            return "m/44'/195'/0'/0/0"
        case .solana:
            return "m/44'/501'/0'/0'"
        case .stellar:
            return "m/44'/148'/0'"
        case .xrp:
            return "m/44'/144'/0'/0/0"
        case .cardano:
            return "m/1852'/1815'/0'/0/0"
        case .sui:
            return "m/44'/784'/0'/0'/0'"
        case .aptos:
            return "m/44'/637'/0'/0'/0'"
        case .ton:
            return "m/44'/607'/0'/0/0"
        case .internetComputer:
            return "m/44'/223'/0'/0/0"
        case .near:
            return "m/44'/397'/0'"
        case .polkadot:
            return "m/44'/354'/0'"
        }
    }

    var presetOptions: [SeedDerivationPathPreset] {
        switch self {
        case .bitcoin:
            return [
                SeedDerivationPathPreset(
                    title: "Taproot",
                    detail: "m/86'/0'/0'/0/0",
                    path: "m/86'/0'/0'/0/0"
                ),
                SeedDerivationPathPreset(
                    title: "Native SegWit",
                    detail: "m/84'/0'/0'/0/0",
                    path: defaultPath
                ),
                SeedDerivationPathPreset(
                    title: "Nested SegWit",
                    detail: "m/49'/0'/0'/0/0",
                    path: "m/49'/0'/0'/0/0"
                ),
                SeedDerivationPathPreset(
                    title: "Legacy",
                    detail: "m/44'/0'/0'/0/0",
                    path: "m/44'/0'/0'/0/0"
                ),
                SeedDerivationPathPreset(
                    title: "Electrum Legacy",
                    detail: "m/0'/0",
                    path: "m/0'/0"
                ),
                SeedDerivationPathPreset(
                    title: "BIP32 Legacy",
                    detail: "m/0'/0/0",
                    path: "m/0'/0/0"
                ),
            ]
        case .solana:
            return [
                SeedDerivationPathPreset(
                    title: "Standard",
                    detail: "m/44'/501'/0'/0'",
                    path: defaultPath
                ),
                SeedDerivationPathPreset(
                    title: "Legacy",
                    detail: "m/44'/501'/0'",
                    path: "m/44'/501'/0'"
                ),
            ]
        case .litecoin:
            return [
                SeedDerivationPathPreset(
                    title: "Legacy",
                    detail: "m/44'/2'/0'/0/0",
                    path: "m/44'/2'/0'/0/0"
                ),
                SeedDerivationPathPreset(
                    title: "SegWit",
                    detail: "m/49'/2'/0'/0/0",
                    path: "m/49'/2'/0'/0/0"
                ),
                SeedDerivationPathPreset(
                    title: "Native SegWit",
                    detail: "m/84'/2'/0'/0/0",
                    path: "m/84'/2'/0'/0/0"
                ),
            ]
        case .bitcoinCash:
            return [
                SeedDerivationPathPreset(
                    title: "Standard",
                    detail: "m/44'/145'/0'/0/0",
                    path: defaultPath
                ),
                SeedDerivationPathPreset(
                    title: "Electrum Legacy",
                    detail: "m/0",
                    path: "m/0"
                ),
            ]
        case .bitcoinSV:
            return [
                SeedDerivationPathPreset(
                    title: "Standard",
                    detail: "m/44'/236'/0'/0/0",
                    path: defaultPath
                ),
                SeedDerivationPathPreset(
                    title: "Electrum Legacy",
                    detail: "m/0",
                    path: "m/0"
                ),
            ]
        case .cardano:
            return [
                SeedDerivationPathPreset(
                    title: "Shelley",
                    detail: "m/1852'/1815'/0'/0/0",
                    path: defaultPath
                ),
                SeedDerivationPathPreset(
                    title: "Byron",
                    detail: "m/44'/1815'/0'/0/0",
                    path: "m/44'/1815'/0'/0/0"
                ),
            ]
        case .tron:
            return [
                SeedDerivationPathPreset(
                    title: "Standard",
                    detail: "m/44'/195'/0'/0/0",
                    path: defaultPath
                ),
                SeedDerivationPathPreset(
                    title: "Legacy",
                    detail: "m/44'/60'/0'/0/0",
                    path: "m/44'/60'/0'/0/0"
                ),
            ]
        default:
            return [
                SeedDerivationPathPreset(
                    title: "Standard",
                    detail: defaultPath,
                    path: defaultPath
                ),
            ]
        }
    }
}

struct SeedDerivationPathPreset: Identifiable, Equatable {
    let title: String
    let detail: String
    let path: String

    var id: String { "\(title)|\(path)" }
}

enum SeedDerivationFlavor: String, Equatable {
    case standard
    case legacy
    case nestedSegWit
    case nativeSegWit
    case taproot
    case electrumLegacy
}

struct SeedDerivationResolution: Equatable {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}

extension SeedDerivationChain {
    func resolve(path rawPath: String) -> SeedDerivationResolution {
        let normalizedPath = DerivationPathParser.normalize(rawPath, fallback: defaultPath)
        return SeedDerivationResolution(
            chain: self,
            normalizedPath: normalizedPath,
            accountIndex: resolvedAccountIndex(in: normalizedPath),
            flavor: resolvedFlavor(in: normalizedPath)
        )
    }

    private func resolvedAccountIndex(in normalizedPath: String) -> UInt32 {
        switch self {
        case .bitcoin where normalizedPath == "m/0'/0" || normalizedPath == "m/0'/0/0":
            return 0
        case .bitcoinCash where normalizedPath == "m/0":
            return 0
        case .bitcoinSV where normalizedPath == "m/0":
            return 0
        default:
            return DerivationPathParser.segmentValue(at: 2, in: normalizedPath) ?? 0
        }
    }

    private func resolvedFlavor(in normalizedPath: String) -> SeedDerivationFlavor {
        switch self {
        case .bitcoin:
            switch normalizedPath {
            case let path where path.hasPrefix("m/86'"):
                return .taproot
            case let path where path.hasPrefix("m/84'"):
                return .nativeSegWit
            case let path where path.hasPrefix("m/49'"):
                return .nestedSegWit
            case "m/0'/0", "m/0'/0/0":
                return .electrumLegacy
            case let path where path.hasPrefix("m/44'"):
                return .legacy
            default:
                return .standard
            }
        case .litecoin:
            switch normalizedPath {
            case let path where path.hasPrefix("m/84'/2'"):
                return .nativeSegWit
            case let path where path.hasPrefix("m/49'/2'"):
                return .nestedSegWit
            case let path where path.hasPrefix("m/44'/2'"):
                return .legacy
            default:
                return .standard
            }
        case .bitcoinCash:
            switch normalizedPath {
            case "m/0":
                return .electrumLegacy
            case let path where path.hasPrefix("m/44'/145'"):
                return .legacy
            default:
                return .standard
            }
        case .solana:
            return normalizedPath == "m/44'/501'/0'" ? .legacy : .standard
        case .cardano:
            return normalizedPath.hasPrefix("m/44'/1815'") ? .legacy : .standard
        case .tron:
            return normalizedPath.hasPrefix("m/44'/60'") ? .legacy : .standard
        case .aptos:
            return .standard
        case .internetComputer:
            return .standard
        default:
            return .standard
        }
    }
}

struct SeedDerivationPaths: Codable, Equatable {
    var isCustomEnabled: Bool
    var bitcoin: String
    var bitcoinCash: String
    var bitcoinSV: String
    var litecoin: String
    var dogecoin: String
    var ethereum: String
    var ethereumClassic: String
    var arbitrum: String
    var optimism: String
    var avalanche: String
    var hyperliquid: String
    var tron: String
    var solana: String
    var stellar: String
    var xrp: String
    var cardano: String
    var sui: String
    var aptos: String
    var ton: String
    var internetComputer: String
    var near: String
    var polkadot: String

    static let defaults = SeedDerivationPaths(
        isCustomEnabled: false,
        bitcoin: SeedDerivationChain.bitcoin.defaultPath,
        bitcoinCash: SeedDerivationChain.bitcoinCash.defaultPath,
        bitcoinSV: SeedDerivationChain.bitcoinSV.defaultPath,
        litecoin: SeedDerivationChain.litecoin.defaultPath,
        dogecoin: SeedDerivationChain.dogecoin.defaultPath,
        ethereum: SeedDerivationChain.ethereum.defaultPath,
        ethereumClassic: SeedDerivationChain.ethereumClassic.defaultPath,
        arbitrum: SeedDerivationChain.arbitrum.defaultPath,
        optimism: SeedDerivationChain.optimism.defaultPath,
        avalanche: SeedDerivationChain.avalanche.defaultPath,
        hyperliquid: SeedDerivationChain.hyperliquid.defaultPath,
        tron: SeedDerivationChain.tron.defaultPath,
        solana: SeedDerivationChain.solana.defaultPath,
        stellar: SeedDerivationChain.stellar.defaultPath,
        xrp: SeedDerivationChain.xrp.defaultPath,
        cardano: SeedDerivationChain.cardano.defaultPath,
        sui: SeedDerivationChain.sui.defaultPath,
        aptos: SeedDerivationChain.aptos.defaultPath,
        ton: SeedDerivationChain.ton.defaultPath,
        internetComputer: SeedDerivationChain.internetComputer.defaultPath,
        near: SeedDerivationChain.near.defaultPath,
        polkadot: SeedDerivationChain.polkadot.defaultPath
    )

    func path(for chain: SeedDerivationChain) -> String {
        switch chain {
        case .bitcoin:
            return bitcoin
        case .bitcoinCash:
            return bitcoinCash
        case .bitcoinSV:
            return bitcoinSV
        case .litecoin:
            return litecoin
        case .dogecoin:
            return dogecoin
        case .ethereum:
            return ethereum
        case .ethereumClassic:
            return ethereumClassic
        case .arbitrum:
            return arbitrum
        case .optimism:
            return optimism
        case .avalanche:
            return avalanche
        case .hyperliquid:
            return hyperliquid
        case .tron:
            return tron
        case .solana:
            return solana
        case .stellar:
            return stellar
        case .xrp:
            return xrp
        case .cardano:
            return cardano
        case .sui:
            return sui
        case .aptos:
            return aptos
        case .ton:
            return ton
        case .internetComputer:
            return internetComputer
        case .near:
            return near
        case .polkadot:
            return polkadot
        }
    }

    mutating func setPath(_ path: String, for chain: SeedDerivationChain) {
        switch chain {
        case .bitcoin:
            bitcoin = path
        case .bitcoinCash:
            bitcoinCash = path
        case .bitcoinSV:
            bitcoinSV = path
        case .litecoin:
            litecoin = path
        case .dogecoin:
            dogecoin = path
        case .ethereum:
            ethereum = path
        case .ethereumClassic:
            ethereumClassic = path
        case .arbitrum:
            arbitrum = path
        case .optimism:
            optimism = path
        case .avalanche:
            avalanche = path
        case .hyperliquid:
            hyperliquid = path
        case .tron:
            tron = path
        case .solana:
            solana = path
        case .stellar:
            stellar = path
        case .xrp:
            xrp = path
        case .cardano:
            cardano = path
        case .sui:
            sui = path
        case .aptos:
            aptos = path
        case .ton:
            ton = path
        case .internetComputer:
            internetComputer = path
        case .near:
            near = path
        case .polkadot:
            polkadot = path
        }
    }

    static func migrated(from preset: SeedDerivationPreset?) -> SeedDerivationPaths {
        guard let preset else { return .defaults }

        var paths = SeedDerivationPaths.defaults
        switch preset {
        case .standard:
            break
        case .account1:
            paths.bitcoin = "m/84'/0'/1'/0/0"
            paths.bitcoinCash = "m/44'/145'/1'/0/0"
            paths.litecoin = "m/44'/2'/1'/0/0"
            paths.dogecoin = "m/44'/3'/1'/0/0"
            paths.ethereum = "m/44'/60'/1'/0/0"
            paths.ethereumClassic = "m/44'/61'/1'/0/0"
            paths.arbitrum = "m/44'/60'/1'/0/0"
            paths.optimism = "m/44'/60'/1'/0/0"
            paths.avalanche = "m/44'/60'/1'/0/0"
            paths.hyperliquid = "m/44'/60'/1'/0/0"
            paths.tron = "m/44'/195'/1'/0/0"
            paths.solana = "m/44'/501'/1'/0'"
            paths.stellar = "m/44'/148'/1'"
            paths.xrp = "m/44'/144'/1'/0/0"
            paths.cardano = "m/1852'/1815'/1'/0/0"
            paths.sui = "m/44'/784'/1'/0'/0'"
            paths.aptos = "m/44'/637'/1'/0'/0'"
            paths.ton = "m/44'/607'/1'/0/0"
            paths.internetComputer = "m/44'/223'/1'/0/0"
            paths.near = "m/44'/397'/1'"
            paths.polkadot = "m/44'/354'/1'"
        case .account2:
            paths.bitcoin = "m/84'/0'/2'/0/0"
            paths.bitcoinCash = "m/44'/145'/2'/0/0"
            paths.litecoin = "m/44'/2'/2'/0/0"
            paths.dogecoin = "m/44'/3'/2'/0/0"
            paths.ethereum = "m/44'/60'/2'/0/0"
            paths.ethereumClassic = "m/44'/61'/2'/0/0"
            paths.arbitrum = "m/44'/60'/2'/0/0"
            paths.optimism = "m/44'/60'/2'/0/0"
            paths.avalanche = "m/44'/60'/2'/0/0"
            paths.hyperliquid = "m/44'/60'/2'/0/0"
            paths.tron = "m/44'/195'/2'/0/0"
            paths.solana = "m/44'/501'/2'/0'"
            paths.stellar = "m/44'/148'/2'"
            paths.xrp = "m/44'/144'/2'/0/0"
            paths.cardano = "m/1852'/1815'/2'/0/0"
            paths.sui = "m/44'/784'/2'/0'/0'"
            paths.aptos = "m/44'/637'/2'/0'/0'"
            paths.ton = "m/44'/607'/2'/0/0"
            paths.internetComputer = "m/44'/223'/2'/0/0"
            paths.near = "m/44'/397'/2'"
            paths.polkadot = "m/44'/354'/2'"
        }

        return paths
    }

    static func applyingPreset(_ preset: SeedDerivationPreset, keepCustomEnabled: Bool = false) -> SeedDerivationPaths {
        var paths = migrated(from: preset)
        paths.isCustomEnabled = keepCustomEnabled
        return paths
    }
}

enum TokenPreferenceCategory: String, CaseIterable, Codable, Identifiable {
    case stablecoin
    case meme
    case custom

    var id: String { rawValue }
}

struct TokenPreferenceEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let chain: TokenTrackingChain
    let name: String
    let symbol: String
    let tokenStandard: String
    let contractAddress: String
    let marketDataID: String
    let coinGeckoID: String
    var decimals: Int
    var displayDecimals: Int?
    let category: TokenPreferenceCategory
    let isBuiltIn: Bool
    var isEnabled: Bool

    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        id: UUID = UUID(),
        chain: TokenTrackingChain,
        name: String,
        symbol: String,
        tokenStandard: String,
        contractAddress: String,
        marketDataID: String,
        coinGeckoID: String,
        decimals: Int,
        displayDecimals: Int? = nil,
        category: TokenPreferenceCategory,
        isBuiltIn: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.chain = chain
        self.name = name
        self.symbol = symbol
        self.tokenStandard = tokenStandard
        self.contractAddress = contractAddress
        self.marketDataID = marketDataID
        self.coinGeckoID = coinGeckoID
        self.decimals = decimals
        self.displayDecimals = displayDecimals
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }
}

struct ChainTokenRegistryEntry: Identifiable, Equatable {
    let chain: TokenTrackingChain
    let name: String
    let symbol: String
    let tokenStandard: String
    let contractAddress: String
    let marketDataID: String
    let coinGeckoID: String
    let decimals: Int
    let displayDecimals: Int?
    let category: TokenPreferenceCategory
    let isBuiltIn: Bool
    let isEnabledByDefault: Bool

    var id: String {
        Coin.iconIdentifier(
            symbol: symbol,
            chainName: chain.rawValue,
            contractAddress: contractAddress,
            tokenStandard: tokenStandard
        )
    }

    init(
        chain: TokenTrackingChain,
        name: String,
        symbol: String,
        tokenStandard: String,
        contractAddress: String,
        marketDataID: String,
        coinGeckoID: String,
        decimals: Int,
        displayDecimals: Int? = nil,
        category: TokenPreferenceCategory,
        isBuiltIn: Bool,
        isEnabledByDefault: Bool
    ) {
        self.chain = chain
        self.name = name
        self.symbol = symbol
        self.tokenStandard = tokenStandard
        self.contractAddress = contractAddress
        self.marketDataID = marketDataID
        self.coinGeckoID = coinGeckoID
        self.decimals = decimals
        self.displayDecimals = displayDecimals
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.isEnabledByDefault = isEnabledByDefault
    }

    init(tokenPreferenceEntry: TokenPreferenceEntry) {
        chain = tokenPreferenceEntry.chain
        name = tokenPreferenceEntry.name
        symbol = tokenPreferenceEntry.symbol
        tokenStandard = tokenPreferenceEntry.tokenStandard
        contractAddress = tokenPreferenceEntry.contractAddress
        marketDataID = tokenPreferenceEntry.marketDataID
        coinGeckoID = tokenPreferenceEntry.coinGeckoID
        decimals = tokenPreferenceEntry.decimals
        displayDecimals = tokenPreferenceEntry.displayDecimals
        category = tokenPreferenceEntry.category
        isBuiltIn = tokenPreferenceEntry.isBuiltIn
        isEnabledByDefault = tokenPreferenceEntry.isEnabled
    }

    var tokenPreferenceEntry: TokenPreferenceEntry {
        TokenPreferenceEntry(
            chain: chain,
            name: name,
            symbol: symbol,
            tokenStandard: tokenStandard,
            contractAddress: contractAddress,
            marketDataID: marketDataID,
            coinGeckoID: coinGeckoID,
            decimals: decimals,
            displayDecimals: displayDecimals,
            category: category,
            isBuiltIn: isBuiltIn,
            isEnabled: isEnabledByDefault
        )
    }
}

struct PersistedWallet: Codable {
    let id: UUID
    let name: String
    let bitcoinAddress: String?
    let bitcoinXPub: String?
    let bitcoinCashAddress: String?
    let bitcoinSVAddress: String?
    let litecoinAddress: String?
    let dogecoinAddress: String?
    let ethereumAddress: String?
    let tronAddress: String?
    let solanaAddress: String?
    let stellarAddress: String?
    let xrpAddress: String?
    let moneroAddress: String?
    let cardanoAddress: String?
    let suiAddress: String?
    let aptosAddress: String?
    let tonAddress: String?
    let icpAddress: String?
    let nearAddress: String?
    let polkadotAddress: String?
    let seedDerivationPreset: SeedDerivationPreset
    let seedDerivationPaths: SeedDerivationPaths
    let selectedChain: String
    let holdings: [PersistedCoin]
    let includeInPortfolioTotal: Bool
}

struct PersistedWalletStore: Codable {
    let version: Int
    let wallets: [PersistedWallet]
    
    static let currentVersion = 5
}

enum TransactionKind: String, Codable {
    case send
    case receive
}

enum TransactionStatus: String, Codable {
    case pending
    case confirmed
    case failed
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case sends = "Sends"
    case receives = "Receives"
    case pending = "Pending"
    
    var id: String { rawValue }
}

enum HistorySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    
    var id: String { rawValue }
}

struct HistorySection: Identifiable {
    let title: String
    let transactions: [TransactionRecord]
    
    var id: String { title }
}

struct NormalizedHistoryEntry: Identifiable {
    let id: String
    let transactionID: UUID
    let dedupeKey: String
    let createdAt: Date
    let kind: TransactionKind
    let status: TransactionStatus
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let address: String
    let transactionHash: String?
    let sourceTag: String
    let sourceConfidenceTag: String
    let sourceConfidenceScore: Int
    let providerCount: Int
    let searchIndex: String
}

enum PriceAlertCondition: String, CaseIterable, Codable, Identifiable {
    case above = "Above"
    case below = "Below"
    
    var id: String { rawValue }

    var displayName: String {
        NSLocalizedString(rawValue, comment: "")
    }
}

struct PriceAlertRule: Identifiable {
    let id: UUID
    let holdingKey: String
    let assetName: String
    let symbol: String
    let chainName: String
    let targetPrice: Double
    let condition: PriceAlertCondition
    var isEnabled: Bool
    var hasTriggered: Bool
    
    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        id: UUID = UUID(),
        holdingKey: String,
        assetName: String,
        symbol: String,
        chainName: String,
        targetPrice: Double,
        condition: PriceAlertCondition,
        isEnabled: Bool = true,
        hasTriggered: Bool = false
    ) {
        self.id = id
        self.holdingKey = holdingKey
        self.assetName = assetName
        self.symbol = symbol
        self.chainName = chainName
        self.targetPrice = targetPrice
        self.condition = condition
        self.isEnabled = isEnabled
        self.hasTriggered = hasTriggered
    }
    
    var titleText: String {
        let format = NSLocalizedString("%@ on %@", comment: "")
        return String(format: format, locale: Locale.current, assetName, chainName)
    }
    
    var conditionText: String {
        "\(condition.rawValue) $\(String(format: "%.2f", targetPrice))"
    }
    
    var statusText: String {
        if !isEnabled {
            return NSLocalizedString("Paused", comment: "")
        }
        return hasTriggered
            ? NSLocalizedString("Triggered", comment: "")
            : NSLocalizedString("Watching", comment: "")
    }
}

struct PersistedPriceAlertRule: Codable {
    let id: UUID
    let holdingKey: String
    let assetName: String
    let symbol: String
    let chainName: String
    let targetPrice: Double
    let condition: PriceAlertCondition
    let isEnabled: Bool
    let hasTriggered: Bool
}

struct PersistedPriceAlertStore: Codable {
    let version: Int
    let alerts: [PersistedPriceAlertRule]
    
    static let currentVersion = 1
}

struct DonationDestination: Identifiable {
    let id = UUID()
    let title: String
    let address: String
    let mark: String
    let assetIdentifier: String?
    let color: Color
}

struct AddressBookEntry: Identifiable {
    let id: UUID
    let name: String
    let chainName: String
    let address: String
    let note: String

    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        id: UUID = UUID(),
        name: String,
        chainName: String,
        address: String,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.chainName = chainName
        self.address = address
        self.note = note
    }

    var subtitleText: String {
        guard !note.isEmpty else { return chainName }
        let format = NSLocalizedString("%@ • %@", comment: "")
        return String(format: format, locale: Locale.current, chainName, note)
    }
}

struct PersistedAddressBookEntry: Codable {
    let id: UUID
    let name: String
    let chainName: String
    let address: String
    let note: String
}

struct PersistedAddressBookStore: Codable {
    let version: Int
    let entries: [PersistedAddressBookEntry]

    static let currentVersion = 1
}

struct TransactionRecord: Identifiable {
    let id: UUID
    let walletID: UUID?
    let kind: TransactionKind
    let status: TransactionStatus
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let amount: Double
    let address: String
    let transactionHash: String?
    let ethereumNonce: Int?
    let receiptBlockNumber: Int?
    let receiptGasUsed: String?
    let receiptEffectiveGasPriceGwei: Double?
    let receiptNetworkFeeETH: Double?
    let dogecoinConfirmedNetworkFeeDOGE: Double?
    let dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?
    let dogecoinEstimatedFeeRateDOGEPerKB: Double?
    let dogecoinUsedChangeOutput: Bool?
    let sourceDerivationPath: String?
    let changeDerivationPath: String?
    let sourceAddress: String?
    let changeAddress: String?
    let dogecoinRawTransactionHex: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAt: Date
    
    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        id: UUID = UUID(),
        walletID: UUID? = nil,
        kind: TransactionKind,
        status: TransactionStatus,
        walletName: String,
        assetName: String,
        symbol: String,
        chainName: String,
        amount: Double,
        address: String,
        transactionHash: String? = nil,
        ethereumNonce: Int? = nil,
        receiptBlockNumber: Int? = nil,
        receiptGasUsed: String? = nil,
        receiptEffectiveGasPriceGwei: Double? = nil,
        receiptNetworkFeeETH: Double? = nil,
        dogecoinConfirmedNetworkFeeDOGE: Double? = nil,
        dogecoinConfirmations: Int? = nil,
        dogecoinFeePriorityRaw: String? = nil,
        dogecoinEstimatedFeeRateDOGEPerKB: Double? = nil,
        dogecoinUsedChangeOutput: Bool? = nil,
        sourceDerivationPath: String? = nil,
        changeDerivationPath: String? = nil,
        sourceAddress: String? = nil,
        changeAddress: String? = nil,
        dogecoinRawTransactionHex: String? = nil,
        failureReason: String? = nil,
        transactionHistorySource: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.walletID = walletID
        self.kind = kind
        self.status = status
        self.walletName = walletName
        self.assetName = assetName
        self.symbol = symbol
        self.chainName = chainName
        self.amount = amount
        self.address = address
        self.transactionHash = transactionHash
        self.ethereumNonce = ethereumNonce
        self.receiptBlockNumber = receiptBlockNumber
        self.receiptGasUsed = receiptGasUsed
        self.receiptEffectiveGasPriceGwei = receiptEffectiveGasPriceGwei
        self.receiptNetworkFeeETH = receiptNetworkFeeETH
        self.dogecoinConfirmedNetworkFeeDOGE = dogecoinConfirmedNetworkFeeDOGE
        self.dogecoinConfirmations = dogecoinConfirmations
        self.dogecoinFeePriorityRaw = dogecoinFeePriorityRaw
        self.dogecoinEstimatedFeeRateDOGEPerKB = dogecoinEstimatedFeeRateDOGEPerKB
        self.dogecoinUsedChangeOutput = dogecoinUsedChangeOutput
        self.sourceDerivationPath = sourceDerivationPath
        self.changeDerivationPath = changeDerivationPath
        self.sourceAddress = sourceAddress
        self.changeAddress = changeAddress
        self.dogecoinRawTransactionHex = dogecoinRawTransactionHex
        self.failureReason = failureReason
        self.transactionHistorySource = transactionHistorySource
        self.createdAt = createdAt
    }

    var assetIdentifier: String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let nativeDescriptor = Coin.nativeChainIconDescriptor(symbol: symbol, chainName: chainName) {
            return nativeDescriptor.assetIdentifier
        }

        guard let chainSlug = transactionIconChainSlug else { return nil }
        guard !normalizedSymbol.isEmpty else { return nil }
        return "token:\(chainSlug):\(normalizedSymbol)"
    }

    private var transactionIconChainSlug: String? {
        switch chainName {
        case "Ethereum":
            return "ethereum"
        case "Arbitrum":
            return "arbitrum"
        case "BNB Chain":
            return "bnb-chain"
        case "Avalanche":
            return "avalanche"
        case "Tron":
            return "tron"
        case "Solana":
            return "solana"
        default:
            return nil
        }
    }
}

enum SendBroadcastVerificationStatus: Equatable {
    case verified
    case deferred
    case failed(String)
}

struct PersistedTransactionRecord: Codable {
    let id: UUID
    let walletID: UUID?
    let kind: TransactionKind
    let status: TransactionStatus
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let amount: Double
    let address: String
    let transactionHash: String?
    let ethereumNonce: Int?
    let receiptBlockNumber: Int?
    let receiptGasUsed: String?
    let receiptEffectiveGasPriceGwei: Double?
    let receiptNetworkFeeETH: Double?
    let dogecoinConfirmedNetworkFeeDOGE: Double?
    let dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?
    let dogecoinEstimatedFeeRateDOGEPerKB: Double?
    let dogecoinUsedChangeOutput: Bool?
    let sourceDerivationPath: String?
    let changeDerivationPath: String?
    let sourceAddress: String?
    let changeAddress: String?
    let dogecoinRawTransactionHex: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case walletID
        case kind
        case status
        case walletName
        case assetName
        case symbol
        case chainName
        case amount
        case address
        case transactionHash
        case ethereumNonce
        case receiptBlockNumber
        case receiptGasUsed
        case receiptEffectiveGasPriceGwei
        case receiptNetworkFeeETH
        case dogecoinConfirmedNetworkFeeDOGE
        case dogecoinConfirmations
        case dogecoinFeePriorityRaw
        case dogecoinEstimatedFeeRateDOGEPerKB
        case dogecoinUsedChangeOutput
        case sourceDerivationPath
        case changeDerivationPath
        case sourceAddress
        case changeAddress
        case dogecoinRawTransactionHex
        case failureReason
        case transactionHistorySource
        case createdAt
    }
    
    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        id: UUID,
        walletID: UUID? = nil,
        kind: TransactionKind,
        status: TransactionStatus,
        walletName: String,
        assetName: String,
        symbol: String,
        chainName: String,
        amount: Double,
        address: String,
        transactionHash: String? = nil,
        ethereumNonce: Int? = nil,
        receiptBlockNumber: Int? = nil,
        receiptGasUsed: String? = nil,
        receiptEffectiveGasPriceGwei: Double? = nil,
        receiptNetworkFeeETH: Double? = nil,
        dogecoinConfirmedNetworkFeeDOGE: Double? = nil,
        dogecoinConfirmations: Int? = nil,
        dogecoinFeePriorityRaw: String? = nil,
        dogecoinEstimatedFeeRateDOGEPerKB: Double? = nil,
        dogecoinUsedChangeOutput: Bool? = nil,
        sourceDerivationPath: String? = nil,
        changeDerivationPath: String? = nil,
        sourceAddress: String? = nil,
        changeAddress: String? = nil,
        dogecoinRawTransactionHex: String? = nil,
        failureReason: String? = nil,
        transactionHistorySource: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.walletID = walletID
        self.kind = kind
        self.status = status
        self.walletName = walletName
        self.assetName = assetName
        self.symbol = symbol
        self.chainName = chainName
        self.amount = amount
        self.address = address
        self.transactionHash = transactionHash
        self.ethereumNonce = ethereumNonce
        self.receiptBlockNumber = receiptBlockNumber
        self.receiptGasUsed = receiptGasUsed
        self.receiptEffectiveGasPriceGwei = receiptEffectiveGasPriceGwei
        self.receiptNetworkFeeETH = receiptNetworkFeeETH
        self.dogecoinConfirmedNetworkFeeDOGE = dogecoinConfirmedNetworkFeeDOGE
        self.dogecoinConfirmations = dogecoinConfirmations
        self.dogecoinFeePriorityRaw = dogecoinFeePriorityRaw
        self.dogecoinEstimatedFeeRateDOGEPerKB = dogecoinEstimatedFeeRateDOGEPerKB
        self.dogecoinUsedChangeOutput = dogecoinUsedChangeOutput
        self.sourceDerivationPath = sourceDerivationPath
        self.changeDerivationPath = changeDerivationPath
        self.sourceAddress = sourceAddress
        self.changeAddress = changeAddress
        self.dogecoinRawTransactionHex = dogecoinRawTransactionHex
        self.failureReason = failureReason
        self.transactionHistorySource = transactionHistorySource
        self.createdAt = createdAt
    }
    
    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(TransactionKind.self, forKey: .kind)
        
        id = try container.decode(UUID.self, forKey: .id)
        walletID = try container.decodeIfPresent(UUID.self, forKey: .walletID)
        self.kind = kind
        status = try container.decodeIfPresent(TransactionStatus.self, forKey: .status)
            ?? (kind == .receive ? .pending : .confirmed)
        walletName = try container.decode(String.self, forKey: .walletName)
        assetName = try container.decode(String.self, forKey: .assetName)
        symbol = try container.decode(String.self, forKey: .symbol)
        chainName = try container.decode(String.self, forKey: .chainName)
        amount = try container.decode(Double.self, forKey: .amount)
        address = try container.decode(String.self, forKey: .address)
        transactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash)
        ethereumNonce = try container.decodeIfPresent(Int.self, forKey: .ethereumNonce)
        receiptBlockNumber = try container.decodeIfPresent(Int.self, forKey: .receiptBlockNumber)
        receiptGasUsed = try container.decodeIfPresent(String.self, forKey: .receiptGasUsed)
        receiptEffectiveGasPriceGwei = try container.decodeIfPresent(Double.self, forKey: .receiptEffectiveGasPriceGwei)
        receiptNetworkFeeETH = try container.decodeIfPresent(Double.self, forKey: .receiptNetworkFeeETH)
        dogecoinConfirmedNetworkFeeDOGE = try container.decodeIfPresent(Double.self, forKey: .dogecoinConfirmedNetworkFeeDOGE)
        dogecoinConfirmations = try container.decodeIfPresent(Int.self, forKey: .dogecoinConfirmations)
        dogecoinFeePriorityRaw = try container.decodeIfPresent(String.self, forKey: .dogecoinFeePriorityRaw)
        dogecoinEstimatedFeeRateDOGEPerKB = try container.decodeIfPresent(Double.self, forKey: .dogecoinEstimatedFeeRateDOGEPerKB)
        dogecoinUsedChangeOutput = try container.decodeIfPresent(Bool.self, forKey: .dogecoinUsedChangeOutput)
        sourceDerivationPath = try container.decodeIfPresent(String.self, forKey: .sourceDerivationPath)
        changeDerivationPath = try container.decodeIfPresent(String.self, forKey: .changeDerivationPath)
        sourceAddress = try container.decodeIfPresent(String.self, forKey: .sourceAddress)
        changeAddress = try container.decodeIfPresent(String.self, forKey: .changeAddress)
        dogecoinRawTransactionHex = try container.decodeIfPresent(String.self, forKey: .dogecoinRawTransactionHex)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        transactionHistorySource = try container.decodeIfPresent(String.self, forKey: .transactionHistorySource)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

private enum SeedDerivationPathsCodingKeys: String, CodingKey {
    case isCustomEnabled
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case avalanche
    case hyperliquid
    case tron
    case solana
    case stellar
    case xrp
    case cardano
    case sui
    case aptos
    case ton
    case internetComputer
    case near
    case polkadot
}

struct NativeChainIconDescriptor: Identifiable {
    let registryID: String
    let title: String
    let symbol: String
    let chainName: String
    let mark: String
    let color: Color
    let assetName: String

    var id: String { assetIdentifier }
    var assetIdentifier: String {
        Coin.iconIdentifier(symbol: symbol, chainName: chainName)
    }
}

extension Coin {
    static let nativeChainIconDescriptors: [NativeChainIconDescriptor] = ChainRegistryEntry.all.map(\.nativeIconDescriptor)

    static func nativeChainIconDescriptor(forAssetIdentifier assetIdentifier: String) -> NativeChainIconDescriptor? {
        nativeChainIconDescriptors.first { $0.assetIdentifier == assetIdentifier }
    }

    static func nativeChainIconDescriptor(chainName: String) -> NativeChainIconDescriptor? {
        let normalizedChainName = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChainName.isEmpty else { return nil }
        let canonicalChainName = canonicalChainComponent(chainName: normalizedChainName, symbol: "")

        return nativeChainIconDescriptors.first { descriptor in
            descriptor.registryID.caseInsensitiveCompare(canonicalChainName) == .orderedSame
                || descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
    }

    static func nativeChainIconDescriptor(symbol: String, chainName: String? = nil) -> NativeChainIconDescriptor? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChainName = chainName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return nativeChainIconDescriptors.first { descriptor in
            let symbolMatches = descriptor.symbol.caseInsensitiveCompare(normalizedSymbol) == .orderedSame
            guard symbolMatches else { return false }

            if normalizedChainName.isEmpty {
                return true
            }

            return descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
    }

    static func nativeChainBadge(chainName: String) -> (assetIdentifier: String?, mark: String, color: Color)? {
        guard let descriptor = nativeChainIconDescriptor(chainName: chainName) else { return nil }
        return (descriptor.assetIdentifier, descriptor.mark, descriptor.color)
    }

    static func iconIdentifier(
        symbol: String,
        chainName: String,
        contractAddress: String? = nil,
        tokenStandard: String = "Native"
    ) -> String {
        let normalizedSymbol = symbol.lowercased()
        let trimmedContract = contractAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedChain = canonicalChainComponent(chainName: chainName, symbol: symbol)

        if !trimmedContract.isEmpty {
            return "token:\(normalizedChain):\(normalizedSymbol):\(trimmedContract.lowercased())"
        }

        let isNativeToken = tokenStandard.caseInsensitiveCompare("Native") == .orderedSame || tokenStandard.isEmpty
        let namespace = isNativeToken ? "native" : "asset"
        return "\(namespace):\(normalizedChain):\(normalizedSymbol)"
    }

    static func normalizedIconIdentifier(_ identifier: String) -> String {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedIdentifier.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3 else { return trimmedIdentifier }

        let namespace = components[0]
        let chainComponent = components[1]
        let symbolComponent = components[2]
        let canonicalChain = canonicalChainComponent(chainName: chainComponent, symbol: symbolComponent)
        var normalizedComponents = components
        normalizedComponents[1] = canonicalChain
        normalizedComponents[2] = symbolComponent.lowercased()
        if normalizedComponents.count >= 4 {
            normalizedComponents[3] = normalizedComponents[3].lowercased()
        }

        switch namespace {
        case "native", "asset", "token":
            normalizedComponents[0] = namespace
            return normalizedComponents.joined(separator: ":")
        default:
            return trimmedIdentifier
        }
    }

    private static func canonicalChainComponent(chainName: String, symbol: String) -> String {
        let normalizedChainName = chainName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let knownAliases: [String: String] = [
            "bitcoin": "bitcoin",
            "bitcoin cash": "bitcoin-cash",
            "bitcoin sv": "bitcoin-sv",
            "litecoin": "litecoin",
            "dogecoin": "dogecoin",
            "ethereum": "ethereum",
            "ethereum classic": "ethereum-classic",
            "arbitrum": "arbitrum",
            "optimism": "optimism",
            "bnb chain": "bnb",
            "avalanche": "avalanche",
            "hyperliquid": "hyperliquid",
            "tron": "tron",
            "solana": "solana",
            "stellar": "stellar",
            "cardano": "cardano",
            "xrp ledger": "xrp",
            "monero": "monero",
            "sui": "sui",
            "aptos": "aptos",
            "ton": "ton",
            "internet computer": "internet-computer",
            "near": "near",
            "polkadot": "polkadot"
        ]

        if let knownAlias = knownAliases[normalizedChainName] {
            return knownAlias
        }

        if let localizedMatch = ChainRegistryEntry.all.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedChainName
        }) {
            return localizedMatch.id
        }

        let nativeSymbolAliases: [String: String] = [
            "BTC": "bitcoin",
            "BCH": "bitcoin-cash",
            "BSV": "bitcoin-sv",
            "LTC": "litecoin",
            "DOGE": "dogecoin",
            "ETH": "ethereum",
            "ETC": "ethereum-classic",
            "ARB": "arbitrum",
            "OP": "optimism",
            "BNB": "bnb",
            "AVAX": "avalanche",
            "HYPE": "hyperliquid",
            "TRX": "tron",
            "SOL": "solana",
            "XLM": "stellar",
            "ADA": "cardano",
            "XRP": "xrp",
            "XMR": "monero",
            "SUI": "sui",
            "APT": "aptos",
            "TON": "ton",
            "ICP": "internet-computer",
            "NEAR": "near",
            "DOT": "polkadot"
        ]

        if let nativeSymbolAlias = nativeSymbolAliases[normalizedSymbol] {
            return nativeSymbolAlias
        }

        return normalizedChainName.replacingOccurrences(of: " ", with: "-")
    }

    /// Handles "displayMark" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func displayMark(for symbol: String) -> String {
        if let nativeDescriptor = nativeChainIconDescriptor(symbol: symbol) {
            return nativeDescriptor.mark
        }

        switch symbol {
        case "MATIC":
            return "P"
        case "ARB":
            return "AR"
        case "TRX", "USDT":
            return "T"
        default:
            if let tokenEntry = TokenVisualRegistryEntry.entry(symbol: symbol) {
                return tokenEntry.mark
            }
            return String(symbol.prefix(2)).uppercased()
        }
    }
    
    /// Handles "displayColor" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func displayColor(for symbol: String) -> Color {
        if let nativeDescriptor = nativeChainIconDescriptor(symbol: symbol) {
            return nativeDescriptor.color
        }

        switch symbol {
        case "MATIC":
            return .indigo
        case "TRX":
            return .red
        case "ARB":
            return .cyan
        case "USDT":
            return .green
        default:
            if let tokenEntry = TokenVisualRegistryEntry.entry(symbol: symbol) {
                return tokenEntry.color
            }
            return .gray
        }
    }

    var iconIdentifier: String {
        Self.iconIdentifier(
            symbol: symbol,
            chainName: chainName,
            contractAddress: contractAddress,
            tokenStandard: tokenStandard
        )
    }

    @MainActor init(snapshot: PersistedCoin) {
        self.init(
            name: snapshot.name,
            symbol: snapshot.symbol,
            marketDataID: snapshot.marketDataID,
            coinGeckoID: snapshot.coinGeckoID,
            chainName: snapshot.chainName,
            tokenStandard: snapshot.tokenStandard,
            contractAddress: snapshot.contractAddress,
            amount: snapshot.amount,
            priceUSD: snapshot.priceUSD,
            mark: Self.displayMark(for: snapshot.symbol),
            color: Self.displayColor(for: snapshot.symbol)
        )
    }
    
    var persistedSnapshot: PersistedCoin {
        PersistedCoin(
            name: name,
            symbol: symbol,
            marketDataID: marketDataID,
            coinGeckoID: coinGeckoID,
            chainName: chainName,
            tokenStandard: tokenStandard,
            contractAddress: contractAddress,
            amount: amount,
            priceUSD: priceUSD
        )
    }
}

extension ImportedWallet {
    @MainActor init(snapshot: PersistedWallet) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            bitcoinAddress: snapshot.bitcoinAddress,
            bitcoinXPub: snapshot.bitcoinXPub,
            bitcoinCashAddress: snapshot.bitcoinCashAddress,
            bitcoinSVAddress: snapshot.bitcoinSVAddress,
            litecoinAddress: snapshot.litecoinAddress,
            dogecoinAddress: snapshot.dogecoinAddress,
            ethereumAddress: snapshot.ethereumAddress,
            tronAddress: snapshot.tronAddress,
            solanaAddress: snapshot.solanaAddress,
            stellarAddress: snapshot.stellarAddress,
            xrpAddress: snapshot.xrpAddress,
            moneroAddress: snapshot.moneroAddress,
            cardanoAddress: snapshot.cardanoAddress,
            suiAddress: snapshot.suiAddress,
            aptosAddress: snapshot.aptosAddress,
            tonAddress: snapshot.tonAddress,
            icpAddress: snapshot.icpAddress,
            nearAddress: snapshot.nearAddress,
            polkadotAddress: snapshot.polkadotAddress,
            seedDerivationPreset: snapshot.seedDerivationPreset,
            seedDerivationPaths: snapshot.seedDerivationPaths,
            selectedChain: snapshot.selectedChain,
            holdings: snapshot.holdings.map(Coin.init(snapshot:)),
            includeInPortfolioTotal: snapshot.includeInPortfolioTotal
        )
    }

    var persistedSnapshot: PersistedWallet {
        PersistedWallet(
            id: id,
            name: name,
            bitcoinAddress: bitcoinAddress,
            bitcoinXPub: bitcoinXPub,
            bitcoinCashAddress: bitcoinCashAddress,
            bitcoinSVAddress: bitcoinSVAddress,
            litecoinAddress: litecoinAddress,
            dogecoinAddress: dogecoinAddress,
            ethereumAddress: ethereumAddress,
            tronAddress: tronAddress,
            solanaAddress: solanaAddress,
            stellarAddress: stellarAddress,
            xrpAddress: xrpAddress,
            moneroAddress: moneroAddress,
            cardanoAddress: cardanoAddress,
            suiAddress: suiAddress,
            aptosAddress: aptosAddress,
            tonAddress: tonAddress,
            icpAddress: icpAddress,
            nearAddress: nearAddress,
            polkadotAddress: polkadotAddress,
            seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths,
            selectedChain: selectedChain,
            holdings: holdings.map(\.persistedSnapshot),
            includeInPortfolioTotal: includeInPortfolioTotal
        )
    }
}

extension TransactionRecord {
    @MainActor init(snapshot: PersistedTransactionRecord) {
        self.init(
            id: snapshot.id,
            walletID: snapshot.walletID,
            kind: snapshot.kind,
            status: snapshot.status,
            walletName: snapshot.walletName,
            assetName: snapshot.assetName,
            symbol: snapshot.symbol,
            chainName: snapshot.chainName,
            amount: snapshot.amount,
            address: snapshot.address,
            transactionHash: snapshot.transactionHash,
            ethereumNonce: snapshot.ethereumNonce,
            receiptBlockNumber: snapshot.receiptBlockNumber,
            receiptGasUsed: snapshot.receiptGasUsed,
            receiptEffectiveGasPriceGwei: snapshot.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: snapshot.receiptNetworkFeeETH,
            dogecoinConfirmedNetworkFeeDOGE: snapshot.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: snapshot.dogecoinConfirmations,
            dogecoinFeePriorityRaw: snapshot.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: snapshot.dogecoinEstimatedFeeRateDOGEPerKB,
            dogecoinUsedChangeOutput: snapshot.dogecoinUsedChangeOutput,
            sourceDerivationPath: snapshot.sourceDerivationPath,
            changeDerivationPath: snapshot.changeDerivationPath,
            sourceAddress: snapshot.sourceAddress,
            changeAddress: snapshot.changeAddress,
            dogecoinRawTransactionHex: snapshot.dogecoinRawTransactionHex,
            failureReason: snapshot.failureReason,
            transactionHistorySource: snapshot.transactionHistorySource,
            createdAt: snapshot.createdAt
        )
    }
    
    var persistedSnapshot: PersistedTransactionRecord {
        PersistedTransactionRecord(
            id: id,
            walletID: walletID,
            kind: kind,
            status: status,
            walletName: walletName,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            amount: amount,
            address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce,
            receiptBlockNumber: receiptBlockNumber,
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: receiptNetworkFeeETH,
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations,
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: dogecoinEstimatedFeeRateDOGEPerKB,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAt: createdAt
        )
    }
    
    var titleText: String {
        switch kind {
        case .send:
            return "Sent \(symbol)"
        case .receive:
            return "Receive"
        }
    }
    
    var subtitleText: String {
        "\(assetName) on \(chainName) • \(walletName)"
    }

    var historySourceText: String? {
        guard let transactionHistorySource else { return nil }
        let trimmed = transactionHistorySource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "esplora":
            return "Esplora"
        case "litecoinspace":
            return "LitecoinSpace"
        case "blockchain.info":
            return "Blockchain.info"
        case "blockchair":
            return "Blockchair"
        case "dogecoin.providers":
            return "DOGE Providers"
        case "rpc":
            return "RPC"
        default:
            return trimmed
        }
    }

    var historySourceConfidenceText: String? {
        guard let transactionHistorySource else { return nil }
        let source = transactionHistorySource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !source.isEmpty else { return nil }

        let score: Int
        switch (chainName, source) {
        case ("Bitcoin", "esplora"),
             ("Bitcoin SV", "blockchair"),
             ("Litecoin", "litecoinspace"),
             ("Dogecoin", "dogecoin.providers"):
            score = 3
        case (_, "etherscan"),
             (_, "blockscout"),
             (_, "ethplorer"),
             (_, "blockchair"),
             (_, "blockcypher"),
             (_, "blockchain.info"):
            score = 2
        case (_, "rpc"):
            score = 1
        default:
            score = 1
        }

        switch score {
        case 3: return "High"
        case 2: return "Medium"
        default: return "Low"
        }
    }
    
    var statusText: String {
        status.rawValue.capitalized
    }
    
    var badgeMark: String {
        switch kind {
        case .send:
            return "OUT"
        case .receive:
            return "IN"
        }
    }
    
    var badgeColor: Color {
        switch kind {
        case .send:
            return .red
        case .receive:
            return .green
        }
    }
    
    var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .confirmed:
            return .mint
        case .failed:
            return .red
        }
    }
    
    var amountText: String? {
        guard amount > 0 else { return nil }
        return String(format: "%.4f %@", amount, symbol)
    }

    var addressPreviewText: String {
        address
    }

    var receiptBlockNumberText: String? {
        guard let receiptBlockNumber else { return nil }
        return String(receiptBlockNumber)
    }

    var receiptEffectiveGasPriceText: String? {
        guard let receiptEffectiveGasPriceGwei else { return nil }
        return String(format: "%.3f gwei", receiptEffectiveGasPriceGwei)
    }

    var receiptNetworkFeeText: String? {
        guard let receiptNetworkFeeETH else { return nil }
        return String(format: "%.8f ETH", receiptNetworkFeeETH)
    }

    var dogecoinConfirmationsText: String? {
        guard chainName == "Dogecoin",
              let dogecoinConfirmations else { return nil }
        return "\(dogecoinConfirmations) conf"
    }
    
    var fullTimestampText: String {
        createdAt.formatted(date: .abbreviated, time: .standard)
    }

    var transactionExplorerURL: URL? {
        guard let transactionHash, !transactionHash.isEmpty else { return nil }
        return ChainBackendRegistry.ExplorerRegistry.transactionURL(for: chainName, transactionHash: transactionHash)
    }

    var transactionExplorerLabel: String? {
        guard transactionHash != nil else { return nil }
        return ChainBackendRegistry.ExplorerRegistry.transactionLabel(for: chainName)
    }
}

extension PriceAlertRule {
    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(snapshot: PersistedPriceAlertRule) {
        self.init(
            id: snapshot.id,
            holdingKey: snapshot.holdingKey,
            assetName: snapshot.assetName,
            symbol: snapshot.symbol,
            chainName: snapshot.chainName,
            targetPrice: snapshot.targetPrice,
            condition: snapshot.condition,
            isEnabled: snapshot.isEnabled,
            hasTriggered: snapshot.hasTriggered
        )
    }
    
    var persistedSnapshot: PersistedPriceAlertRule {
        PersistedPriceAlertRule(
            id: id,
            holdingKey: holdingKey,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            targetPrice: targetPrice,
            condition: condition,
            isEnabled: isEnabled,
            hasTriggered: hasTriggered
        )
    }
}

struct CoinBadge: View {
    let assetIdentifier: String?
    let fallbackText: String
    let color: Color
    var size: CGFloat = 40

    @AppStorage(TokenIconPreferenceStore.defaultsKey) private var tokenIconPreferencesStorage = ""
    @AppStorage(TokenIconPreferenceStore.customImageRevisionDefaultsKey) private var tokenIconCustomImageRevision = 0

    private var resolvedAssetIdentifier: String {
        if let assetIdentifier {
            return Coin.normalizedIconIdentifier(assetIdentifier)
        }
        return "generic:\(fallbackText.lowercased())"
    }

    private var tokenIconAssetName: String? {
        if let nativeDescriptor = Coin.nativeChainIconDescriptor(forAssetIdentifier: resolvedAssetIdentifier) {
            return nativeDescriptor.assetName
        }
        return TokenVisualRegistryEntry.entry(matchingAssetIdentifier: resolvedAssetIdentifier)?.assetName
    }

    private var preferredIconStyle: TokenIconStyle {
        TokenIconPreferenceStore.preference(
            for: resolvedAssetIdentifier,
            storage: tokenIconPreferencesStorage
        )
    }
    
    var body: some View {
        ZStack {
            if preferredIconStyle == .customPhoto, let customImage = customTokenImage {
                Image(uiImage: customImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else if preferredIconStyle == .artwork, let tokenIconAssetName {
                Image(tokenIconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: size, height: size)
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: size * 0.38, height: size * 0.38)
                    .offset(x: -size * 0.16, y: -size * 0.16)
                Text(fallbackText)
                    .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .shadow(color: color.opacity(0.18), radius: 6, y: 3)
    }

    private var customTokenImage: UIImage? {
#if canImport(UIKit)
        _ = tokenIconCustomImageRevision
        return TokenIconImageStore.image(for: resolvedAssetIdentifier)
#else
        return nil
#endif
    }
}

enum TokenIconStyle: String, CaseIterable, Identifiable {
    case artwork
    case customPhoto
    case classicBadge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artwork:
            return "Artwork"
        case .customPhoto:
            return "Photo"
        case .classicBadge:
            return "Classic"
        }
    }
}

enum TokenIconPreferenceStore {
    static let defaultsKey = "settings.tokenIconPreferences.v1"
    static let customImageRevisionDefaultsKey = "settings.tokenIconCustomImageRevision.v1"

    static func preference(for identifier: String, storage: String) -> TokenIconStyle {
        let preferences = storedPreferences(from: storage)
        return preferences[identifier] ?? .artwork
    }

    static func updatePreference(
        _ preference: TokenIconStyle,
        for identifier: String,
        storage: String
    ) -> String {
        var preferences = storedPreferences(from: storage)
        if preference == .artwork {
            preferences.removeValue(forKey: identifier)
        } else {
            preferences[identifier] = preference
        }
        return encodedStorage(from: preferences)
    }

    private static func storedPreferences(from storage: String) -> [String: TokenIconStyle] {
        guard let data = storage.data(using: .utf8),
              let rawPreferences = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return rawPreferences.reduce(into: [:]) { partialResult, entry in
            if let preference = TokenIconStyle(rawValue: entry.value) {
                partialResult[entry.key] = preference
            }
        }
    }

    private static func encodedStorage(from preferences: [String: TokenIconStyle]) -> String {
        guard !preferences.isEmpty else { return "" }
        let rawPreferences = preferences.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(rawPreferences),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }
}

enum TokenIconImageStore {
    static let maximumUploadBytes = 3 * 1024 * 1024

    enum IconError: LocalizedError {
        case imageTooLarge
        case unreadableImage
        case failedToWrite

        var errorDescription: String? {
            switch self {
            case .imageTooLarge:
                return "Selected images must be 3 MB or smaller."
            case .unreadableImage:
                return "The selected photo could not be read as an image."
            case .failedToWrite:
                return "The custom icon could not be saved."
            }
        }
    }

    static func hasCustomImage(for identifier: String) -> Bool {
        guard let url = customImageURL(for: identifier) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

#if canImport(UIKit)
    static func image(for identifier: String) -> UIImage? {
        guard let url = customImageURL(for: identifier), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    static func saveImageData(_ data: Data, for identifier: String) throws {
        guard data.count <= maximumUploadBytes else {
            throw IconError.imageTooLarge
        }
        guard let sourceImage = UIImage(data: data) else {
            throw IconError.unreadableImage
        }
        let normalizedImage = resizedImage(from: sourceImage, targetSize: CGSize(width: 256, height: 256))
        guard let pngData = normalizedImage.pngData(),
              let url = customImageURL(for: identifier) else {
            throw IconError.failedToWrite
        }
        do {
            let directoryURL = try customIconDirectoryURL()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try pngData.write(to: url, options: .atomic)
        } catch {
            throw IconError.failedToWrite
        }
    }

    private static func resizedImage(from image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

            let aspectRatio = min(targetSize.width / max(image.size.width, 1), targetSize.height / max(image.size.height, 1))
            let drawnSize = CGSize(width: image.size.width * aspectRatio, height: image.size.height * aspectRatio)
            let origin = CGPoint(
                x: (targetSize.width - drawnSize.width) / 2,
                y: (targetSize.height - drawnSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawnSize))
        }
    }
#endif

    static func removeImage(for identifier: String) {
        guard let url = customImageURL(for: identifier), FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func removeAllImages() {
        guard let directoryURL = try? customIconDirectoryURL(),
              FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func customImageURL(for identifier: String) -> URL? {
        try? customIconDirectoryURL().appendingPathComponent(fileName(for: identifier))
    }

    private static func customIconDirectoryURL() throws -> URL {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportDirectory
            .appendingPathComponent("Spectra", isDirectory: true)
            .appendingPathComponent("TokenIcons", isDirectory: true)
    }

    private static func fileName(for identifier: String) -> String {
        let sanitizedMark = identifier.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
        return "\(sanitizedMark).png"
    }
}

struct ChainToggleLabel: View {
    let title: String
    let symbol: String
    let mark: String
    var assetIdentifier: String? = nil
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            CoinBadge(assetIdentifier: assetIdentifier, fallbackText: mark, color: color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(symbol)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SpectraBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backdropGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Circle()
                .fill(Color.red.opacity(0.45))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -120, y: -220)
            
            Circle()
                .fill(Color.orange.opacity(0.45))
                .frame(width: 240, height: 240)
                .blur(radius: 65)
                .offset(x: 100, y: -170)
            
            Circle()
                .fill(Color.green.opacity(0.35))
                .frame(width: 230, height: 230)
                .blur(radius: 70)
                .offset(x: -140, y: 40)
            
            Circle()
                .fill(Color.blue.opacity(0.4))
                .frame(width: 260, height: 260)
                .blur(radius: 75)
                .offset(x: 140, y: 120)
            
            Circle()
                .fill(Color.purple.opacity(0.36))
                .frame(width: 250, height: 250)
                .blur(radius: 80)
                .offset(x: 0, y: 260)
        }
        .ignoresSafeArea()
    }

    private var backdropGradientColors: [Color] {
        if colorScheme == .light {
            return [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(red: 0.93, green: 0.95, blue: 0.98)
            ]
        }
        return [
            Color(red: 0.08, green: 0.12, blue: 0.22),
            Color(red: 0.12, green: 0.08, blue: 0.18),
            Color(red: 0.04, green: 0.1, blue: 0.16)
        ]
    }
}

extension View {
    func spectraNumericTextLayout(minimumScaleFactor: CGFloat = 0.62) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
            .allowsTightening(true)
    }
}

struct SpectraLogo: View {
    var size: CGFloat = 78
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.75))
                            .frame(width: size * 0.7, height: size * 0.7)
                            .blur(radius: size * 0.14)
                            .offset(x: -size * 0.2, y: -size * 0.18)
                        Circle()
                            .fill(Color.yellow.opacity(0.72))
                            .frame(width: size * 0.6, height: size * 0.6)
                            .blur(radius: size * 0.14)
                            .offset(x: size * 0.18, y: -size * 0.16)
                        Circle()
                            .fill(Color.green.opacity(0.62))
                            .frame(width: size * 0.58, height: size * 0.58)
                            .blur(radius: size * 0.14)
                            .offset(x: -size * 0.16, y: size * 0.16)
                        Circle()
                            .fill(Color.blue.opacity(0.68))
                            .frame(width: size * 0.62, height: size * 0.62)
                            .blur(radius: size * 0.15)
                            .offset(x: size * 0.2, y: size * 0.18)
                        Circle()
                            .fill(Color.purple.opacity(0.55))
                            .frame(width: size * 0.52, height: size * 0.52)
                            .blur(radius: size * 0.16)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                )
                .glassEffect(.regular.tint(.white.opacity(0.044)), in: .rect(cornerRadius: size * 0.28))
            
            Text("S")
                .font(.system(size: size * 0.62, weight: .black, design: .rounded))
                .foregroundStyle(Color.primary)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .rotationEffect(.degrees(-8))
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

enum PricingProvider: String, CaseIterable, Identifiable {
    case coinGecko = "CoinGecko"
    case binance = "Binance Public API"
    case coinbaseExchange = "Coinbase Exchange API"
    case coinPaprika = "CoinPaprika"
    case coinLore = "CoinLore"
    
    var id: String { rawValue }
}

enum FiatRateProvider: String, CaseIterable, Identifiable {
    case openER = "Open ER"
    case exchangeRateHost = "ExchangeRate.host"
    case frankfurter = "Frankfurter API"
    case fawazAhmed = "Fawaz Ahmed Currency API"

    var id: String { rawValue }
}

enum FiatCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cny = "CNY"
    case inr = "INR"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case brl = "BRL"
    case sgd = "SGD"
    case aed = "AED"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar (USD)"
        case .eur: return "Euro (EUR)"
        case .gbp: return "British Pound (GBP)"
        case .jpy: return "Japanese Yen (JPY)"
        case .cny: return "Chinese Yuan (CNY)"
        case .inr: return "Indian Rupee (INR)"
        case .cad: return "Canadian Dollar (CAD)"
        case .aud: return "Australian Dollar (AUD)"
        case .chf: return "Swiss Franc (CHF)"
        case .brl: return "Brazilian Real (BRL)"
        case .sgd: return "Singapore Dollar (SGD)"
        case .aed: return "UAE Dirham (AED)"
        }
    }

}

enum CoinGeckoService {
    private struct CoinGeckoEndpointAttempt {
        let baseURL: String
        let headerName: String?
        let queryItemName: String?
    }

    /// Handles "fetchQuotes" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func fetchQuotes(for ids: [String], apiKey: String) async throws -> [String: Double] {
        let normalizedIDs = Array(
            Set(
                ids.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                .filter { !$0.isEmpty }
            )
        ).sorted()
        guard !normalizedIDs.isEmpty else { return [:] }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let attempts: [CoinGeckoEndpointAttempt]
        if trimmedAPIKey.isEmpty {
            attempts = [
                CoinGeckoEndpointAttempt(
                    baseURL: ChainBackendRegistry.MarketDataRegistry.coinGeckoSimplePriceURL,
                    headerName: nil,
                    queryItemName: nil
                )
            ]
        } else {
            attempts = [
                CoinGeckoEndpointAttempt(
                    baseURL: "https://pro-api.coingecko.com/api/v3/simple/price",
                    headerName: "x-cg-pro-api-key",
                    queryItemName: "x_cg_pro_api_key"
                ),
                CoinGeckoEndpointAttempt(
                    baseURL: ChainBackendRegistry.MarketDataRegistry.coinGeckoSimplePriceURL,
                    headerName: "x-cg-demo-api-key",
                    queryItemName: "x_cg_demo_api_key"
                )
            ]
        }

        var lastError: Error = URLError(.badServerResponse)
        for attempt in attempts {
            var components = URLComponents(string: attempt.baseURL)
            var queryItems = [
                URLQueryItem(name: "ids", value: normalizedIDs.joined(separator: ",")),
                URLQueryItem(name: "vs_currencies", value: "usd")
            ]
            if let queryItemName = attempt.queryItemName, !trimmedAPIKey.isEmpty {
                queryItems.append(URLQueryItem(name: queryItemName, value: trimmedAPIKey))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                lastError = URLError(.badURL)
                continue
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
            if let headerName = attempt.headerName, !trimmedAPIKey.isEmpty {
                request.setValue(trimmedAPIKey, forHTTPHeaderField: headerName)
            }

            do {
                let (data, response) = try await SpectraNetworkRouter.shared.data(
                    for: request,
                    profile: .chainRead
                )
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ..< 300).contains(httpResponse.statusCode) else {
                    lastError = URLError(.badServerResponse)
                    continue
                }

                let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: data)
                let prices = decoded.reduce(into: [String: Double]()) { result, entry in
                    if let usdPrice = entry.value["usd"] {
                        result[entry.key.lowercased()] = usdPrice
                    }
                }
                if !prices.isEmpty {
                    return prices
                }
                lastError = URLError(.zeroByteResource)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }
}

private struct BinanceTickerPriceResponse: Decodable {
    let symbol: String
    let price: String
}

private struct CoinbaseExchangeRatesEnvelope: Decodable {
    struct Payload: Decodable {
        let rates: [String: String]
    }

    let data: Payload
}

private struct CoinPaprikaTicker: Decodable {
    struct Quotes: Decodable {
        struct USD: Decodable {
            let price: Double?
        }

        let usd: USD?

        enum CodingKeys: String, CodingKey {
            case usd = "USD"
        }
    }

    let id: String
    let name: String
    let symbol: String
    let quotes: Quotes?
}

private struct CoinLoreTickersResponse: Decodable {
    let data: [CoinLoreTicker]
}

private struct CoinLoreTicker: Decodable {
    let id: String
    let symbol: String
    let name: String
    let nameid: String
    let priceUSD: String

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case nameid
        case priceUSD = "price_usd"
    }
}

enum LivePriceService {
    static func fetchQuotes(for coins: [Coin], provider: PricingProvider, coinGeckoAPIKey: String) async throws -> [String: Double] {
        switch provider {
        case .coinGecko:
            return try await fetchCoinGeckoQuotes(for: coins, apiKey: coinGeckoAPIKey)
        case .binance:
            return try await fetchBinanceQuotes(for: coins)
        case .coinbaseExchange:
            return try await fetchCoinbaseExchangeQuotes(for: coins)
        case .coinPaprika:
            return try await fetchCoinPaprikaQuotes(for: coins)
        case .coinLore:
            return try await fetchCoinLoreQuotes(for: coins)
        }
    }

    private static func fetchCoinGeckoQuotes(for coins: [Coin], apiKey: String) async throws -> [String: Double] {
        let grouped = Dictionary(grouping: coins.compactMap { coin -> (String, Coin)? in
            let normalizedID = coin.coinGeckoID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedID.isEmpty else { return nil }
            return (normalizedID, coin)
        }, by: \.0)
        guard !grouped.isEmpty else { return [:] }

        let fetched = try await CoinGeckoService.fetchQuotes(for: grouped.keys.sorted(), apiKey: apiKey)
        var resolved: [String: Double] = [:]
        for (id, price) in fetched {
            for (_, coin) in grouped[id] ?? [] {
                resolved[coin.holdingKey] = price
            }
        }
        return resolved
    }

    private static func fetchBinanceQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.binanceTickerPriceURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([BinanceTickerPriceResponse].self, from: data)
        let priceBySymbol: [String: Double] = Dictionary(uniqueKeysWithValues: decoded.compactMap { ticker -> (String, Double)? in
            guard let price = Double(ticker.price), price > 0 else { return nil }
            return (ticker.symbol.uppercased(), price)
        })

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            let symbol = coin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let candidates = ["\(symbol)USDT", "\(symbol)FDUSD", "\(symbol)USDC"]
            if let candidate = candidates.first(where: { priceBySymbol[$0] != nil }),
               let price = priceBySymbol[candidate] {
                resolved[coin.holdingKey] = price
            }
        }
        return resolved
    }

    private static func fetchCoinbaseExchangeQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.coinbaseExchangeRatesURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(CoinbaseExchangeRatesEnvelope.self, from: data)

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            let symbol = coin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let rawRate = decoded.data.rates[symbol],
                  let rate = Double(rawRate),
                  rate > 0 else {
                continue
            }
            resolved[coin.holdingKey] = 1.0 / rate
        }
        return resolved
    }

    private static func fetchCoinPaprikaQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.coinPaprikaTickersURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([CoinPaprikaTicker].self, from: data)

        let byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        var bySymbol: [String: CoinPaprikaTicker] = [:]
        for ticker in decoded {
            let symbol = ticker.symbol.uppercased()
            if bySymbol[symbol] == nil {
                bySymbol[symbol] = ticker
            }
        }

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            if let id = coinPaprikaID(for: coin),
               let ticker = byID[id],
               let price = ticker.quotes?.usd?.price,
               price > 0 {
                resolved[coin.holdingKey] = price
                continue
            }
            if let ticker = bySymbol[coin.symbol.uppercased()],
               let price = ticker.quotes?.usd?.price,
               price > 0 {
                resolved[coin.holdingKey] = price
            }
        }
        return resolved
    }

    private static func fetchCoinLoreQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.coinLoreTickersURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(CoinLoreTickersResponse.self, from: data)

        var bySymbol: [String: CoinLoreTicker] = [:]
        for ticker in decoded.data {
            let symbol = ticker.symbol.uppercased()
            if bySymbol[symbol] == nil {
                bySymbol[symbol] = ticker
            }
        }

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            guard let ticker = bySymbol[coin.symbol.uppercased()],
                  let price = Double(ticker.priceUSD),
                  price > 0 else {
                continue
            }
            resolved[coin.holdingKey] = price
        }
        return resolved
    }

    private static func stablecoinQuotes(for coins: [Coin]) -> [String: Double] {
        var resolved: [String: Double] = [:]
        for coin in coins {
            if isUSDStablecoin(coin.symbol) {
                resolved[coin.holdingKey] = 1.0
            }
        }
        return resolved
    }

    private static func isUSDStablecoin(_ symbol: String) -> Bool {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["USDT", "USDC", "DAI", "FDUSD", "TUSD", "BUSD", "USDE", "PYUSD", "USDS", "USDD", "USDG", "USD1"].contains(normalized)
    }

    private static func coinPaprikaID(for coin: Coin) -> String? {
        let normalizedGeckoID = coin.coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let idByGeckoID: [String: String] = [
            "bitcoin": "btc-bitcoin",
            "ethereum": "eth-ethereum",
            "optimism": "op-optimism",
            "binancecoin": "bnb-binance-coin",
            "bitcoin-cash": "bch-bitcoin-cash",
            "litecoin": "ltc-litecoin",
            "dogecoin": "doge-dogecoin",
            "cardano": "ada-cardano",
            "solana": "sol-solana",
            "tron": "trx-tron",
            "stellar": "xlm-stellar",
            "xrp": "xrp-xrp",
            "monero": "xmr-monero",
            "ethereum-classic": "etc-ethereum-classic",
            "sui": "sui-sui",
            "internet-computer": "icp-internet-computer",
            "near": "near-near-protocol",
            "polkadot": "dot-polkadot",
            "hyperliquid": "hype-hyperliquid",
            "tether": "usdt-tether",
            "usd-coin": "usdc-usd-coin",
            "dai": "dai-dai",
            "wrapped-bitcoin": "wbtc-wrapped-bitcoin",
            "chainlink": "link-chainlink",
            "uniswap": "uni-uniswap",
            "aave": "aave-aave",
            "shiba-inu": "shib-shiba-inu",
            "pepe": "pepe-pepe",
            "bitget-token": "bgb-bitget-token",
            "leo-token": "leo-unus-sed-leo",
            "cronos": "cro-cronos",
            "ethena-usde": "usde-ethena-usde",
            "ripple-usd": "rlusd-ripple-usd",
            "pax-gold": "paxg-pax-gold",
            "tether-gold": "xaut-tether-gold",
            "usdd": "usdd-usdd",
            "global-dollar": "usdg-global-dollar"
        ]
        if let id = idByGeckoID[normalizedGeckoID] {
            return id
        }

        let symbol = coin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let idBySymbol: [String: String] = [
            "BTC": "btc-bitcoin",
            "ETH": "eth-ethereum",
            "OP": "op-optimism",
            "BNB": "bnb-binance-coin",
            "BCH": "bch-bitcoin-cash",
            "BSV": "bsv-bitcoin-sv",
            "LTC": "ltc-litecoin",
            "DOGE": "doge-dogecoin",
            "ADA": "ada-cardano",
            "SOL": "sol-solana",
            "TRX": "trx-tron",
            "XLM": "xlm-stellar",
            "XRP": "xrp-xrp",
            "XMR": "xmr-monero",
            "ETC": "etc-ethereum-classic",
            "SUI": "sui-sui",
            "ICP": "icp-internet-computer",
            "NEAR": "near-near-protocol",
            "HYPE": "hype-hyperliquid",
            "USDT": "usdt-tether",
            "USDC": "usdc-usd-coin",
            "DAI": "dai-dai",
            "BGB": "bgb-bitget-token",
            "LEO": "leo-unus-sed-leo",
            "CRO": "cro-cronos",
            "USDE": "usde-ethena-usde",
            "RLUSD": "rlusd-ripple-usd",
            "PAXG": "paxg-pax-gold",
            "XAUT": "xaut-tether-gold",
            "USDD": "usdd-usdd",
            "USDG": "usdg-global-dollar"
        ]
        return idBySymbol[symbol]
    }
}

extension SeedDerivationPaths {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        isCustomEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCustomEnabled) ?? false
        bitcoin = try container.decodeIfPresent(String.self, forKey: .bitcoin) ?? SeedDerivationChain.bitcoin.defaultPath
        bitcoinCash = try container.decodeIfPresent(String.self, forKey: .bitcoinCash) ?? SeedDerivationChain.bitcoinCash.defaultPath
        bitcoinSV = try container.decodeIfPresent(String.self, forKey: .bitcoinSV) ?? SeedDerivationChain.bitcoinSV.defaultPath
        litecoin = try container.decodeIfPresent(String.self, forKey: .litecoin) ?? SeedDerivationChain.litecoin.defaultPath
        dogecoin = try container.decodeIfPresent(String.self, forKey: .dogecoin) ?? SeedDerivationChain.dogecoin.defaultPath
        ethereum = try container.decodeIfPresent(String.self, forKey: .ethereum) ?? SeedDerivationChain.ethereum.defaultPath
        ethereumClassic = try container.decodeIfPresent(String.self, forKey: .ethereumClassic) ?? SeedDerivationChain.ethereumClassic.defaultPath
        arbitrum = try container.decodeIfPresent(String.self, forKey: .arbitrum) ?? SeedDerivationChain.arbitrum.defaultPath
        optimism = try container.decodeIfPresent(String.self, forKey: .optimism) ?? SeedDerivationChain.optimism.defaultPath
        avalanche = try container.decodeIfPresent(String.self, forKey: .avalanche) ?? SeedDerivationChain.avalanche.defaultPath
        hyperliquid = try container.decodeIfPresent(String.self, forKey: .hyperliquid) ?? SeedDerivationChain.hyperliquid.defaultPath
        tron = try container.decodeIfPresent(String.self, forKey: .tron) ?? SeedDerivationChain.tron.defaultPath
        solana = try container.decodeIfPresent(String.self, forKey: .solana) ?? SeedDerivationChain.solana.defaultPath
        stellar = try container.decodeIfPresent(String.self, forKey: .stellar) ?? SeedDerivationChain.stellar.defaultPath
        xrp = try container.decodeIfPresent(String.self, forKey: .xrp) ?? SeedDerivationChain.xrp.defaultPath
        cardano = try container.decodeIfPresent(String.self, forKey: .cardano) ?? SeedDerivationChain.cardano.defaultPath
        sui = try container.decodeIfPresent(String.self, forKey: .sui) ?? SeedDerivationChain.sui.defaultPath
        aptos = try container.decodeIfPresent(String.self, forKey: .aptos) ?? SeedDerivationChain.aptos.defaultPath
        ton = try container.decodeIfPresent(String.self, forKey: .ton) ?? SeedDerivationChain.ton.defaultPath
        internetComputer = try container.decodeIfPresent(String.self, forKey: .internetComputer) ?? SeedDerivationChain.internetComputer.defaultPath
        near = try container.decodeIfPresent(String.self, forKey: .near) ?? SeedDerivationChain.near.defaultPath
        polkadot = try container.decodeIfPresent(String.self, forKey: .polkadot) ?? SeedDerivationChain.polkadot.defaultPath
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        try container.encode(isCustomEnabled, forKey: .isCustomEnabled)
        try container.encode(bitcoin, forKey: .bitcoin)
        try container.encode(bitcoinCash, forKey: .bitcoinCash)
        try container.encode(bitcoinSV, forKey: .bitcoinSV)
        try container.encode(litecoin, forKey: .litecoin)
        try container.encode(dogecoin, forKey: .dogecoin)
        try container.encode(ethereum, forKey: .ethereum)
        try container.encode(ethereumClassic, forKey: .ethereumClassic)
        try container.encode(arbitrum, forKey: .arbitrum)
        try container.encode(optimism, forKey: .optimism)
        try container.encode(avalanche, forKey: .avalanche)
        try container.encode(hyperliquid, forKey: .hyperliquid)
        try container.encode(tron, forKey: .tron)
        try container.encode(solana, forKey: .solana)
        try container.encode(stellar, forKey: .stellar)
        try container.encode(xrp, forKey: .xrp)
        try container.encode(cardano, forKey: .cardano)
        try container.encode(sui, forKey: .sui)
        try container.encode(aptos, forKey: .aptos)
        try container.encode(ton, forKey: .ton)
        try container.encode(internetComputer, forKey: .internetComputer)
        try container.encode(near, forKey: .near)
        try container.encode(polkadot, forKey: .polkadot)
    }
}
private struct OpenERRatesResponse: Decodable {
    let rates: [String: Double]
}

private struct FrankfurterRatesResponse: Decodable {
    let rates: [String: Double]
}

private struct ExchangeRateHostLiveResponse: Decodable {
    let quotes: [String: Double]?
}

private struct FawazAhmedUSDRatesResponse: Decodable {
    let usd: [String: Double]
}

enum FiatRateService {
    static func fetchRates(from provider: FiatRateProvider, currencies: [FiatCurrency]) async throws -> [String: Double] {
        let targets = currencies.filter { $0 != .usd }
        switch provider {
        case .openER:
            return try await fetchOpenERRates(currencies: targets)
        case .exchangeRateHost:
            return try await fetchExchangeRateHostRates(currencies: targets)
        case .frankfurter:
            return try await fetchFrankfurterRates(currencies: targets)
        case .fawazAhmed:
            return try await fetchFawazAhmedRates(currencies: targets)
        }
    }

    private static func fetchOpenERRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.openERLatestUSDURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenERRatesResponse.self, from: data)
        return filteredRates(decoded.rates, allowedCurrencies: currencies)
    }

    private static func fetchFrankfurterRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        var components = URLComponents(string: ChainBackendRegistry.MarketDataRegistry.frankfurterLatestURL)
        components?.queryItems = [
            URLQueryItem(name: "from", value: "USD"),
            URLQueryItem(name: "to", value: currencies.map(\.rawValue).joined(separator: ","))
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(FrankfurterRatesResponse.self, from: data)
        return filteredRates(decoded.rates, allowedCurrencies: currencies)
    }

    private static func fetchExchangeRateHostRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        var components = URLComponents(string: ChainBackendRegistry.MarketDataRegistry.exchangeRateHostLiveURL)
        components?.queryItems = [
            URLQueryItem(name: "source", value: "USD"),
            URLQueryItem(name: "currencies", value: currencies.map(\.rawValue).joined(separator: ","))
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ExchangeRateHostLiveResponse.self, from: data)
        let quotes = decoded.quotes ?? [:]
        return Dictionary(uniqueKeysWithValues: currencies.compactMap { currency in
            guard let rate = quotes["USD\(currency.rawValue)"] else { return nil }
            return (currency.rawValue, rate)
        })
    }

    private static func fetchFawazAhmedRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.fawazAhmedUSDRatesURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(FawazAhmedUSDRatesResponse.self, from: data)
        let normalized = Dictionary(uniqueKeysWithValues: decoded.usd.map { ($0.key.uppercased(), $0.value) })
        return filteredRates(normalized, allowedCurrencies: currencies)
    }

    private static func filteredRates(_ rates: [String: Double], allowedCurrencies: [FiatCurrency]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: allowedCurrencies.compactMap { currency in
            guard let rate = rates[currency.rawValue], rate > 0 else { return nil }
            return (currency.rawValue, rate)
        })
    }
}
