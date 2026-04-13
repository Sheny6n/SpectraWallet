import Foundation

// MARK: - RustBalanceDecoder
enum RustBalanceDecoder {
    static func uint64Field(_ field: String, from json: String) -> UInt64? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.uint64Value }
        if let s = obj[field] as? String   { return UInt64(s) }
        return nil
    }
    static func int64Field(_ field: String, from json: String) -> Int64? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.int64Value }
        if let s = obj[field] as? String   { return Int64(s) }
        return nil
    }
    static func uint128StringField(_ field: String, from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.doubleValue }
        if let s = obj[field] as? String   { return Double(s) }
        return nil
    }
    static func evmNativeBalance(from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let s = obj["balance_display"] as? String, let v = Double(s) { return v }
        if let n = obj["balance_wei"] as? NSNumber { return n.doubleValue / 1e18 }
        if let s = obj["balance_wei"] as? String, let wei = Double(s) { return wei / 1e18 }
        return nil
    }
    static func yoctoNearToDouble(from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let s = obj["near_display"] as? String, let v = Double(s) { return v }
        if let s = obj["yocto_near"] as? String, let yocto = Double(s) { return yocto / 1e24 }
        if let n = obj["yocto_near"] as? NSNumber { return n.doubleValue / 1e24 }
        return nil
    }
    private static func parseObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Bitcoin
enum BitcoinNetworkMode: String, CaseIterable, Identifiable, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet:  return "Mainnet"
        case .testnet:  return "Testnet"
        case .testnet4: return "Testnet4"
        case .signet:   return "Signet"
        }}
}
struct BitcoinHistorySnapshot: Equatable {
    let txid: String
    let amountBTC: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}
struct BitcoinHistoryPage {
    let snapshots: [BitcoinHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

// MARK: - Dogecoin
enum DogecoinNetworkMode: String, CaseIterable, Codable, Identifiable {
    case mainnet
    case testnet
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        }}
}
struct DogecoinTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int?
    let networkFeeDOGE: Double?
    let confirmations: Int?
}
enum DogecoinBalanceService {
    typealias NetworkMode = DogecoinNetworkMode
    struct AddressTransactionSnapshot {
        let hash: String
        let kind: TransactionKind
        let status: TransactionStatus
        let amount: Double
        let counterpartyAddress: String
        let createdAt: Date
        let blockNumber: Int?
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.dogecoinChainName) }
    static func endpointCatalogByNetwork() -> [(title: String, endpoints: [String])] { AppEndpointDirectory.groupedSettingsEntries(for: ChainBackendRegistry.dogecoinChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.dogecoinChainName) }
}

// MARK: - EVM
struct EthereumCustomFeeConfiguration: Equatable {
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
}
struct EthereumTransactionReceipt: Equatable {
    let transactionHash: String
    let blockNumber: Int?
    let status: String?
    let gasUsed: Decimal?
    let effectiveGasPriceWei: Decimal?
    var isConfirmed: Bool { blockNumber != nil }
    var isFailed: Bool {
        guard let status else { return false }
        return status.lowercased() == "0x0"
    }
    var gasUsedText: String? {
        guard let gasUsed else { return nil }
        return NSDecimalNumber(decimal: gasUsed).stringValue
    }
    var effectiveGasPriceGwei: Double? {
        guard let effectiveGasPriceWei else { return nil }
        let gweiValue = effectiveGasPriceWei / Decimal(1_000_000_000)
        return NSDecimalNumber(decimal: gweiValue).doubleValue
    }
    var networkFeeETH: Double? {
        guard let gasUsed, let effectiveGasPriceWei else { return nil }
        let feeWei = gasUsed * effectiveGasPriceWei
        let feeETH = feeWei / Decimal(string: "1000000000000000000")!
        return NSDecimalNumber(decimal: feeETH).doubleValue
    }
}
struct EthereumTokenBalanceSnapshot: Equatable {
    let contractAddress: String
    let symbol: String
    let balance: Decimal
    let decimals: Int
}
struct EthereumTokenTransferSnapshot: Equatable {
    let contractAddress: String
    let tokenName: String
    let symbol: String
    let decimals: Int
    let fromAddress: String
    let toAddress: String
    let amount: Decimal
    let transactionHash: String
    let blockNumber: Int
    let logIndex: Int
    let timestamp: Date?
}
struct EthereumNativeTransferSnapshot: Equatable {
    let fromAddress: String
    let toAddress: String
    let amount: Decimal
    let transactionHash: String
    let blockNumber: Int
    let timestamp: Date?
}
struct EthereumSupportedToken {
    let name: String
    let symbol: String
    let contractAddress: String
    let decimals: Int
    let marketDataID: String
    let coinGeckoID: String
    init(name: String, symbol: String, contractAddress: String, decimals: Int, marketDataID: String, coinGeckoID: String) {
        self.name = name
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.decimals = decimals
        self.marketDataID = marketDataID
        self.coinGeckoID = coinGeckoID
    }
    init(registryEntry: ChainTokenRegistryEntry) {
        self.name = registryEntry.name
        self.symbol = registryEntry.symbol
        self.contractAddress = registryEntry.contractAddress
        self.decimals = registryEntry.decimals
        self.marketDataID = registryEntry.marketDataID
        self.coinGeckoID = registryEntry.coinGeckoID
    }
}
struct EthereumTokenTransferHistoryDiagnostics: Equatable {
    let address: String
    let rpcTransferCount: Int
    let rpcError: String?
    let blockscoutTransferCount: Int
    let blockscoutError: String?
    let etherscanTransferCount: Int
    let etherscanError: String?
    let ethplorerTransferCount: Int
    let ethplorerError: String?
    let sourceUsed: String
    let transferScanCount: Int
    let decodedTransferCount: Int
    let unsupportedTransferDropCount: Int
    let decodingCompletenessRatio: Double
    init(
        address: String, rpcTransferCount: Int, rpcError: String?, blockscoutTransferCount: Int, blockscoutError: String?, etherscanTransferCount: Int, etherscanError: String?, ethplorerTransferCount: Int, ethplorerError: String?, sourceUsed: String, transferScanCount: Int = 0, decodedTransferCount: Int = 0, unsupportedTransferDropCount: Int = 0, decodingCompletenessRatio: Double = 0
    ) {
        self.address = address
        self.rpcTransferCount = rpcTransferCount
        self.rpcError = rpcError
        self.blockscoutTransferCount = blockscoutTransferCount
        self.blockscoutError = blockscoutError
        self.etherscanTransferCount = etherscanTransferCount
        self.etherscanError = etherscanError
        self.ethplorerTransferCount = ethplorerTransferCount
        self.ethplorerError = ethplorerError
        self.sourceUsed = sourceUsed
        self.transferScanCount = transferScanCount
        self.decodedTransferCount = decodedTransferCount
        self.unsupportedTransferDropCount = unsupportedTransferDropCount
        self.decodingCompletenessRatio = decodingCompletenessRatio
    }
}

// MARK: - Tron
struct TronTokenBalanceSnapshot: Equatable {
    let symbol: String
    let contractAddress: String?
    let balance: Double
}
struct TronHistoryDiagnostics: Equatable {
    let address: String
    let tronScanTxCount: Int
    let tronScanTRC20Count: Int
    let sourceUsed: String
    let error: String?
}
enum TronBalanceService {
    static let usdtTronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    static let usddTronContract = "TXDk8mbtRbXeYuMNS83CfKPaYYT8XWv9Hz"
    static let usd1TronContract = "TPFqcBAaaUMCSVRCqPaQ9QnzKhmuoLR6Rc"
    static let bttTronContract = "TAFjULxiVgT4qWk6UZwjqwZXTSaGaqnVp4"
    struct TrackedTRC20Token: Equatable {
        let symbol: String
        let contractAddress: String
        let decimals: Int
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.tronChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.tronChainName) }
}

// MARK: - Stellar
struct StellarHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum StellarBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.stellarChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.stellarChainName) }
}

// MARK: - ICP
struct ICPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum ICPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.icpChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.icpChainName) }
}

// MARK: - XRP
struct XRPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum XRPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.xrpChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { endpointCatalog().map { base in (endpoint: base, probeURL: base) }}
}

// MARK: - Cardano
struct CardanoHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum CardanoBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.cardanoChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.cardanoChainName) }
}

// MARK: - Polkadot
struct PolkadotHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum PolkadotBalanceService {
    static func endpointCatalog() -> [String] { PolkadotProvider.endpointCatalog() }
    static func sidecarEndpointCatalog() -> [String] { PolkadotProvider.sidecarBaseURLs }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { PolkadotProvider.diagnosticsChecks() }
}

// MARK: - Monero
struct MoneroHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum MoneroBalanceService {
    typealias TrustedBackend = MoneroProvider.TrustedBackend
    static let backendBaseURLDefaultsKey = MoneroProvider.backendBaseURLDefaultsKey
    static let backendAPIKeyDefaultsKey = MoneroProvider.backendAPIKeyDefaultsKey
    static let defaultBackendID = MoneroProvider.defaultBackendID
    static let defaultPublicBackend = MoneroProvider.defaultPublicBackend
    static let trustedBackends = MoneroProvider.trustedBackends
}

// MARK: - Bitcoin Cash
enum BitcoinCashBalanceService {
    static func endpointCatalog() -> [String] { BitcoinCashProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { BitcoinCashProvider.diagnosticsChecks() }
}

// MARK: - Bitcoin SV
enum BitcoinSVBalanceService {
    static func endpointCatalog() -> [String] { BitcoinSVProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { BitcoinSVProvider.diagnosticsChecks() }
}

// MARK: - Litecoin
enum LitecoinBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.litecoinChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.litecoinChainName) }
}

// MARK: - Solana
struct SolanaHistoryDiagnostics: Equatable {
    let address: String
    let rpcCount: Int
    let sourceUsed: String
    let error: String?
}
struct SolanaSPLTokenBalanceSnapshot: Equatable {
    let mintAddress: String
    let sourceTokenAccountAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}
struct SolanaPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SolanaSPLTokenBalanceSnapshot]
}
enum SolanaBalanceService {
    static func endpointCatalog() -> [String] { SolanaProvider.balanceEndpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { SolanaProvider.diagnosticsChecks() }
    struct KnownTokenMetadata {
        let symbol: String
        let name: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }
    static let usdtMintAddress = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
    static let usdcMintAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    static let pyusdMintAddress = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
    static let usdgMintAddress = "2u1tszSeqZ3qBWF3uNGPFc8TzMk2tdiwknnRMWGWjGWH"
    static let usd1MintAddress = "USD1ttGY1N17NEEHLmELoaybftRBUSErhqYiQzvEmuB"
    static let linkMintAddress = "LinkhB3afbBKb2EQQu7s7umdZceV3wcvAUJhQAfQ23L"
    static let wlfiMintAddress = "WLFinEv6ypjkczcS83FZqFpgFZYwQXutRbxGe7oC16g"
    static let jupMintAddress = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
    static let bonkMintAddress = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    static let knownTokenMetadataByMint: [String: KnownTokenMetadata] = [
        usdtMintAddress: KnownTokenMetadata(
            symbol: "USDT", name: "Tether USD", decimals: 6, marketDataID: "825", coinGeckoID: "tether"
        ), usdcMintAddress: KnownTokenMetadata(
            symbol: "USDC", name: "USD Coin", decimals: 6, marketDataID: "3408", coinGeckoID: "usd-coin"
        ), pyusdMintAddress: KnownTokenMetadata(
            symbol: "PYUSD", name: "PayPal USD", decimals: 6, marketDataID: "27772", coinGeckoID: "paypal-usd"
        ), usdgMintAddress: KnownTokenMetadata(
            symbol: "USDG", name: "Global Dollar", decimals: 6, marketDataID: "0", coinGeckoID: "global-dollar"
        ), usd1MintAddress: KnownTokenMetadata(symbol: "USD1", name: "USD1", decimals: 6, marketDataID: "0", coinGeckoID: ""), linkMintAddress: KnownTokenMetadata(
            symbol: "LINK", name: "Chainlink", decimals: 8, marketDataID: "1975", coinGeckoID: "chainlink"
        ), wlfiMintAddress: KnownTokenMetadata(
            symbol: "WLFI", name: "World Liberty Financial", decimals: 6, marketDataID: "0", coinGeckoID: ""
        ), jupMintAddress: KnownTokenMetadata(
            symbol: "JUP", name: "Jupiter", decimals: 6, marketDataID: "29210", coinGeckoID: "jupiter-exchange-solana"
        ), bonkMintAddress: KnownTokenMetadata(symbol: "BONK", name: "Bonk", decimals: 5, marketDataID: "23095", coinGeckoID: "bonk")
    ]
    static func mintAddress(for symbol: String) -> String? {
        switch symbol.uppercased() {
        case "USDT": return usdtMintAddress
        case "USDC": return usdcMintAddress
        case "PYUSD": return pyusdMintAddress
        case "USDG": return usdgMintAddress
        case "USD1": return usd1MintAddress
        case "LINK": return linkMintAddress
        case "WLFI": return wlfiMintAddress
        case "JUP": return jupMintAddress
        case "BONK": return bonkMintAddress
        default: return nil
        }}
    static func isValidAddress(_ address: String) -> Bool { AddressValidation.isValidSolanaAddress(address) }
}

// MARK: - NEAR
struct NearHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}
struct NearHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
struct NearTokenBalanceSnapshot: Equatable {
    let contractAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}
enum NearBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.nearChainName) }
    static func rpcEndpointCatalog() -> [String] { ChainBackendRegistry.NearRuntimeEndpoints.rpcBaseURLs }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.nearChainName) }
    static func parseHistoryResponse(_ data: Data, ownerAddress: String) throws -> [NearHistorySnapshot] {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let rows = historyRows(from: jsonObject)
        return rows.compactMap { snapshot(from: $0, ownerAddress: ownerAddress) }}
    private static func historyRows(from jsonObject: Any) -> [[String: Any]] {
        if let rows = jsonObject as? [[String: Any]] { return rows }
        guard let dictionary = jsonObject as? [String: Any] else { return [] }
        if let rows = dictionary["txns"] as? [[String: Any]] { return rows }
        if let rows = dictionary["transactions"] as? [[String: Any]] { return rows }
        if let rows = dictionary["data"] as? [[String: Any]] { return rows }
        if let rows = dictionary["result"] as? [[String: Any]] { return rows }
        return []
    }
    private static func snapshot(from row: [String: Any], ownerAddress: String) -> NearHistorySnapshot? {
        guard let hash = stringValue(in: row, keys: ["transaction_hash", "hash", "receipt_id"]), !hash.isEmpty else { return nil }
        let owner = normalizedAddress(ownerAddress)
        let signer = normalizedAddress(
            stringValue(in: row, keys: ["signer_account_id", "predecessor_account_id", "signer_id", "signer"]) ?? ""
        )
        let receiver = normalizedAddress(
            stringValue(in: row, keys: ["receiver_account_id", "receiver_id", "receiver"]) ?? ""
        )
        let kind: TransactionKind
        let counterparty: String
        if signer == owner {
            kind = .send
            counterparty = receiver
        } else if receiver == owner {
            kind = .receive
            counterparty = signer
        } else if !signer.isEmpty {
            kind = .receive
            counterparty = signer
        } else {
            kind = .send
            counterparty = receiver
        }
        let depositYocto = depositText(in: row).flatMap { Decimal(string: $0) } ?? 0
        let amount = decimalToDouble(depositYocto / Decimal(string: "1000000000000000000000000")!)
        let createdAt = timestampDate(in: row) ?? Date()
        return NearHistorySnapshot(
            transactionHash: hash, kind: kind, amount: amount, counterpartyAddress: counterparty, createdAt: createdAt, status: .confirmed
        )
    }
    private static func depositText(in row: [String: Any]) -> String? {
        if let direct = stringValue(in: row, keys: ["deposit", "amount"]), !direct.isEmpty { return direct }
        if let actionsAggregate = row["actions_agg"] as? [String: Any], let aggregateDeposit = stringValue(in: actionsAggregate, keys: ["deposit", "total_deposit", "amount"]), !aggregateDeposit.isEmpty { return aggregateDeposit }
        if let actions = row["actions"] as? [[String: Any]] {
            for action in actions {
                if let deposit = stringValue(in: action, keys: ["deposit", "amount"]), !deposit.isEmpty { return deposit }
                if let args = action["args"] as? [String: Any], let nestedDeposit = stringValue(in: args, keys: ["deposit", "amount"]), !nestedDeposit.isEmpty { return nestedDeposit }}}
        return nil
    }
    private static func timestampDate(in row: [String: Any]) -> Date? {
        if let timestamp = numericTimestamp(in: row, keys: ["block_timestamp", "timestamp", "included_in_block_timestamp"]) { return normalizedDate(fromTimestamp: timestamp) }
        for nestedKey in ["block", "receipt_block", "included_in_block", "receipt"] {
            if let nested = row[nestedKey] as? [String: Any], let timestamp = numericTimestamp(in: nested, keys: ["block_timestamp", "timestamp"]) { return normalizedDate(fromTimestamp: timestamp) }}
        return nil
    }
    private static func normalizedDate(fromTimestamp timestamp: Double) -> Date? {
        guard timestamp > 0 else { return nil }
        if timestamp >= 1_000_000_000_000_000 { return Date(timeIntervalSince1970: timestamp / 1_000_000_000.0) }
        if timestamp >= 1_000_000_000_000 { return Date(timeIntervalSince1970: timestamp / 1_000.0) }
        return Date(timeIntervalSince1970: timestamp)
    }
    private static func numericTimestamp(in row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = row[key] as? NSNumber { return number.doubleValue }
            if let string = row[key] as? String, let parsed = Double(string) { return parsed }}
        return nil
    }
    private static func stringValue(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = row[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }}
            if let number = row[key] as? NSNumber { return number.stringValue }}
        return nil
    }
    private static func normalizedAddress(_ address: String) -> String { address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func decimalToDouble(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}

// MARK: - Aptos
struct AptosHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
struct AptosTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}
struct AptosPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [AptosTokenBalanceSnapshot]
}
enum AptosBalanceService {
    static let aptosCoinType = "0x1::aptos_coin::aptoscoin"
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }
    static func endpointCatalog() -> [String] { AptosProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AptosProvider.diagnosticsChecks() }
}

// MARK: - Sui
struct SuiHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
struct SuiTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}
struct SuiPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SuiTokenBalanceSnapshot]
}
enum SuiBalanceService {
    static let suiCoinType = "0x2::sui::SUI"
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.suiChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.suiChainName) }
}

// MARK: - TON
struct TONHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
struct TONJettonBalanceSnapshot: Equatable {
    let masterAddress: String
    let walletAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}
struct TONPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [TONJettonBalanceSnapshot]
}
enum TONBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }
    static func endpointCatalog() -> [String] { TONProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { TONProvider.diagnosticsChecks() }
    static func normalizeJettonMasterAddress(_ address: String) -> String { canonicalAddressIdentifier(address) }
    private static func canonicalAddressIdentifier(_ address: String?) -> String { address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}
