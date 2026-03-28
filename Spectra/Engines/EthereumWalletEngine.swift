// MARK: - File Overview
// EVM signing and transaction builder for Ethereum-compatible flows used by ETH and BNB-chain operations.
//
// Responsibilities:
// - Creates and signs EVM native/token transactions with fee/nonce controls.
// - Normalizes EVM address handling and submission data structures.

import Foundation
import BigInt
import WalletCore

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidSeedPhrase
    case missingRPCEndpoint
    case invalidRPCEndpoint
    case invalidResponse
    case invalidHexQuantity
    case unsupportedNetwork
    case rpcFailure(String)
    case integrationNotImplemented

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The Ethereum address is not valid.", comment: "")
        case .invalidSeedPhrase:
            return NSLocalizedString("The Ethereum seed phrase could not derive a valid account.", comment: "")
        case .missingRPCEndpoint:
            return NSLocalizedString("An Ethereum RPC endpoint is required for live chain access.", comment: "")
        case .invalidRPCEndpoint:
            return NSLocalizedString("The Ethereum RPC endpoint is not valid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The Ethereum RPC response was invalid.", comment: "")
        case .invalidHexQuantity:
            return NSLocalizedString("The Ethereum RPC returned an invalid balance.", comment: "")
        case .unsupportedNetwork:
            return NSLocalizedString("The configured EVM RPC endpoint does not match the selected chain.", comment: "")
        case let .rpcFailure(message):
            return NSLocalizedString(message, comment: "")
        case .integrationNotImplemented:
            return NSLocalizedString("Ethereum token integration has not been implemented yet.", comment: "")
        }
    }
}

struct EthereumCustomFeeConfiguration: Equatable {
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
}

struct EthereumAccountSnapshot: Equatable {
    let address: String
    let chainID: Int
    let nativeBalanceWei: Decimal
    let blockNumber: Int?
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

    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(
        address: String,
        rpcTransferCount: Int,
        rpcError: String?,
        blockscoutTransferCount: Int,
        blockscoutError: String?,
        etherscanTransferCount: Int,
        etherscanError: String?,
        ethplorerTransferCount: Int,
        ethplorerError: String?,
        sourceUsed: String,
        transferScanCount: Int = 0,
        decodedTransferCount: Int = 0,
        unsupportedTransferDropCount: Int = 0,
        decodingCompletenessRatio: Double = 0
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

private struct EthereumTransferDecodingStats: Equatable {
    let scannedTransfers: Int
    let decodedSupportedTransfers: Int
    let droppedUnsupportedTransfers: Int

    static let zero = EthereumTransferDecodingStats(
        scannedTransfers: 0,
        decodedSupportedTransfers: 0,
        droppedUnsupportedTransfers: 0
    )
}

struct EthereumSendPreview: Equatable {
    let nonce: Int
    let gasLimit: Int
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
    let estimatedNetworkFeeETH: Double
}

struct EthereumSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let preview: EthereumSendPreview
    let verificationStatus: SendBroadcastVerificationStatus
}

struct EthereumRPCHealthSnapshot: Equatable {
    let chainID: Int
    let latestBlockNumber: Int
}

struct EthereumSupportedToken {
    let name: String
    let symbol: String
    let contractAddress: String
    let decimals: Int
    let marketDataID: String
    let coinGeckoID: String

    init(
        name: String,
        symbol: String,
        contractAddress: String,
        decimals: Int,
        marketDataID: String,
        coinGeckoID: String
    ) {
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

enum EVMChainContext: Equatable {
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid

    var displayName: String {
        switch self {
        case .ethereum:
            return "Ethereum"
        case .ethereumClassic:
            return "Ethereum Classic"
        case .arbitrum:
            return "Arbitrum"
        case .optimism:
            return "Optimism"
        case .bnb:
            return "BNB Chain"
        case .avalanche:
            return "Avalanche"
        case .hyperliquid:
            return "Hyperliquid"
        }
    }

    var tokenTrackingChain: TokenTrackingChain? {
        switch self {
        case .ethereum:
            return .ethereum
        case .ethereumClassic:
            return nil
        case .arbitrum:
            return .arbitrum
        case .optimism:
            return .optimism
        case .bnb:
            return .bnb
        case .avalanche:
            return .avalanche
        case .hyperliquid:
            return .hyperliquid
        }
    }

    var expectedChainID: Int {
        switch self {
        case .ethereum:
            return 1
        case .ethereumClassic:
            return 61
        case .arbitrum:
            return 42161
        case .optimism:
            return 10
        case .bnb:
            return 56
        case .avalanche:
            return 43114
        case .hyperliquid:
            return 999
        }
    }

    var defaultDerivationPath: String {
        switch self {
        case .ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid:
            return "m/44'/60'/0'/0/0"
        case .ethereumClassic:
            return "m/44'/61'/0'/0/0"
        }
    }

    func derivationPath(account: UInt32) -> String {
        switch self {
        case .ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid:
            return "m/44'/60'/\(account)'/0/0"
        case .ethereumClassic:
            return "m/44'/61'/\(account)'/0/0"
        }
    }

    var defaultRPCEndpoints: [String] {
        switch self {
        case .ethereum:
            return [
                "https://ethereum-rpc.publicnode.com",
                "https://eth.llamarpc.com",
                "https://cloudflare-eth.com",
                "https://rpc.ankr.com/eth",
                "https://1rpc.io/eth"
            ]
        case .arbitrum:
            return [
                "https://arbitrum-one-rpc.publicnode.com",
                "https://arb1.arbitrum.io/rpc",
                "https://1rpc.io/arb"
            ]
        case .optimism:
            return [
                "https://mainnet.optimism.io",
                "https://optimism-rpc.publicnode.com",
                "https://1rpc.io/op"
            ]
        case .ethereumClassic:
            return [
                "https://etc.rivet.link",
                "https://geth-at.etc-network.info",
                "https://besu-at.etc-network.info"
            ]
        case .bnb:
            return [
                "https://bsc-dataseed.bnbchain.org",
                "https://bsc-dataseed1.binance.org",
                "https://bsc-dataseed1.defibit.io",
                "https://bsc-dataseed1.ninicoin.io"
            ]
        case .avalanche:
            return [
                "https://api.avax.network/ext/bc/C/rpc",
                "https://avalanche-c-chain-rpc.publicnode.com",
                "https://1rpc.io/avax/c"
            ]
        case .hyperliquid:
            return [
                "https://rpc.hyperliquid.xyz/evm"
            ]
        }
    }
}

struct EthereumTransactionReceipt: Equatable {
    let transactionHash: String
    let blockNumber: Int?
    let status: String?
    let gasUsed: Decimal?
    let effectiveGasPriceWei: Decimal?

    var isConfirmed: Bool {
        blockNumber != nil
    }

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

private struct EthereumJSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Params
}

private struct EthereumJSONRPCResponse: Decodable {
    let result: String?
    let error: EthereumJSONRPCError?
}

private struct EthereumJSONRPCDecodedResponse<Result: Decodable>: Decodable {
    let result: Result?
    let error: EthereumJSONRPCError?
}

private struct EthereumTransactionReceiptJSONRPCResponse: Decodable {
    let result: EthereumTransactionReceiptPayload?
    let error: EthereumJSONRPCError?
}

private struct EthereumTransactionReceiptPayload: Decodable {
    let transactionHash: String
    let blockNumber: String?
    let status: String?
    let gasUsed: String?
    let effectiveGasPrice: String?
}

private struct EthereumTransactionPayload: Decodable {
    let nonce: String?
}

private struct EthereumTransactionByHashPayload: Decodable {
    let hash: String?
    let blockNumber: String?
    let from: String
    let to: String?
    let value: String
}

private struct EthereumBlockPayload: Decodable {
    let timestamp: String
}

private struct EthereumTransactionReceiptWithLogsPayload: Decodable {
    let transactionHash: String
    let blockNumber: String?
    let status: String?
    let logs: [EthereumLogPayload]
}

private struct EthereumLogPayload: Decodable {
    let address: String
    let topics: [String]
    let data: String
    let logIndex: String?
}

private struct HyperliquidExplorerResolvedTransaction {
    let transactionHash: String
    let blockNumber: Int
    let fromAddress: String
    let toAddress: String
    let value: Decimal
    let timestamp: Date?
    let logs: [EthereumLogPayload]
}

private struct EthereumJSONRPCError: Decodable {
    let code: Int
    let message: String
}

private struct ENSIdeasResolveResponse: Decodable {
    let address: String?
}

private struct EthereumCallRequest: Encodable {
    let to: String
    let data: String
}

private struct EthereumEstimateGasRequest: Encodable {
    let from: String
    let to: String
    let value: String
    let data: String?
}

private struct EthereumBlockByNumberParameters: Encodable {
    let blockNumber: String
    let includeTransactions: Bool

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(blockNumber)
        try container.encode(includeTransactions)
    }
}

private struct EtherscanTokenTransferResponse: Decodable {
    let status: String?
    let message: String?
    let result: [EtherscanTokenTransferItem]
    let resultText: String?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case result
    }

    /// Initializes and configures this component for use in the wallet app.
    /// Ensures deterministic setup so runtime state remains consistent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let items = try? container.decode([EtherscanTokenTransferItem].self, forKey: .result) {
            result = items
            resultText = nil
        } else if let text = try? container.decode(String.self, forKey: .result) {
            result = []
            resultText = text
        } else {
            result = []
            resultText = nil
        }
    }
}

private struct EtherscanTokenTransferItem: Decodable {
    let blockNumber: String
    let timeStamp: String
    let hash: String
    let from: String
    let to: String
    let contractAddress: String
    let tokenName: String
    let tokenSymbol: String
    let tokenDecimal: String
    let value: String
}

private struct EtherscanNormalTransactionResponse: Decodable {
    let status: String?
    let message: String?
    let result: [EtherscanNormalTransactionItem]
    let resultText: String?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let items = try? container.decode([EtherscanNormalTransactionItem].self, forKey: .result) {
            result = items
            resultText = nil
        } else if let text = try? container.decode(String.self, forKey: .result) {
            result = []
            resultText = text
        } else {
            result = []
            resultText = nil
        }
    }
}

private struct EtherscanNormalTransactionItem: Decodable {
    let blockNumber: String
    let timeStamp: String
    let hash: String
    let from: String
    let to: String
    let value: String
    let isError: String?
    let txreceipt_status: String?
}

private struct BlockscoutTokenTransfersResponse: Decodable {
    let items: [BlockscoutTokenTransferItem]
}

private struct BlockscoutNormalTransactionsResponse: Decodable {
    let items: [BlockscoutNormalTransactionItem]
}

private struct BlockscoutNormalTransactionItem: Decodable {
    let hash: String?
    let timestamp: String?
    let from: BlockscoutAddress?
    let to: BlockscoutAddress?
    let value: String?
    let result: String?
    let block: BlockscoutBlock?
}

private struct BlockscoutTokenTransferItem: Decodable {
    let transaction_hash: String?
    let block_number: Int?
    let timestamp: String?
    let from: BlockscoutAddress?
    let to: BlockscoutAddress?
    let token: BlockscoutToken?
    let total: BlockscoutAmount?
}

private struct BlockscoutAddress: Decodable {
    let hash: String?
}

private struct BlockscoutBlock: Decodable {
    let height: Int?
}

private struct BlockscoutToken: Decodable {
    let address: String?
    let symbol: String?
    let name: String?
    let decimals: String?
}

private struct BlockscoutAmount: Decodable {
    let value: String?
}

private struct EthplorerErrorResponse: Decodable {
    let error: EthplorerErrorBody?
}

private struct EthplorerErrorBody: Decodable {
    let code: Int?
    let message: String?
}

private struct EthplorerAddressHistoryResponse: Decodable {
    let operations: [EthplorerOperation]?
}

private struct EthplorerOperation: Decodable {
    let timestamp: TimeInterval?
    let transactionHash: String?
    let from: String?
    let to: String?
    let value: String?
    let blockNumber: Int?
    let tokenInfo: EthplorerTokenInfo?
}

private struct EthplorerTokenInfo: Decodable {
    let address: String?
    let symbol: String?
    let name: String?
    let decimals: String?
}

private struct EthereumSendParameters {
    let nonce: Int
    let gasLimit: Int
    let maxFeePerGasWei: Decimal
    let maxPriorityFeePerGasWei: Decimal
}

private struct EthereumFeeHistoryParameters: Encodable {
    let blockCountHex: String
    let blockTag: String
    let rewardPercentiles: [Int]

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(blockCountHex)
        try container.encode(blockTag)
        try container.encode(rewardPercentiles)
    }
}

private struct EthereumFeeHistoryResult: Decodable {
    let baseFeePerGas: [String]
    let reward: [[String]]?
}

private struct EthereumCallParameters: Encodable {
    let call: EthereumCallRequest
    let blockTag: String

    /// Ethereum/EVM engine operation: Encode.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(call)
        try container.encode(blockTag)
    }
}

private struct EthereumSimulationRequest: Encodable {
    let from: String
    let to: String
    let value: String
    let data: String?
}

private struct EthereumSimulationParameters: Encodable {
    let call: EthereumSimulationRequest
    let blockTag: String

    /// Ethereum/EVM engine operation: Encode.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(call)
        try container.encode(blockTag)
    }
}

enum EthereumWalletEngine {
    private static let iso8601Formatter = ISO8601DateFormatter()

    static let supportedTokens: [EthereumSupportedToken] = supportedTokens(for: .ethereum)

    /// Ethereum/EVM engine operation: Supported tokens.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func supportedTokens(for chain: EVMChainContext) -> [EthereumSupportedToken] {
        guard let trackingChain = chain.tokenTrackingChain else { return [] }
        return ChainTokenRegistryEntry.builtIn
            .filter { $0.chain == trackingChain }
            .map { entry in
                EthereumSupportedToken(
                    name: entry.name,
                    symbol: entry.symbol,
                    contractAddress: entry.contractAddress,
                    decimals: entry.decimals,
                    marketDataID: entry.marketDataID,
                    coinGeckoID: entry.coinGeckoID
                )
            }
    }

    /// Ethereum/EVM engine operation: Resolved rpcendpoints.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func resolvedRPCEndpoints(preferred: URL?, chain: EVMChainContext) -> [URL] {
        if let preferred {
            return [preferred]
        }
        var endpoints: [URL] = []
        for endpointString in chain.defaultRPCEndpoints {
            guard let endpointURL = URL(string: endpointString) else { continue }
            if !endpoints.contains(endpointURL) {
                endpoints.append(endpointURL)
            }
        }
        return endpoints
    }

    /// Ethereum/EVM engine operation: Resolved rpcendpoints.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func resolvedRPCEndpoints(fallbackFrom rpcEndpoint: URL, chain: EVMChainContext) -> [URL] {
        let defaultEndpoints = resolvedRPCEndpoints(preferred: nil, chain: chain)
        guard defaultEndpoints.contains(rpcEndpoint) else {
            return [rpcEndpoint]
        }
        return [rpcEndpoint] + defaultEndpoints.filter { $0 != rpcEndpoint }
    }

    /// Ethereum/EVM engine operation: Inferred chain context.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func inferredChainContext(for rpcEndpoint: URL) -> EVMChainContext {
        let allContexts: [EVMChainContext] = [.ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid]
        for context in allContexts {
            let defaults = resolvedRPCEndpoints(preferred: nil, chain: context)
            if defaults.contains(rpcEndpoint) {
                return context
            }
        }
        return .ethereum
    }

    /// Ethereum/EVM engine operation: Normalize address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Ethereum/EVM engine operation: Make history diagnostics.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func makeHistoryDiagnostics(
        address: String,
        rpcTransferCount: Int,
        rpcError: String?,
        blockscoutTransferCount: Int,
        blockscoutError: String?,
        etherscanTransferCount: Int,
        etherscanError: String?,
        ethplorerTransferCount: Int,
        ethplorerError: String?,
        sourceUsed: String,
        stats: EthereumTransferDecodingStats
    ) -> EthereumTokenTransferHistoryDiagnostics {
        let denominator = max(1, stats.scannedTransfers)
        let ratio = Double(stats.decodedSupportedTransfers) / Double(denominator)
        return EthereumTokenTransferHistoryDiagnostics(
            address: address,
            rpcTransferCount: rpcTransferCount,
            rpcError: rpcError,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutError,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanError,
            ethplorerTransferCount: ethplorerTransferCount,
            ethplorerError: ethplorerError,
            sourceUsed: sourceUsed,
            transferScanCount: stats.scannedTransfers,
            decodedTransferCount: stats.decodedSupportedTransfers,
            unsupportedTransferDropCount: stats.droppedUnsupportedTransfers,
            decodingCompletenessRatio: ratio
        )
    }

    /// Ethereum/EVM engine operation: Is valid address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func isValidAddress(_ address: String) -> Bool {
        let normalizedAddress = normalizeAddress(address)
        guard normalizedAddress.count == 42, normalizedAddress.hasPrefix("0x") else {
            return false
        }

        let hexBody = normalizedAddress.dropFirst(2)
        return hexBody.allSatisfy(\.isHexDigit)
    }

    /// Ethereum/EVM engine operation: Validate address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func validateAddress(_ address: String) throws -> String {
        let normalizedAddress = normalizeAddress(address)
        guard isValidAddress(normalizedAddress) else {
            throw EthereumWalletEngineError.invalidAddress
        }
        return normalizedAddress
    }

    /// Ethereum/EVM engine operation: Receive address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func receiveAddress(for address: String) throws -> String {
        try validateAddress(address)
    }

    /// Ethereum/EVM engine operation: Resolve ensaddress.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func resolveENSAddress(_ name: String, chain: EVMChainContext = .ethereum) async throws -> String? {
        guard chain == .ethereum else { return nil }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedName.hasSuffix(".eth"),
              !normalizedName.isEmpty,
              !normalizedName.contains(" ") else {
            return nil
        }
        guard let encodedName = normalizedName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let endpoint = URL(string: "https://api.ensideas.com/ens/resolve/\(encodedName)") else {
            throw EthereumWalletEngineError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw EthereumWalletEngineError.rpcFailure("Unable to resolve ENS name right now.")
        }

        let payload = try JSONDecoder().decode(ENSIdeasResolveResponse.self, from: data)
        guard let address = payload.address, isValidAddress(address) else {
            return nil
        }
        return try validateAddress(address)
    }

    /// Ethereum/EVM engine operation: Fetch code.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchCode(
        at address: String,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> String {
        let normalizedAddress = try validateAddress(address)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        return try await performRPC(
            method: "eth_getCode",
            params: [normalizedAddress, "latest"],
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 35
        )
    }

    /// Ethereum/EVM engine operation: Has contract code.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func hasContractCode(_ code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized != "0x" && normalized != "0x0"
    }

    /// Ethereum/EVM engine operation: Derived address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func derivedAddress(
        for seedPhrase: String,
        account: UInt32 = 0,
        chain: EVMChainContext = .ethereum,
        derivationPath: String? = nil
    ) throws -> String {
        let normalizedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let wordCount = BitcoinWalletEngine.normalizedMnemonicWords(from: normalizedSeedPhrase).count
        guard wordCount > 0,
              BitcoinWalletEngine.validateMnemonic(normalizedSeedPhrase, expectedWordCount: wordCount) == nil else {
            throw EthereumWalletEngineError.invalidSeedPhrase
        }

        return try walletCoreDerivedAddress(
            seedPhrase: normalizedSeedPhrase,
            account: account,
            chain: chain,
            derivationPath: derivationPath
        )
    }

    static func derivedAddress(
        forPrivateKey privateKeyHex: String,
        chain: EVMChainContext = .ethereum
    ) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .ethereum)
        return normalizeAddress(material.address)
    }

    /// Ethereum/EVM engine operation: Fetch account snapshot.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchAccountSnapshot(
        for address: String,
        rpcEndpoint: URL? = nil,
        chainID: Int = 1,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumAccountSnapshot {
        let normalizedAddress = try validateAddress(address)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!

        async let balanceHex = performRPC(
            method: "eth_getBalance",
            params: [normalizedAddress, "latest"],
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 1
        )
        async let blockHex = performRPC(
            method: "eth_blockNumber",
            params: [String](),
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 2
        )

        let nativeBalanceWei = try decimal(fromHexQuantity: try await balanceHex)
        let blockNumberHex = try await blockHex
        let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16)

        return EthereumAccountSnapshot(
            address: normalizedAddress,
            chainID: chainID,
            nativeBalanceWei: nativeBalanceWei,
            blockNumber: blockNumber
        )
    }

    /// Ethereum/EVM engine operation: Native balance eth.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func nativeBalanceETH(from snapshot: EthereumAccountSnapshot) -> Double {
        let divisor = Decimal(string: "1000000000000000000") ?? 1
        let ethBalance = snapshot.nativeBalanceWei / divisor
        return NSDecimalNumber(decimal: ethBalance).doubleValue
    }

    /// Ethereum/EVM engine operation: Planned account snapshot.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func plannedAccountSnapshot(
        for address: String,
        rpcEndpoint: URL?,
        chainID: Int = 1,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumAccountSnapshot {
        guard let rpcEndpoint else {
            throw EthereumWalletEngineError.missingRPCEndpoint
        }

        return try await fetchAccountSnapshot(
            for: address,
            rpcEndpoint: rpcEndpoint,
            chainID: chainID,
            chain: chain
        )
    }

    /// Ethereum/EVM engine operation: Planned token balances.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func plannedTokenBalances(
        for address: String,
        tokenContracts: [String],
        rpcEndpoint: URL?,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumTokenBalanceSnapshot] {
        let chainTokens = supportedTokens(for: chain)
        let requestedContracts = Set(tokenContracts.map(normalizeAddress))
        let matchingTokens = chainTokens.filter { requestedContracts.contains($0.contractAddress) }
        guard !matchingTokens.isEmpty else { return [] }

        return try await fetchTokenBalances(
            for: address,
            tokens: matchingTokens,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
    }

    /// Ethereum/EVM engine operation: Fetch supported token balances.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchSupportedTokenBalances(
        for address: String,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumTokenBalanceSnapshot] {
        try await fetchTokenBalances(
            for: address,
            tokens: supportedTokens(for: chain),
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
    }

    /// Ethereum/EVM engine operation: Fetch token balances.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchTokenBalances(
        for address: String,
        trackedTokens: [EthereumSupportedToken],
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumTokenBalanceSnapshot] {
        guard !trackedTokens.isEmpty else { return [] }
        return try await fetchTokenBalances(
            for: address,
            tokens: trackedTokens,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
    }

    /// Ethereum/EVM engine operation: Fetch supported token transfer history.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchSupportedTokenTransferHistory(
        for address: String,
        rpcEndpoint: URL? = nil,
        etherscanAPIKey: String? = nil,
        maxResults: Int = 200,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumTokenTransferSnapshot] {
        let result = try await fetchSupportedTokenTransferHistoryWithDiagnostics(
            for: address,
            rpcEndpoint: rpcEndpoint,
            etherscanAPIKey: etherscanAPIKey,
            maxResults: maxResults,
            chain: chain
        )
        return result.snapshots
    }

    /// Ethereum/EVM engine operation: Fetch supported token transfer history page with diagnostics.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchSupportedTokenTransferHistoryPageWithDiagnostics(
        for address: String,
        rpcEndpoint: URL? = nil,
        etherscanAPIKey: String? = nil,
        page: Int = 1,
        pageSize: Int = 200,
        trackedTokens: [EthereumSupportedToken]? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> (snapshots: [EthereumTokenTransferSnapshot], diagnostics: EthereumTokenTransferHistoryDiagnostics) {
        let normalizedAddress = try validateAddress(address)
        let safePage = max(1, page)
        let safePageSize = max(1, min(pageSize, 500))
        let chainTokens = trackedTokens ?? supportedTokens(for: chain)
        if chain == .hyperliquid {
            let result = try await fetchTokenTransferHistoryFromHyperliquidExplorerAddressPage(
                normalizedAddress: normalizedAddress,
                chainTokens: chainTokens,
                maxResults: safePageSize,
                page: safePage,
                pageSize: safePageSize,
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: 0,
                blockscoutError: "Blockscout provider is not configured for \(chain.displayName).",
                etherscanTransferCount: result.snapshots.count,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: "Ethplorer provider is not configured for \(chain.displayName).",
                sourceUsed: "hyperliquid-explorer",
                stats: result.stats
            )
            return (result.snapshots, diagnostics)
        }
        let supportedTokensByContract = Dictionary(
            uniqueKeysWithValues: chainTokens.map { (normalizeAddress($0.contractAddress), $0) }
        )
        let supportedTokensBySymbol = Dictionary(
            uniqueKeysWithValues: chainTokens.map { ($0.symbol.uppercased(), $0) }
        )
        var blockscoutTransferCount = 0
        var blockscoutErrorMessage: String?
        var etherscanTransferCount = 0
        var etherscanErrorMessage: String?
        var ethplorerTransferCount = 0
        var ethplorerErrorMessage: String?
        var blockscoutStats = EthereumTransferDecodingStats.zero
        var etherscanStats = EthereumTransferDecodingStats.zero
        var ethplorerStats = EthereumTransferDecodingStats.zero

        let blockscoutPage: [EthereumTokenTransferSnapshot]
        if chain == .ethereum {
            do {
                let result = try await fetchTokenTransferHistoryFromBlockscout(
                    normalizedAddress: normalizedAddress,
                    supportedTokensByContract: supportedTokensByContract,
                    supportedTokensBySymbol: supportedTokensBySymbol,
                    maxResults: safePageSize,
                    page: safePage,
                    pageSize: safePageSize,
                    chain: chain
                )
                blockscoutPage = result.snapshots
                blockscoutStats = result.stats
            } catch {
                blockscoutErrorMessage = error.localizedDescription
                blockscoutPage = []
            }
        } else {
            blockscoutErrorMessage = "Blockscout provider is not configured for \(chain.displayName)."
            blockscoutPage = []
        }
        blockscoutTransferCount = blockscoutPage.count
        if !blockscoutPage.isEmpty {
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: blockscoutTransferCount,
                blockscoutError: blockscoutErrorMessage,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "blockscout",
                stats: blockscoutStats
            )
            return (blockscoutPage, diagnostics)
        }

        let etherscanPage: [EthereumTokenTransferSnapshot]
        do {
                let result = try await fetchTokenTransferHistoryFromEtherscan(
                    normalizedAddress: normalizedAddress,
                    chainTokens: chainTokens,
                    supportedTokensByContract: supportedTokensByContract,
                    supportedTokensBySymbol: supportedTokensBySymbol,
                    apiKey: etherscanAPIKey,
                maxResults: safePageSize,
                page: safePage,
                pageSize: safePageSize,
                chain: chain
            )
            etherscanPage = result.snapshots
            etherscanStats = result.stats
        } catch {
            etherscanErrorMessage = error.localizedDescription
            etherscanPage = []
        }
        etherscanTransferCount = etherscanPage.count
        if !etherscanPage.isEmpty {
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: blockscoutTransferCount,
                blockscoutError: blockscoutErrorMessage,
                etherscanTransferCount: etherscanTransferCount,
                etherscanError: etherscanErrorMessage,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "etherscan",
                stats: EthereumTransferDecodingStats(
                    scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers,
                    decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers,
                    droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers
                )
            )
            return (etherscanPage, diagnostics)
        }

        let ethplorerPage: [EthereumTokenTransferSnapshot]
        if chain == .ethereum {
            do {
                let result = try await fetchTokenTransferHistoryFromEthplorer(
                    normalizedAddress: normalizedAddress,
                    supportedTokensByContract: supportedTokensByContract,
                    supportedTokensBySymbol: supportedTokensBySymbol,
                    maxResults: safePageSize,
                    page: safePage,
                    pageSize: safePageSize,
                    chain: chain
                )
                ethplorerPage = result.snapshots
                ethplorerStats = result.stats
            } catch {
                ethplorerErrorMessage = error.localizedDescription
                ethplorerPage = []
            }
        } else {
            ethplorerErrorMessage = "Ethplorer provider is not configured for \(chain.displayName)."
            ethplorerPage = []
        }
        ethplorerTransferCount = ethplorerPage.count
        if !ethplorerPage.isEmpty {
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: blockscoutTransferCount,
                blockscoutError: blockscoutErrorMessage,
                etherscanTransferCount: etherscanTransferCount,
                etherscanError: etherscanErrorMessage,
                ethplorerTransferCount: ethplorerTransferCount,
                ethplorerError: ethplorerErrorMessage,
                sourceUsed: "ethplorer",
                stats: EthereumTransferDecodingStats(
                    scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
                    decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
                    droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
                )
            )
            return (ethplorerPage, diagnostics)
        }

        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: "RPC fallback skipped to avoid long timeout on constrained networks.",
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanErrorMessage,
            ethplorerTransferCount: ethplorerTransferCount,
            ethplorerError: ethplorerErrorMessage,
            sourceUsed: "none",
            stats: EthereumTransferDecodingStats(
                scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
                decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
                droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
            )
        )
        return ([], diagnostics)
    }

    /// Ethereum/EVM engine operation: Fetch supported token transfer history with diagnostics.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchSupportedTokenTransferHistoryWithDiagnostics(
        for address: String,
        rpcEndpoint: URL? = nil,
        etherscanAPIKey: String? = nil,
        maxResults: Int = 200,
        trackedTokens: [EthereumSupportedToken]? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> (snapshots: [EthereumTokenTransferSnapshot], diagnostics: EthereumTokenTransferHistoryDiagnostics) {
        let normalizedAddress = try validateAddress(address)

        let chainTokens = trackedTokens ?? supportedTokens(for: chain)
        if chain == .hyperliquid {
            let result = try await fetchTokenTransferHistoryFromHyperliquidExplorerAddressPage(
                normalizedAddress: normalizedAddress,
                chainTokens: chainTokens,
                maxResults: maxResults,
                page: 1,
                pageSize: maxResults,
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: 0,
                blockscoutError: "Blockscout provider is not configured for \(chain.displayName).",
                etherscanTransferCount: result.snapshots.count,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: "Ethplorer provider is not configured for \(chain.displayName).",
                sourceUsed: "hyperliquid-explorer",
                stats: result.stats
            )
            return (Array(result.snapshots.prefix(maxResults)), diagnostics)
        }
        let supportedTokensByContract = Dictionary(
            uniqueKeysWithValues: chainTokens.map { (normalizeAddress($0.contractAddress), $0) }
        )
        let supportedTokensBySymbol = Dictionary(
            uniqueKeysWithValues: chainTokens.map { ($0.symbol.uppercased(), $0) }
        )
        var blockscoutTransferCount = 0
        var blockscoutErrorMessage: String?
        var etherscanTransferCount = 0
        var etherscanErrorMessage: String?
        var ethplorerTransferCount = 0
        var ethplorerErrorMessage: String?
        var blockscoutStats = EthereumTransferDecodingStats.zero
        var etherscanStats = EthereumTransferDecodingStats.zero
        var ethplorerStats = EthereumTransferDecodingStats.zero

        let blockscoutFallback: [EthereumTokenTransferSnapshot]
        if chain == .ethereum {
            do {
                let result = try await fetchTokenTransferHistoryFromBlockscout(
                    normalizedAddress: normalizedAddress,
                    supportedTokensByContract: supportedTokensByContract,
                    supportedTokensBySymbol: supportedTokensBySymbol,
                    maxResults: maxResults,
                    chain: chain
                )
                blockscoutFallback = result.snapshots
                blockscoutStats = result.stats
            } catch {
                blockscoutErrorMessage = error.localizedDescription
                blockscoutFallback = []
            }
        } else {
            blockscoutErrorMessage = "Blockscout provider is not configured for \(chain.displayName)."
            blockscoutFallback = []
        }
        blockscoutTransferCount = blockscoutFallback.count
        if !blockscoutFallback.isEmpty {
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: blockscoutTransferCount,
                blockscoutError: blockscoutErrorMessage,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "blockscout",
                stats: blockscoutStats
            )
            return (Array(blockscoutFallback.prefix(maxResults)), diagnostics)
        }

        // Fast path for diagnostics and UI responsiveness.
        let etherscanFallback: [EthereumTokenTransferSnapshot]
        do {
            let result = try await fetchTokenTransferHistoryFromEtherscan(
                normalizedAddress: normalizedAddress,
                chainTokens: chainTokens,
                supportedTokensByContract: supportedTokensByContract,
                supportedTokensBySymbol: supportedTokensBySymbol,
                apiKey: etherscanAPIKey,
                maxResults: maxResults,
                chain: chain
            )
            etherscanFallback = result.snapshots
            etherscanStats = result.stats
        } catch {
            etherscanErrorMessage = error.localizedDescription
            etherscanFallback = []
        }
        etherscanTransferCount = etherscanFallback.count
        if !etherscanFallback.isEmpty {
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: blockscoutTransferCount,
                blockscoutError: blockscoutErrorMessage,
                etherscanTransferCount: etherscanTransferCount,
                etherscanError: etherscanErrorMessage,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "etherscan",
                stats: EthereumTransferDecodingStats(
                    scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers,
                    decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers,
                    droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers
                )
            )
            return (Array(etherscanFallback.prefix(maxResults)), diagnostics)
        }

        let ethplorerFallback: [EthereumTokenTransferSnapshot]
        if chain == .ethereum {
            do {
                let result = try await fetchTokenTransferHistoryFromEthplorer(
                    normalizedAddress: normalizedAddress,
                    supportedTokensByContract: supportedTokensByContract,
                    supportedTokensBySymbol: supportedTokensBySymbol,
                    maxResults: maxResults,
                    chain: chain
                )
                ethplorerFallback = result.snapshots
                ethplorerStats = result.stats
            } catch {
                ethplorerErrorMessage = error.localizedDescription
                ethplorerFallback = []
            }
        } else {
            ethplorerErrorMessage = "Ethplorer provider is not configured for \(chain.displayName)."
            ethplorerFallback = []
        }
        ethplorerTransferCount = ethplorerFallback.count
        if !ethplorerFallback.isEmpty {
            let diagnostics = makeHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0,
                rpcError: nil,
                blockscoutTransferCount: blockscoutTransferCount,
                blockscoutError: blockscoutErrorMessage,
                etherscanTransferCount: etherscanTransferCount,
                etherscanError: etherscanErrorMessage,
                ethplorerTransferCount: ethplorerTransferCount,
                ethplorerError: ethplorerErrorMessage,
                sourceUsed: "ethplorer",
                stats: EthereumTransferDecodingStats(
                    scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
                    decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
                    droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
                )
            )
            return (Array(ethplorerFallback.prefix(maxResults)), diagnostics)
        }

        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: "RPC fallback skipped to avoid long timeout on constrained networks.",
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanErrorMessage,
            ethplorerTransferCount: ethplorerTransferCount,
            ethplorerError: ethplorerErrorMessage,
            sourceUsed: "none",
            stats: EthereumTransferDecodingStats(
                scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
                decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
                droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
            )
        )
        return ([], diagnostics)
    }

    /// Ethereum/EVM engine operation: Fetch token balances.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchTokenBalances(
        for address: String,
        tokens: [EthereumSupportedToken],
        rpcEndpoint: URL?,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumTokenBalanceSnapshot] {
        let normalizedAddress = try validateAddress(address)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!

        var balances: [EthereumTokenBalanceSnapshot] = []
        for (index, token) in tokens.enumerated() {
            let balanceHex = try await performRPC(
                method: "eth_call",
                params: EthereumCallParameters(
                    call: EthereumCallRequest(
                        to: token.contractAddress,
                        data: balanceOfCallData(for: normalizedAddress)
                    ),
                    blockTag: "latest"
                ),
                rpcEndpoint: resolvedRPCEndpoint,
                requestID: 100 + index
            )
            let rawBalance = try decimal(fromHexQuantity: balanceHex)
            let normalizedBalance = rawBalance / decimalPowerOfTen(token.decimals)
            balances.append(
                EthereumTokenBalanceSnapshot(
                    contractAddress: token.contractAddress,
                    symbol: token.symbol,
                    balance: normalizedBalance,
                    decimals: token.decimals
                )
            )
        }

        return balances
    }

    /// Ethereum/EVM engine operation: Fetch send preview.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchSendPreview(
        from fromAddress: String,
        to toAddress: String,
        amountETH: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendPreview {
        let parameters = try await fetchSendParameters(
            from: fromAddress,
            to: toAddress,
            valueWei: weiDecimal(fromETH: amountETH),
            data: nil,
            explicitNonce: explicitNonce,
            customFees: customFees,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
        let estimatedNetworkFeeWei = Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei
        return EthereumSendPreview(
            nonce: parameters.nonce,
            gasLimit: parameters.gasLimit,
            maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
            maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
            estimatedNetworkFeeETH: eth(fromWei: estimatedNetworkFeeWei)
        )
    }

    /// Ethereum/EVM engine operation: Send.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func send(
        seedPhrase: String,
        to toAddress: String,
        amountETH: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum,
        derivationAccount: UInt32 = 0
    ) async throws -> EthereumSendResult {
        let normalizedFromAddress = try derivedAddress(for: seedPhrase, account: derivationAccount, chain: chain)
        let normalizedToAddress = try validateAddress(toAddress)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
        guard chainID == chain.expectedChainID else {
            throw EthereumWalletEngineError.unsupportedNetwork
        }

        let parameters = try await fetchSendParameters(
            from: normalizedFromAddress,
            to: normalizedToAddress,
            valueWei: weiDecimal(fromETH: amountETH),
            data: nil,
            explicitNonce: explicitNonce,
            customFees: customFees,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let preview = EthereumSendPreview(
            nonce: parameters.nonce,
            gasLimit: parameters.gasLimit,
            maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
            maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
            estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei)
        )

        let rawTransaction = try signTransaction(
            seedPhrase: seedPhrase,
            toAddress: normalizedToAddress,
            valueWei: weiDecimal(fromETH: amountETH),
            parameters: parameters,
            chainID: chainID,
            derivationAccount: derivationAccount,
            chain: chain
        )

        let transactionHash = try await broadcastRawTransaction(
            rawTransaction,
            preferredRPCEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            transactionHash: transactionHash,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        return EthereumSendResult(
            fromAddress: normalizedFromAddress,
            transactionHash: transactionHash,
            preview: preview,
            verificationStatus: verificationStatus
        )
    }

    static func send(
        privateKeyHex: String,
        to toAddress: String,
        amountETH: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendResult {
        let normalizedFromAddress = try derivedAddress(forPrivateKey: privateKeyHex, chain: chain)
        let normalizedToAddress = try validateAddress(toAddress)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
        guard chainID == chain.expectedChainID else {
            throw EthereumWalletEngineError.unsupportedNetwork
        }

        let parameters = try await fetchSendParameters(
            from: normalizedFromAddress,
            to: normalizedToAddress,
            valueWei: weiDecimal(fromETH: amountETH),
            data: nil,
            explicitNonce: explicitNonce,
            customFees: customFees,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let preview = EthereumSendPreview(
            nonce: parameters.nonce,
            gasLimit: parameters.gasLimit,
            maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
            maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
            estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei)
        )

        let rawTransaction = try signTransaction(
            privateKeyHex: privateKeyHex,
            toAddress: normalizedToAddress,
            valueWei: weiDecimal(fromETH: amountETH),
            parameters: parameters,
            chainID: chainID,
            chain: chain
        )

        let transactionHash = try await broadcastRawTransaction(
            rawTransaction,
            preferredRPCEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            transactionHash: transactionHash,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        return EthereumSendResult(
            fromAddress: normalizedFromAddress,
            transactionHash: transactionHash,
            preview: preview,
            verificationStatus: verificationStatus
        )
    }

    /// Ethereum/EVM engine operation: Fetch token send preview.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchTokenSendPreview(
        from fromAddress: String,
        to toAddress: String,
        token: EthereumSupportedToken,
        amount: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendPreview {
        let callData = try transferCallData(
            to: toAddress,
            amount: amount,
            decimals: token.decimals
        )
        let parameters = try await fetchSendParameters(
            from: fromAddress,
            to: token.contractAddress,
            valueWei: 0,
            data: callData,
            explicitNonce: explicitNonce,
            customFees: customFees,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
        let estimatedNetworkFeeWei = Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei
        return EthereumSendPreview(
            nonce: parameters.nonce,
            gasLimit: parameters.gasLimit,
            maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
            maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
            estimatedNetworkFeeETH: eth(fromWei: estimatedNetworkFeeWei)
        )
    }

    /// Ethereum/EVM engine operation: Send token.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func sendToken(
        seedPhrase: String,
        to toAddress: String,
        token: EthereumSupportedToken,
        amount: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum,
        derivationAccount: UInt32 = 0
    ) async throws -> EthereumSendResult {
        let normalizedFromAddress = try derivedAddress(for: seedPhrase, account: derivationAccount, chain: chain)
        let normalizedRecipientAddress = try validateAddress(toAddress)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
        guard chainID == chain.expectedChainID else {
            throw EthereumWalletEngineError.unsupportedNetwork
        }

        let callData = try transferCallData(
            to: normalizedRecipientAddress,
            amount: amount,
            decimals: token.decimals
        )
        let parameters = try await fetchSendParameters(
            from: normalizedFromAddress,
            to: token.contractAddress,
            valueWei: 0,
            data: callData,
            explicitNonce: explicitNonce,
            customFees: customFees,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let preview = EthereumSendPreview(
            nonce: parameters.nonce,
            gasLimit: parameters.gasLimit,
            maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
            maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
            estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei)
        )

        let amountUnits = scaledUnitDecimal(fromAmount: amount, decimals: token.decimals)
        let rawTransaction = try signERC20Transaction(
            seedPhrase: seedPhrase,
            tokenContract: token.contractAddress,
            recipientAddress: normalizedRecipientAddress,
            amountUnits: amountUnits,
            parameters: parameters,
            chainID: chainID,
            derivationAccount: derivationAccount,
            chain: chain
        )

        let transactionHash = try await broadcastRawTransaction(
            rawTransaction,
            preferredRPCEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            transactionHash: transactionHash,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        return EthereumSendResult(
            fromAddress: normalizedFromAddress,
            transactionHash: transactionHash,
            preview: preview,
            verificationStatus: verificationStatus
        )
    }

    static func sendToken(
        privateKeyHex: String,
        to toAddress: String,
        token: EthereumSupportedToken,
        amount: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendResult {
        let normalizedFromAddress = try derivedAddress(forPrivateKey: privateKeyHex, chain: chain)
        let normalizedRecipientAddress = try validateAddress(toAddress)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
        guard chainID == chain.expectedChainID else {
            throw EthereumWalletEngineError.unsupportedNetwork
        }

        let callData = try transferCallData(
            to: normalizedRecipientAddress,
            amount: amount,
            decimals: token.decimals
        )
        let parameters = try await fetchSendParameters(
            from: normalizedFromAddress,
            to: token.contractAddress,
            valueWei: 0,
            data: callData,
            explicitNonce: explicitNonce,
            customFees: customFees,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let preview = EthereumSendPreview(
            nonce: parameters.nonce,
            gasLimit: parameters.gasLimit,
            maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
            maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
            estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei)
        )

        let amountUnits = scaledUnitDecimal(fromAmount: amount, decimals: token.decimals)
        let rawTransaction = try signERC20Transaction(
            privateKeyHex: privateKeyHex,
            tokenContract: token.contractAddress,
            recipientAddress: normalizedRecipientAddress,
            amountUnits: amountUnits,
            parameters: parameters,
            chainID: chainID,
            chain: chain
        )

        let transactionHash = try await broadcastRawTransaction(
            rawTransaction,
            preferredRPCEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            transactionHash: transactionHash,
            rpcEndpoint: resolvedRPCEndpoint,
            chain: chain
        )
        return EthereumSendResult(
            fromAddress: normalizedFromAddress,
            transactionHash: transactionHash,
            preview: preview,
            verificationStatus: verificationStatus
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        transactionHash: String,
        rpcEndpoint: URL,
        chain: EVMChainContext
    ) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if let receipt = try await fetchTransactionReceipt(
                    transactionHash: transactionHash,
                    rpcEndpoint: rpcEndpoint,
                    chain: chain
                ) {
                    if receipt.status == "0x0" {
                        return .failed("Transaction was mined with failed execution status.")
                    }
                    return .verified
                }
            } catch {
                lastError = error
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    /// Ethereum/EVM engine operation: Send token in background.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func sendTokenInBackground(
        seedPhrase: String,
        to toAddress: String,
        token: EthereumSupportedToken,
        amount: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum,
        derivationAccount: UInt32 = 0
    ) async throws -> EthereumSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    do {
                        let result = try await sendToken(
                            seedPhrase: seedPhrase,
                            to: toAddress,
                            token: token,
                            amount: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: rpcEndpoint,
                            chain: chain,
                            derivationAccount: derivationAccount
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    static func sendInBackground(
        privateKeyHex: String,
        to toAddress: String,
        amountETH: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    do {
                        let result = try await send(
                            privateKeyHex: privateKeyHex,
                            to: toAddress,
                            amountETH: amountETH,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: rpcEndpoint,
                            chain: chain
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    static func sendTokenInBackground(
        privateKeyHex: String,
        to toAddress: String,
        token: EthereumSupportedToken,
        amount: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    do {
                        let result = try await sendToken(
                            privateKeyHex: privateKeyHex,
                            to: toAddress,
                            token: token,
                            amount: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: rpcEndpoint,
                            chain: chain
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Ethereum/EVM engine operation: Fetch transaction receipt.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchTransactionReceipt(
        transactionHash: String,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumTransactionReceipt? {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHash.hasPrefix("0x"), normalizedHash.count == 66 else {
            throw EthereumWalletEngineError.invalidResponse
        }

        let resolvedRPCEndpoints = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain)
        var lastError: Error?
        var sawValidEmptyReceipt = false
        var requestID = 14
        for endpoint in resolvedRPCEndpoints {
            let payload = EthereumJSONRPCRequest(
                id: requestID,
                method: "eth_getTransactionReceipt",
                params: [normalizedHash]
            )
            requestID += 1

            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 20
                request.httpBody = try JSONEncoder().encode(payload)

                let (data, response) = try await fetchData(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ..< 300).contains(httpResponse.statusCode) else {
                    throw EthereumWalletEngineError.invalidResponse
                }

                let decoded = try JSONDecoder().decode(EthereumTransactionReceiptJSONRPCResponse.self, from: data)
                if let rpcError = decoded.error {
                    throw EthereumWalletEngineError.rpcFailure(rpcError.message)
                }

                guard let receiptPayload = decoded.result else {
                    sawValidEmptyReceipt = true
                    continue
                }

                let blockNumber = receiptPayload.blockNumber.flatMap { Int($0.dropFirst(2), radix: 16) }
                let gasUsed = try receiptPayload.gasUsed.map(decimal(fromHexQuantity:))
                let effectiveGasPriceWei = try receiptPayload.effectiveGasPrice.map(decimal(fromHexQuantity:))
                return EthereumTransactionReceipt(
                    transactionHash: receiptPayload.transactionHash,
                    blockNumber: blockNumber,
                    status: receiptPayload.status,
                    gasUsed: gasUsed,
                    effectiveGasPriceWei: effectiveGasPriceWei
                )
            } catch {
                lastError = error
            }
        }

        if sawValidEmptyReceipt {
            return nil
        }
        throw lastError ?? EthereumWalletEngineError.invalidResponse
    }

    /// Ethereum/EVM engine operation: Send in background.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func sendInBackground(
        seedPhrase: String,
        to toAddress: String,
        amountETH: Double,
        explicitNonce: Int? = nil,
        customFees: EthereumCustomFeeConfiguration? = nil,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum,
        derivationAccount: UInt32 = 0
    ) async throws -> EthereumSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    do {
                        let result = try await send(
                            seedPhrase: seedPhrase,
                            to: toAddress,
                            amountETH: amountETH,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: rpcEndpoint,
                            chain: chain,
                            derivationAccount: derivationAccount
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Ethereum/EVM engine operation: Fetch rpchealth.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchRPCHealth(rpcEndpoint: URL? = nil, chain: EVMChainContext = .ethereum) async throws -> EthereumRPCHealthSnapshot {
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        async let chainID = fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
        async let blockHex = performRPC(
            method: "eth_blockNumber",
            params: [String](),
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 31
        )

        let latestBlockHex = try await blockHex
        guard let latestBlockNumber = Int(latestBlockHex.dropFirst(2), radix: 16) else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }

        return EthereumRPCHealthSnapshot(
            chainID: try await chainID,
            latestBlockNumber: latestBlockNumber
        )
    }

    /// Ethereum/EVM engine operation: Fetch transaction count.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchTransactionCount(
        for address: String,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> Int {
        let normalizedAddress = try validateAddress(address)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let nonceHex = try await performRPC(
            method: "eth_getTransactionCount",
            params: [normalizedAddress, "latest"],
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 32
        )
        return Int(nonceHex.dropFirst(2), radix: 16) ?? 0
    }

    /// Ethereum/EVM engine operation: Fetch transaction nonce.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func fetchTransactionNonce(
        for transactionHash: String,
        rpcEndpoint: URL? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> Int {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHash.hasPrefix("0x"), normalizedHash.count == 66 else {
            throw EthereumWalletEngineError.invalidResponse
        }
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let payload: EthereumTransactionPayload = try await performRPCDecoded(
            method: "eth_getTransactionByHash",
            params: [normalizedHash],
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 33
        )
        guard let nonceHex = payload.nonce else {
            throw EthereumWalletEngineError.invalidResponse
        }
        return Int(nonceHex.dropFirst(2), radix: 16) ?? 0
    }

    /// Ethereum/EVM engine operation: Broadcast raw transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func broadcastRawTransaction(
        _ rawTransaction: Data,
        preferredRPCEndpoint: URL?,
        chain: EVMChainContext = .ethereum
    ) async throws -> String {
        let rawHex = "0x" + rawTransaction.map { String(format: "%02x", $0) }.joined()
        return try await performRPC(
            method: "eth_sendRawTransaction",
            params: [rawHex],
            rpcEndpoint: resolvedRPCEndpoints(preferred: preferredRPCEndpoint, chain: chain).first!,
            requestID: 12
        )
    }

    private static func performRPC<Params: Encodable>(
        method: String,
        params: Params,
        rpcEndpoint: URL,
        requestID: Int
    ) async throws -> String {
        let inferred = inferredChainContext(for: rpcEndpoint)
        let endpoints = resolvedRPCEndpoints(fallbackFrom: rpcEndpoint, chain: inferred)
        var lastError: Error?
        var nextRequestID = requestID
        for endpoint in endpoints {
            do {
                return try await performRPCOnce(
                    method: method,
                    params: params,
                    rpcEndpoint: endpoint,
                    requestID: nextRequestID
                )
            } catch {
                lastError = error
                nextRequestID += 1
            }
        }
        throw lastError ?? EthereumWalletEngineError.invalidResponse
    }

    private static func performRPCOnce<Params: Encodable>(
        method: String,
        params: Params,
        rpcEndpoint: URL,
        requestID: Int
    ) async throws -> String {
        let payload = EthereumJSONRPCRequest(
            id: requestID,
            method: method,
            params: params
        )
        var request = URLRequest(url: rpcEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw EthereumWalletEngineError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(EthereumJSONRPCResponse.self, from: data)
        if let rpcError = decoded.error {
            throw EthereumWalletEngineError.rpcFailure(rpcError.message)
        }

        guard let result = decoded.result else {
            throw EthereumWalletEngineError.invalidResponse
        }

        return result
    }

    private static func performRPCDecoded<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params,
        rpcEndpoint: URL,
        requestID: Int
    ) async throws -> Result {
        let inferred = inferredChainContext(for: rpcEndpoint)
        let endpoints = resolvedRPCEndpoints(fallbackFrom: rpcEndpoint, chain: inferred)
        var lastError: Error?
        var nextRequestID = requestID
        for endpoint in endpoints {
            do {
                return try await performRPCDecodedOnce(
                    method: method,
                    params: params,
                    rpcEndpoint: endpoint,
                    requestID: nextRequestID
                )
            } catch {
                lastError = error
                nextRequestID += 1
            }
        }
        throw lastError ?? EthereumWalletEngineError.invalidResponse
    }

    private static func performRPCDecodedOnce<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params,
        rpcEndpoint: URL,
        requestID: Int
    ) async throws -> Result {
        let payload = EthereumJSONRPCRequest(
            id: requestID,
            method: method,
            params: params
        )
        var request = URLRequest(url: rpcEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw EthereumWalletEngineError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(EthereumJSONRPCDecodedResponse<Result>.self, from: data)
        if let rpcError = decoded.error {
            throw EthereumWalletEngineError.rpcFailure(rpcError.message)
        }

        guard let result = decoded.result else {
            throw EthereumWalletEngineError.invalidResponse
        }

        return result
    }

    /// Ethereum/EVM engine operation: Fetch data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
    }

    /// Ethereum/EVM engine operation: Fetch eip1559 fee parameters.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchEIP1559FeeParameters(
        rpcEndpoint: URL,
        customFees: EthereumCustomFeeConfiguration?
    ) async throws -> (maxFeePerGasWei: Decimal, maxPriorityFeePerGasWei: Decimal) {
        if let customFees {
            let maxFeePerGasWei = Decimal(string: String(format: "%.9f", customFees.maxFeePerGasGwei))! * decimalPowerOfTen(9)
            let maxPriorityFeePerGasWei = Decimal(string: String(format: "%.9f", customFees.maxPriorityFeePerGasGwei))! * decimalPowerOfTen(9)
            guard maxFeePerGasWei > 0,
                  maxPriorityFeePerGasWei > 0,
                  maxFeePerGasWei >= maxPriorityFeePerGasWei else {
                throw EthereumWalletEngineError.rpcFailure("Invalid custom fee settings. Max fee must be greater than or equal to priority fee.")
            }
            return (maxFeePerGasWei, maxPriorityFeePerGasWei)
        }

        async let feeHistory: EthereumFeeHistoryResult = performRPCDecoded(
            method: "eth_feeHistory",
            params: EthereumFeeHistoryParameters(
                blockCountHex: "0x5",
                blockTag: "latest",
                rewardPercentiles: [25, 50, 75]
            ),
            rpcEndpoint: rpcEndpoint,
            requestID: 21
        )
        async let fallbackGasPriceHex = performRPC(
            method: "eth_gasPrice",
            params: [String](),
            rpcEndpoint: rpcEndpoint,
            requestID: 22
        )

        do {
            let history = try await feeHistory
            let fallbackGasPriceWei = try decimal(fromHexQuantity: try await fallbackGasPriceHex)
            guard let latestBaseFeeHex = history.baseFeePerGas.last else {
                return (fallbackGasPriceWei, min(fallbackGasPriceWei, Decimal(2_000_000_000)))
            }

            let latestBaseFeeWei = try decimal(fromHexQuantity: latestBaseFeeHex)
            let rewardCandidates = history.reward?.flatMap { $0 } ?? []
            let priorityCandidatesWei: [Decimal] = try rewardCandidates.map { try decimal(fromHexQuantity: $0) }
            let suggestedPriorityWei = priorityCandidatesWei.max() ?? Decimal(2_000_000_000)
            let boundedPriorityWei = min(max(suggestedPriorityWei, Decimal(1_000_000_000)), Decimal(5_000_000_000))
            let suggestedMaxFeeWei = (latestBaseFeeWei * 2) + boundedPriorityWei
            let maxFeeWei = max(suggestedMaxFeeWei, fallbackGasPriceWei)
            return (maxFeeWei, boundedPriorityWei)
        } catch {
            let fallbackGasPriceWei = try decimal(fromHexQuantity: try await fallbackGasPriceHex)
            return (fallbackGasPriceWei, min(fallbackGasPriceWei, Decimal(2_000_000_000)))
        }
    }

    /// Ethereum/EVM engine operation: Fetch send parameters.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchSendParameters(
        from fromAddress: String,
        to toAddress: String,
        valueWei: Decimal,
        data: String?,
        explicitNonce: Int?,
        customFees: EthereumCustomFeeConfiguration?,
        rpcEndpoint: URL?,
        chain: EVMChainContext = .ethereum
    ) async throws -> EthereumSendParameters {
        let normalizedFromAddress = try validateAddress(fromAddress)
        let normalizedToAddress = try validateAddress(toAddress)
        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        let valueHex = hexQuantity(from: valueWei)

        // Best-effort simulation only. Some RPC providers return opaque internal errors for
        // valid token transfers; we still want nonce/fee preview to proceed.
        _ = try? await performRPC(
            method: "eth_call",
            params: EthereumSimulationParameters(
                call: EthereumSimulationRequest(
                    from: normalizedFromAddress,
                    to: normalizedToAddress,
                    value: valueHex,
                    data: data
                ),
                blockTag: "latest"
            ),
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 9
        )

        async let nonceHex: String? = explicitNonce == nil
            ? performRPC(
                method: "eth_getTransactionCount",
                params: [normalizedFromAddress, "pending"],
                rpcEndpoint: resolvedRPCEndpoint,
                requestID: 10
            )
            : nil
        async let feeParameters = fetchEIP1559FeeParameters(
            rpcEndpoint: resolvedRPCEndpoint,
            customFees: customFees
        )

        let nonce: Int
        if let explicitNonce {
            nonce = explicitNonce
        } else {
            let resolvedNonceHex = try await nonceHex ?? "0x0"
            nonce = Int(resolvedNonceHex.dropFirst(2), radix: 16) ?? 0
        }
        let gasLimit: Int
        do {
            let gasLimitHex = try await performRPC(
                method: "eth_estimateGas",
                params: [
                    EthereumEstimateGasRequest(
                        from: normalizedFromAddress,
                        to: normalizedToAddress,
                        value: valueHex,
                        data: data
                    )
                ],
                rpcEndpoint: resolvedRPCEndpoint,
                requestID: 11
            )
            gasLimit = Int(gasLimitHex.dropFirst(2), radix: 16) ?? (data == nil ? 21_000 : 120_000)
        } catch {
            gasLimit = data == nil ? 21_000 : 120_000
        }
        let resolvedFeeParameters = try await feeParameters
        return EthereumSendParameters(
            nonce: nonce,
            gasLimit: gasLimit,
            maxFeePerGasWei: resolvedFeeParameters.maxFeePerGasWei,
            maxPriorityFeePerGasWei: resolvedFeeParameters.maxPriorityFeePerGasWei
        )
    }

    /// Ethereum/EVM engine operation: Fetch chain id.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchChainID(rpcEndpoint: URL) async throws -> Int {
        let chainIDHex = try await performRPC(
            method: "eth_chainId",
            params: [String](),
            rpcEndpoint: rpcEndpoint,
            requestID: 13
        )
        guard let chainID = Int(chainIDHex.dropFirst(2), radix: 16) else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }
        return chainID
    }

    /// Ethereum/EVM engine operation: Etherscan apiurl.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func etherscanAPIURL(for chain: EVMChainContext) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.etherscanStyleAPIURL(for: chain.displayName)
    }

    /// Ethereum/EVM engine operation: Blockscout token transfers url.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func blockscoutTokenTransfersURL(
        for chain: EVMChainContext,
        normalizedAddress: String,
        page: Int,
        pageSize: Int
    ) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.blockscoutTokenTransfersURL(
            for: chain.displayName,
            normalizedAddress: normalizedAddress,
            page: page,
            pageSize: pageSize
        )
    }

    private static func blockscoutAccountAPIURL(
        for chain: EVMChainContext,
        normalizedAddress: String,
        action: String,
        page: Int,
        pageSize: Int
    ) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.blockscoutAccountAPIURL(
            for: chain.displayName,
            normalizedAddress: normalizedAddress,
            action: action,
            page: page,
            pageSize: pageSize
        )
    }

    /// Ethereum/EVM engine operation: Ethplorer history url.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func ethplorerHistoryURL(
        for chain: EVMChainContext,
        normalizedAddress: String,
        requestedLimit: Int
    ) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.ethplorerHistoryURL(
            for: chain.displayName,
            normalizedAddress: normalizedAddress,
            requestedLimit: requestedLimit
        )
    }


    /// Ethereum/EVM engine operation: Fetch token transfer history from etherscan.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchTokenTransferHistoryFromEtherscan(
        normalizedAddress: String,
        chainTokens: [EthereumSupportedToken],
        supportedTokensByContract: [String: EthereumSupportedToken],
        supportedTokensBySymbol: [String: EthereumSupportedToken],
        apiKey: String?,
        maxResults: Int,
        page: Int = 1,
        pageSize: Int? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
        let trimmedAPIKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let safePage = max(1, page)
        let effectivePageSize = max(10, min(pageSize ?? maxResults, 500))
        var transfers: [EthereumTokenTransferSnapshot] = []
        var scannedTransfers = 0
        var decodedSupportedTransfers = 0
        var droppedUnsupportedTransfers = 0
        for token in chainTokens {
            guard let baseURL = etherscanAPIURL(for: chain) else { continue }
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            var queryItems = [
                URLQueryItem(name: "module", value: "account"),
                URLQueryItem(name: "action", value: "tokentx"),
                URLQueryItem(name: "address", value: normalizedAddress),
                URLQueryItem(name: "contractaddress", value: token.contractAddress),
                URLQueryItem(name: "page", value: String(safePage)),
                URLQueryItem(name: "offset", value: String(effectivePageSize)),
                URLQueryItem(name: "sort", value: "desc")
            ]
            if !trimmedAPIKey.isEmpty {
                queryItems.append(URLQueryItem(name: "apikey", value: trimmedAPIKey))
            }
            switch chain {
            case .ethereum:
                queryItems.insert(URLQueryItem(name: "chainid", value: "1"), at: 0)
            case .arbitrum:
                queryItems.insert(URLQueryItem(name: "chainid", value: "42161"), at: 0)
            case .optimism:
                queryItems.insert(URLQueryItem(name: "chainid", value: "10"), at: 0)
            case .hyperliquid:
                queryItems.insert(URLQueryItem(name: "chainid", value: "999"), at: 0)
            default:
                break
            }
            components?.queryItems = queryItems
            guard let url = components?.url else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await fetchData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                continue
            }

            let decoded = try JSONDecoder().decode(EtherscanTokenTransferResponse.self, from: data)
            if let status = decoded.status, status != "1" {
                let message = decoded.message ?? "Unknown Etherscan response"
                let reason = decoded.resultText ?? message
                if reason.lowercased().contains("no transactions") {
                    continue
                }
                if reason.lowercased().contains("missing/invalid api key") {
                    continue
                }
                throw EthereumWalletEngineError.rpcFailure("Etherscan: \(reason)")
            }
            let items = decoded.result
            guard !items.isEmpty else { continue }
            scannedTransfers += items.count

            for (index, item) in items.enumerated() {
                let contract = normalizeAddress(item.contractAddress)
                let normalizedSymbol = item.tokenSymbol.uppercased()
                guard let resolvedToken = supportedTokensByContract[contract] ?? supportedTokensBySymbol[normalizedSymbol] else {
                    droppedUnsupportedTransfers += 1
                    continue
                }

                let fromAddress = normalizeAddress(item.from)
                let toAddress = normalizeAddress(item.to)
                guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
                    continue
                }

                guard let blockNumber = Int(item.blockNumber),
                      let timestampSeconds = TimeInterval(item.timeStamp),
                      let amountUnits = Decimal(string: item.value) else {
                    continue
                }
                let decimals = Int(item.tokenDecimal) ?? resolvedToken.decimals
                let amount = amountUnits / decimalPowerOfTen(decimals)

                transfers.append(
                    EthereumTokenTransferSnapshot(
                        contractAddress: resolvedToken.contractAddress,
                        tokenName: resolvedToken.name,
                        symbol: resolvedToken.symbol,
                        decimals: resolvedToken.decimals,
                        fromAddress: fromAddress,
                        toAddress: toAddress,
                        amount: amount,
                        transactionHash: item.hash,
                        blockNumber: blockNumber,
                        logIndex: max(0, items.count - index),
                        timestamp: Date(timeIntervalSince1970: timestampSeconds)
                    )
                )
                decodedSupportedTransfers += 1
            }
        }

        var seen: Set<String> = []
        transfers = transfers.filter { transfer in
            let key = "\(transfer.transactionHash.lowercased())-\(transfer.symbol)-\(transfer.fromAddress)-\(transfer.toAddress)-\(transfer.amount)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        transfers.sort { lhs, rhs in
            if lhs.blockNumber != rhs.blockNumber {
                return lhs.blockNumber > rhs.blockNumber
            }
            return lhs.logIndex > rhs.logIndex
        }
        return (
            Array(transfers.prefix(effectivePageSize)),
            EthereumTransferDecodingStats(
                scannedTransfers: scannedTransfers,
                decodedSupportedTransfers: decodedSupportedTransfers,
                droppedUnsupportedTransfers: droppedUnsupportedTransfers
            )
        )
    }

    static func fetchNativeTransferHistoryPageFromEtherscan(
        for normalizedAddress: String,
        apiKey: String?,
        page: Int = 1,
        pageSize: Int = 100,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumNativeTransferSnapshot] {
        if chain == .hyperliquid {
            return try await fetchNativeTransferHistoryPageFromHyperliquidExplorerAddressPage(
                normalizedAddress: normalizedAddress,
                page: page,
                pageSize: pageSize,
                chain: chain
            )
        }
        let trimmedAPIKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = etherscanAPIURL(for: chain) else {
            return []
        }

        let safePage = max(1, page)
        let effectivePageSize = max(10, min(pageSize, 500))
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "txlist"),
            URLQueryItem(name: "address", value: normalizedAddress),
            URLQueryItem(name: "page", value: String(safePage)),
            URLQueryItem(name: "offset", value: String(effectivePageSize)),
            URLQueryItem(name: "sort", value: "desc")
        ]
        if !trimmedAPIKey.isEmpty {
            queryItems.append(URLQueryItem(name: "apikey", value: trimmedAPIKey))
        }
        switch chain {
        case .ethereum:
            queryItems.insert(URLQueryItem(name: "chainid", value: "1"), at: 0)
        case .arbitrum:
            queryItems.insert(URLQueryItem(name: "chainid", value: "42161"), at: 0)
        case .optimism:
            queryItems.insert(URLQueryItem(name: "chainid", value: "10"), at: 0)
        case .hyperliquid:
            queryItems.insert(URLQueryItem(name: "chainid", value: "999"), at: 0)
        default:
            break
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(EtherscanNormalTransactionResponse.self, from: data)
        if let status = decoded.status, status != "1" {
            let message = decoded.message ?? "Unknown Etherscan response"
            let reason = decoded.resultText ?? message
            if reason.lowercased().contains("no transactions") {
                return []
            }
            if reason.lowercased().contains("missing/invalid api key") {
                return []
            }
            throw EthereumWalletEngineError.rpcFailure("Etherscan: \(reason)")
        }

        return decoded.result.compactMap { item in
            let fromAddress = normalizeAddress(item.from)
            let toAddress = normalizeAddress(item.to)
            guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
                return nil
            }
            if item.isError == "1" || item.txreceipt_status == "0" {
                return nil
            }
            guard let blockNumber = Int(item.blockNumber),
                  let timestampSeconds = TimeInterval(item.timeStamp),
                  let amountWei = Decimal(string: item.value) else {
                return nil
            }
            let amount = amountWei / decimalPowerOfTen(18)

            return EthereumNativeTransferSnapshot(
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                transactionHash: item.hash,
                blockNumber: blockNumber,
                timestamp: Date(timeIntervalSince1970: timestampSeconds)
            )
        }
    }

    static func fetchNativeTransferHistoryPageFromBlockscout(
        for normalizedAddress: String,
        page: Int = 1,
        pageSize: Int = 100,
        chain: EVMChainContext = .ethereum
    ) async throws -> [EthereumNativeTransferSnapshot] {
        guard let url = blockscoutAccountAPIURL(
            for: chain,
            normalizedAddress: normalizedAddress,
            action: "txlist",
            page: page,
            pageSize: pageSize
        ) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(BlockscoutNormalTransactionsResponse.self, from: data)
        guard !decoded.items.isEmpty else { return [] }

        return decoded.items.compactMap { item in
            guard item.result?.lowercased() != "error" else {
                return nil
            }
            guard let fromHash = item.from?.hash,
                  let toHash = item.to?.hash else {
                return nil
            }
            let fromAddress = normalizeAddress(fromHash)
            let toAddress = normalizeAddress(toHash)
            guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
                return nil
            }
            guard let blockNumber = item.block?.height,
                  let timestampRaw = item.timestamp,
                  let timestamp = iso8601Formatter.date(from: timestampRaw),
                  let valueRaw = item.value,
                  let amountWei = Decimal(string: valueRaw) else {
                return nil
            }

            return EthereumNativeTransferSnapshot(
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amountWei / decimalPowerOfTen(18),
                transactionHash: item.hash ?? "",
                blockNumber: blockNumber,
                timestamp: timestamp
            )
        }
    }

    /// Ethereum/EVM engine operation: Fetch token transfer history from ethplorer.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchTokenTransferHistoryFromEthplorer(
        normalizedAddress: String,
        supportedTokensByContract: [String: EthereumSupportedToken],
        supportedTokensBySymbol: [String: EthereumSupportedToken],
        maxResults: Int,
        page: Int = 1,
        pageSize: Int? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
        let safePage = max(1, page)
        let effectivePageSize = max(10, min(pageSize ?? maxResults, 500))
        let requestedLimit = min(max(safePage * effectivePageSize, effectivePageSize), 1000)
        guard let url = ethplorerHistoryURL(
            for: chain,
            normalizedAddress: normalizedAddress,
            requestedLimit: requestedLimit
        ) else {
            return (.init(), .zero)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            return (.init(), .zero)
        }

        if let errorDecoded = try? JSONDecoder().decode(EthplorerErrorResponse.self, from: data),
           let errorMessage = errorDecoded.error?.message,
           !errorMessage.isEmpty {
            throw EthereumWalletEngineError.rpcFailure("Ethplorer: \(errorMessage)")
        }

        let decoded = try JSONDecoder().decode(EthplorerAddressHistoryResponse.self, from: data)
        guard let operations = decoded.operations, !operations.isEmpty else {
            return (.init(), .zero)
        }

        var transfers: [EthereumTokenTransferSnapshot] = []
        transfers.reserveCapacity(operations.count)
        var scannedTransfers = 0
        var decodedSupportedTransfers = 0
        var droppedUnsupportedTransfers = 0
        for (index, op) in operations.enumerated() {
            scannedTransfers += 1
            guard let txHash = op.transactionHash,
                  let from = op.from,
                  let to = op.to,
                  let tokenAddress = op.tokenInfo?.address,
                  let valueString = op.value,
                  let timestamp = op.timestamp else {
                continue
            }

            let normalizedContract = normalizeAddress(tokenAddress)
            let symbol = op.tokenInfo?.symbol?.uppercased() ?? ""
            guard let supportedToken = supportedTokensByContract[normalizedContract] ?? supportedTokensBySymbol[symbol] else {
                droppedUnsupportedTransfers += 1
                continue
            }

            let normalizedFrom = normalizeAddress(from)
            let normalizedTo = normalizeAddress(to)
            guard normalizedFrom == normalizedAddress || normalizedTo == normalizedAddress else {
                continue
            }

            guard let rawValue = Decimal(string: valueString) else {
                continue
            }
            let amount = rawValue / decimalPowerOfTen(supportedToken.decimals)
            let blockNumber = op.blockNumber ?? 0

            transfers.append(
                EthereumTokenTransferSnapshot(
                    contractAddress: supportedToken.contractAddress,
                    tokenName: supportedToken.name,
                    symbol: supportedToken.symbol,
                    decimals: supportedToken.decimals,
                    fromAddress: normalizedFrom,
                    toAddress: normalizedTo,
                    amount: amount,
                    transactionHash: txHash,
                    blockNumber: blockNumber,
                    logIndex: max(0, operations.count - index),
                    timestamp: Date(timeIntervalSince1970: timestamp)
                )
            )
            decodedSupportedTransfers += 1
        }

        transfers.sort { lhs, rhs in
            if lhs.blockNumber != rhs.blockNumber {
                return lhs.blockNumber > rhs.blockNumber
            }
            return lhs.logIndex > rhs.logIndex
        }
        let pageSlice = paginateTransferSnapshots(
            transfers,
            page: safePage,
            pageSize: effectivePageSize
        )
        return (
            Array(pageSlice.prefix(effectivePageSize)),
            EthereumTransferDecodingStats(
                scannedTransfers: scannedTransfers,
                decodedSupportedTransfers: decodedSupportedTransfers,
                droppedUnsupportedTransfers: droppedUnsupportedTransfers
            )
        )
    }

    /// Ethereum/EVM engine operation: Fetch token transfer history from blockscout.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func fetchTokenTransferHistoryFromBlockscout(
        normalizedAddress: String,
        supportedTokensByContract: [String: EthereumSupportedToken],
        supportedTokensBySymbol: [String: EthereumSupportedToken],
        maxResults: Int,
        page: Int = 1,
        pageSize: Int? = nil,
        chain: EVMChainContext = .ethereum
    ) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
        let safePage = max(1, page)
        let effectivePageSize = max(10, min(pageSize ?? maxResults, 200))
        guard let url = blockscoutTokenTransfersURL(
            for: chain,
            normalizedAddress: normalizedAddress,
            page: safePage,
            pageSize: effectivePageSize
        ) else {
            return (.init(), .zero)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            return (.init(), .zero)
        }

        let decoded = try JSONDecoder().decode(BlockscoutTokenTransfersResponse.self, from: data)
        guard !decoded.items.isEmpty else { return (.init(), .zero) }

        var transfers: [EthereumTokenTransferSnapshot] = []
        transfers.reserveCapacity(decoded.items.count)
        var scannedTransfers = 0
        var decodedSupportedTransfers = 0
        var droppedUnsupportedTransfers = 0
        for (index, item) in decoded.items.enumerated() {
            scannedTransfers += 1
            guard let txHash = item.transaction_hash,
                  let from = item.from?.hash,
                  let to = item.to?.hash,
                  let tokenAddress = item.token?.address,
                  let rawValue = item.total?.value,
                  let decimalValue = Decimal(string: rawValue) else {
                continue
            }

            let normalizedContract = normalizeAddress(tokenAddress)
            let symbol = item.token?.symbol?.uppercased() ?? ""
            guard let supportedToken = supportedTokensByContract[normalizedContract] ?? supportedTokensBySymbol[symbol] else {
                droppedUnsupportedTransfers += 1
                continue
            }

            let normalizedFrom = normalizeAddress(from)
            let normalizedTo = normalizeAddress(to)
            guard normalizedFrom == normalizedAddress || normalizedTo == normalizedAddress else {
                continue
            }

            let amount = decimalValue / decimalPowerOfTen(supportedToken.decimals)
            let blockNumber = item.block_number ?? 0
            let timestamp = item.timestamp.flatMap { iso8601Formatter.date(from: $0) }
            transfers.append(
                EthereumTokenTransferSnapshot(
                    contractAddress: supportedToken.contractAddress,
                    tokenName: supportedToken.name,
                    symbol: supportedToken.symbol,
                    decimals: supportedToken.decimals,
                    fromAddress: normalizedFrom,
                    toAddress: normalizedTo,
                    amount: amount,
                    transactionHash: txHash,
                    blockNumber: blockNumber,
                    logIndex: max(0, decoded.items.count - index),
                    timestamp: timestamp
                )
            )
            decodedSupportedTransfers += 1
        }

        transfers.sort { lhs, rhs in
            if lhs.blockNumber != rhs.blockNumber {
                return lhs.blockNumber > rhs.blockNumber
            }
            return lhs.logIndex > rhs.logIndex
        }
        return (
            Array(transfers.prefix(effectivePageSize)),
            EthereumTransferDecodingStats(
                scannedTransfers: scannedTransfers,
                decodedSupportedTransfers: decodedSupportedTransfers,
                droppedUnsupportedTransfers: droppedUnsupportedTransfers
            )
        )
    }

    private static func fetchTokenTransferHistoryFromHyperliquidExplorerAddressPage(
        normalizedAddress: String,
        chainTokens: [EthereumSupportedToken],
        maxResults: Int,
        page: Int,
        pageSize: Int,
        rpcEndpoint: URL?,
        chain: EVMChainContext
    ) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
        let resolvedTransactions = try await fetchHyperliquidExplorerResolvedTransactions(
            normalizedAddress: normalizedAddress,
            page: page,
            pageSize: pageSize,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
        guard !resolvedTransactions.isEmpty else {
            return ([], .zero)
        }

        let supportedTokensByContract = Dictionary(
            uniqueKeysWithValues: chainTokens.map { (normalizeAddress($0.contractAddress), $0) }
        )
        let transferTopic = "0xddf252ad"
        var scannedTransfers = 0
        var decodedSupportedTransfers = 0
        var droppedUnsupportedTransfers = 0
        var snapshots: [EthereumTokenTransferSnapshot] = []

        for transaction in resolvedTransactions {
            for log in transaction.logs {
                scannedTransfers += 1
                guard let firstTopic = log.topics.first?.lowercased(),
                      firstTopic.hasPrefix(transferTopic),
                      log.topics.count >= 3 else {
                    continue
                }

                let contractAddress = normalizeAddress(log.address)
                guard let token = supportedTokensByContract[contractAddress] else {
                    droppedUnsupportedTransfers += 1
                    continue
                }

                guard let fromAddress = addressFromIndexedTopic(log.topics[1]),
                      let toAddress = addressFromIndexedTopic(log.topics[2]) else {
                    continue
                }
                guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
                    continue
                }

                let amountUnits = try decimal(fromHexQuantity: log.data)
                let amount = amountUnits / decimalPowerOfTen(token.decimals)
                let logIndex = log.logIndex.flatMap { Int($0.dropFirst(2), radix: 16) } ?? 0
                snapshots.append(
                    EthereumTokenTransferSnapshot(
                        contractAddress: token.contractAddress,
                        tokenName: token.name,
                        symbol: token.symbol,
                        decimals: token.decimals,
                        fromAddress: fromAddress,
                        toAddress: toAddress,
                        amount: amount,
                        transactionHash: transaction.transactionHash,
                        blockNumber: transaction.blockNumber,
                        logIndex: logIndex,
                        timestamp: transaction.timestamp
                    )
                )
                decodedSupportedTransfers += 1
            }
        }

        snapshots.sort { lhs, rhs in
            if lhs.blockNumber != rhs.blockNumber {
                return lhs.blockNumber > rhs.blockNumber
            }
            return lhs.logIndex > rhs.logIndex
        }

        return (
            Array(snapshots.prefix(maxResults)),
            EthereumTransferDecodingStats(
                scannedTransfers: scannedTransfers,
                decodedSupportedTransfers: decodedSupportedTransfers,
                droppedUnsupportedTransfers: droppedUnsupportedTransfers
            )
        )
    }

    private static func fetchNativeTransferHistoryPageFromHyperliquidExplorerAddressPage(
        normalizedAddress: String,
        page: Int,
        pageSize: Int,
        chain: EVMChainContext
    ) async throws -> [EthereumNativeTransferSnapshot] {
        let resolvedTransactions = try await fetchHyperliquidExplorerResolvedTransactions(
            normalizedAddress: normalizedAddress,
            page: page,
            pageSize: pageSize,
            rpcEndpoint: nil,
            chain: chain
        )

        return resolvedTransactions.compactMap { transaction in
            guard transaction.fromAddress == normalizedAddress || transaction.toAddress == normalizedAddress else {
                return nil
            }
            return EthereumNativeTransferSnapshot(
                fromAddress: transaction.fromAddress,
                toAddress: transaction.toAddress,
                amount: transaction.value / decimalPowerOfTen(18),
                transactionHash: transaction.transactionHash,
                blockNumber: transaction.blockNumber,
                timestamp: transaction.timestamp
            )
        }
    }

    private static func fetchHyperliquidExplorerResolvedTransactions(
        normalizedAddress: String,
        page: Int,
        pageSize: Int,
        rpcEndpoint: URL?,
        chain: EVMChainContext
    ) async throws -> [HyperliquidExplorerResolvedTransaction] {
        guard page == 1 else { return [] }
        let transactionHashes = try await fetchHyperliquidExplorerTransactionHashes(
            for: normalizedAddress,
            maxResults: max(1, min(pageSize, 25))
        )
        guard !transactionHashes.isEmpty else { return [] }

        let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
        var transactionsByHash: [String: (payload: EthereumTransactionByHashPayload, receipt: EthereumTransactionReceiptWithLogsPayload)] = [:]
        try await withThrowingTaskGroup(of: (String, EthereumTransactionByHashPayload, EthereumTransactionReceiptWithLogsPayload)?.self) { group in
            for transactionHash in transactionHashes {
                group.addTask {
                    do {
                        let payload: EthereumTransactionByHashPayload = try await performRPCDecoded(
                            method: "eth_getTransactionByHash",
                            params: [transactionHash],
                            rpcEndpoint: resolvedRPCEndpoint,
                            requestID: 71
                        )
                        let receipt: EthereumTransactionReceiptWithLogsPayload = try await performRPCDecoded(
                            method: "eth_getTransactionReceipt",
                            params: [transactionHash],
                            rpcEndpoint: resolvedRPCEndpoint,
                            requestID: 72
                        )
                        guard receipt.status != "0x0",
                              let blockNumberHex = payload.blockNumber ?? receipt.blockNumber,
                              !blockNumberHex.isEmpty else {
                            return nil
                        }
                        return (transactionHash, payload, receipt)
                    } catch {
                        return nil
                    }
                }
            }

            for try await item in group {
                guard let item else { continue }
                transactionsByHash[item.0] = (item.1, item.2)
            }
        }

        let blockHexes = Set(transactionsByHash.values.compactMap { $0.payload.blockNumber ?? $0.receipt.blockNumber })
        var timestampsByBlockHex: [String: Date] = [:]
        try await withThrowingTaskGroup(of: (String, Date?).self) { group in
            for blockHex in blockHexes {
                group.addTask {
                    do {
                        let block: EthereumBlockPayload = try await performRPCDecoded(
                            method: "eth_getBlockByNumber",
                            params: EthereumBlockByNumberParameters(
                                blockNumber: blockHex,
                                includeTransactions: false
                            ),
                            rpcEndpoint: resolvedRPCEndpoint,
                            requestID: 73
                        )
                        let timestampValue = Int(block.timestamp.dropFirst(2), radix: 16).map(TimeInterval.init)
                        return (blockHex, timestampValue.map { Date(timeIntervalSince1970: $0) })
                    } catch {
                        return (blockHex, nil)
                    }
                }
            }

            for try await (blockHex, timestamp) in group {
                if let timestamp {
                    timestampsByBlockHex[blockHex] = timestamp
                }
            }
        }

        return transactionHashes.compactMap { transactionHash in
            guard let resolved = transactionsByHash[transactionHash] else { return nil }
            let blockNumberHex = resolved.payload.blockNumber ?? resolved.receipt.blockNumber ?? ""
            guard let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16),
                  let value = try? decimal(fromHexQuantity: resolved.payload.value) else {
                return nil
            }
            return HyperliquidExplorerResolvedTransaction(
                transactionHash: transactionHash,
                blockNumber: blockNumber,
                fromAddress: normalizeAddress(resolved.payload.from),
                toAddress: normalizeAddress(resolved.payload.to ?? ""),
                value: value,
                timestamp: timestampsByBlockHex[blockNumberHex],
                logs: resolved.receipt.logs
            )
        }
    }

    private static func fetchHyperliquidExplorerTransactionHashes(
        for normalizedAddress: String,
        maxResults: Int
    ) async throws -> [String] {
        guard let url = ChainBackendRegistry.EVMExplorerRegistry.addressExplorerURL(
            for: ChainBackendRegistry.hyperliquidChainName,
            normalizedAddress: normalizedAddress
        ) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }

        let pattern = #"/tx/(0x[0-9a-fA-F]{64})"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: nsRange)

        var hashes: [String] = []
        var seen: Set<String> = []
        for match in matches {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else {
                continue
            }
            let hash = String(html[range]).lowercased()
            guard !seen.contains(hash) else { continue }
            seen.insert(hash)
            hashes.append(hash)
            if hashes.count >= maxResults {
                break
            }
        }
        return hashes
    }

    private static func addressFromIndexedTopic(_ topic: String) -> String? {
        let normalized = topic.lowercased()
        guard normalized.hasPrefix("0x"), normalized.count >= 42 else { return nil }
        let startIndex = normalized.index(normalized.endIndex, offsetBy: -40)
        return normalizeAddress("0x" + String(normalized[startIndex...]))
    }

    /// Ethereum/EVM engine operation: Paginate transfer snapshots.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func paginateTransferSnapshots(
        _ snapshots: [EthereumTokenTransferSnapshot],
        page: Int,
        pageSize: Int
    ) -> [EthereumTokenTransferSnapshot] {
        let safePage = max(1, page)
        let safePageSize = max(1, pageSize)
        let startIndex = (safePage - 1) * safePageSize
        guard startIndex < snapshots.count else { return [] }
        let endIndex = min(startIndex + safePageSize, snapshots.count)
        return Array(snapshots[startIndex ..< endIndex])
    }

#if DEBUG
    /// Ethereum/EVM engine operation: Paginate transfer snapshots for testing.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    static func paginateTransferSnapshotsForTesting(
        _ snapshots: [EthereumTokenTransferSnapshot],
        page: Int,
        pageSize: Int
    ) -> [EthereumTokenTransferSnapshot] {
        paginateTransferSnapshots(snapshots, page: page, pageSize: pageSize)
    }
#endif

    /// Ethereum/EVM engine operation: Balance of call data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func balanceOfCallData(for address: String) -> String {
        let normalizedAddress = normalizeAddress(address)
        let addressBody = normalizedAddress.dropFirst(2)
        let paddedAddress = String(repeating: "0", count: max(0, 64 - addressBody.count)) + addressBody
        return "0x70a08231\(paddedAddress)"
    }

    /// Ethereum/EVM engine operation: Transfer call data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func transferCallData(
        to address: String,
        amount: Double,
        decimals: Int
    ) throws -> String {
        let normalizedAddress = try validateAddress(address)
        let addressBody = normalizedAddress.dropFirst(2)
        let paddedAddress = String(repeating: "0", count: max(0, 64 - addressBody.count)) + addressBody
        let tokenUnits = scaledUnitDecimal(fromAmount: amount, decimals: decimals)
        let amountHex = hexString(from: tokenUnits)
        let paddedAmount = String(repeating: "0", count: max(0, 64 - amountHex.count)) + amountHex
        return "0xa9059cbb\(paddedAddress)\(paddedAmount)"
    }

    /// Ethereum/EVM engine operation: Transfer call data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func transferCallData(
        to address: String,
        amountUnits: Decimal
    ) throws -> String {
        let normalizedAddress = try validateAddress(address)
        let addressBody = normalizedAddress.dropFirst(2)
        let paddedAddress = String(repeating: "0", count: max(0, 64 - addressBody.count)) + addressBody
        let amountHex = hexString(from: amountUnits)
        let paddedAmount = String(repeating: "0", count: max(0, 64 - amountHex.count)) + amountHex
        return "0xa9059cbb\(paddedAddress)\(paddedAmount)"
    }

    /// Ethereum/EVM engine operation: Decimal power of ten.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }

    /// Ethereum/EVM engine operation: Wei decimal.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func weiDecimal(fromETH amountETH: Double) -> Decimal {
        scaledUnitDecimal(fromAmount: amountETH, decimals: 18)
    }

    /// Ethereum/EVM engine operation: Scaled unit decimal.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func scaledUnitDecimal(fromAmount amount: Double, decimals: Int) -> Decimal {
        let normalizedAmount = max(amount, 0)
        guard normalizedAmount.isFinite else { return 0 }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(max(decimals, 0)))
        let scaled = NSDecimalNumber(value: normalizedAmount).multiplying(by: base)
        return scaled.rounding(accordingToBehavior: nil).decimalValue
    }

    /// Ethereum/EVM engine operation: Gwei.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func gwei(fromWei wei: Decimal) -> Double {
        let gweiValue = wei / decimalPowerOfTen(9)
        return NSDecimalNumber(decimal: gweiValue).doubleValue
    }

    /// Ethereum/EVM engine operation: Eth.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func eth(fromWei wei: Decimal) -> Double {
        let ethValue = wei / decimalPowerOfTen(18)
        return NSDecimalNumber(decimal: ethValue).doubleValue
    }

    /// Ethereum/EVM engine operation: Hex quantity.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func hexQuantity(from decimal: Decimal) -> String {
        "0x" + hexString(from: decimal)
    }

    /// Ethereum/EVM engine operation: Hex string.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func hexString(from decimal: Decimal) -> String {
        guard let uintValue = try? bigUInt(from: decimal) else { return "0" }
        return uintValue == 0 ? "0" : String(uintValue, radix: 16)
    }

    /// Ethereum/EVM engine operation: Whole number string.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func wholeNumberString(from decimal: Decimal) -> String {
        var sourceValue = decimal
        var wholeValue = Decimal()
        NSDecimalRound(&wholeValue, &sourceValue, 0, .down)
        return NSDecimalNumber(decimal: wholeValue).stringValue
    }

    /// Ethereum/EVM engine operation: Big uint.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func bigUInt(from decimal: Decimal) throws -> BigUInt {
        let wholeString = wholeNumberString(from: decimal)
        guard let value = BigUInt(wholeString) else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }
        return value
    }

    /// Ethereum/EVM engine operation: Data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func data(fromHexString hexString: String) throws -> Data {
        let normalized = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard normalized.count.isMultiple(of: 2) else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index ..< nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw EthereumWalletEngineError.invalidHexQuantity
            }
            bytes.append(byte)
            index = nextIndex
        }
        return Data(bytes)
    }

    /// Ethereum/EVM engine operation: Decimal.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func decimal(fromHexQuantity hexQuantity: String) throws -> Decimal {
        let normalizedQuantity = hexQuantity.lowercased()
        guard normalizedQuantity.hasPrefix("0x") else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }
        let body = String(normalizedQuantity.dropFirst(2))
        guard !body.isEmpty else { return .zero }
        guard let value = BigUInt(body, radix: 16),
              let decimalValue = Decimal(string: value.description) else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }
        return decimalValue
    }

    /// Ethereum/EVM engine operation: Sign transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func signTransaction(
        seedPhrase: String,
        toAddress: String,
        valueWei: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        derivationAccount: UInt32,
        chain: EVMChainContext
    ) throws -> Data {
        let walletCoreSigned = try walletCoreSignNativeTransaction(
            seedPhrase: seedPhrase,
            toAddress: toAddress,
            valueWei: valueWei,
            parameters: parameters,
            chainID: chainID,
            derivationAccount: derivationAccount,
            chain: chain
        )
        return walletCoreSigned
    }

    private static func signTransaction(
        privateKeyHex: String,
        toAddress: String,
        valueWei: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        chain: EVMChainContext
    ) throws -> Data {
        try walletCoreSignNativeTransaction(
            privateKeyHex: privateKeyHex,
            toAddress: toAddress,
            valueWei: valueWei,
            parameters: parameters,
            chainID: chainID,
            chain: chain
        )
    }

    /// Ethereum/EVM engine operation: Sign erc20 transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func signERC20Transaction(
        seedPhrase: String,
        tokenContract: String,
        recipientAddress: String,
        amountUnits: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        derivationAccount: UInt32,
        chain: EVMChainContext
    ) throws -> Data {
        let walletCoreSigned = try walletCoreSignERC20Transaction(
            seedPhrase: seedPhrase,
            tokenContract: tokenContract,
            recipientAddress: recipientAddress,
            amountUnits: amountUnits,
            parameters: parameters,
            chainID: chainID,
            derivationAccount: derivationAccount,
            chain: chain
        )
        return walletCoreSigned
    }

    private static func signERC20Transaction(
        privateKeyHex: String,
        tokenContract: String,
        recipientAddress: String,
        amountUnits: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        chain: EVMChainContext
    ) throws -> Data {
        try walletCoreSignERC20Transaction(
            privateKeyHex: privateKeyHex,
            tokenContract: tokenContract,
            recipientAddress: recipientAddress,
            amountUnits: amountUnits,
            parameters: parameters,
            chainID: chainID,
            chain: chain
        )
    }

    /// Ethereum/EVM engine operation: Serialized uint256 data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func serializedUInt256Data(from value: Int) -> Data {
        serializedUInt256Data(from: Decimal(value))
    }

    /// Ethereum/EVM engine operation: Serialized uint256 data.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func serializedUInt256Data(from value: Decimal) -> Data {
        guard let uintValue = try? bigUInt(from: value) else { return Data([0]) }
        let serialized = uintValue.serialize()
        return serialized.isEmpty ? Data([0]) : serialized
    }

    /// Ethereum/EVM engine operation: Wallet core derived address.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func walletCoreDerivedAddress(
        seedPhrase: String,
        account: UInt32,
        chain: EVMChainContext,
        derivationPath: String?
    ) throws -> String {
        let material = try walletCoreMaterial(
            seedPhrase: seedPhrase,
            account: account,
            chain: chain,
            derivationPath: derivationPath
        )
        return normalizeAddress(material.address)
    }

    /// Ethereum/EVM engine operation: Wallet core sign native transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func walletCoreSignNativeTransaction(
        seedPhrase: String,
        toAddress: String,
        valueWei: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        derivationAccount: UInt32,
        chain: EVMChainContext
    ) throws -> Data {
        let material = try walletCoreMaterial(
            seedPhrase: seedPhrase,
            account: derivationAccount,
            chain: chain,
            derivationPath: nil
        )
        return try walletCoreSignNativeTransaction(
            privateKeyData: material.privateKeyData,
            toAddress: toAddress,
            valueWei: valueWei,
            parameters: parameters,
            chainID: chainID
        )
    }

    private static func walletCoreSignNativeTransaction(
        privateKeyHex: String,
        toAddress: String,
        valueWei: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        chain: EVMChainContext
    ) throws -> Data {
        let material = try walletCoreMaterial(privateKeyHex: privateKeyHex, chain: chain)
        return try walletCoreSignNativeTransaction(
            privateKeyData: material.privateKeyData,
            toAddress: toAddress,
            valueWei: valueWei,
            parameters: parameters,
            chainID: chainID
        )
    }

    private static func walletCoreSignNativeTransaction(
        privateKeyData: Data,
        toAddress: String,
        valueWei: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int
    ) throws -> Data {
        var input = EthereumSigningInput()
        input.chainID = serializedUInt256Data(from: chainID)
        input.nonce = serializedUInt256Data(from: parameters.nonce)
        input.txMode = .enveloped
        input.gasLimit = serializedUInt256Data(from: parameters.gasLimit)
        input.maxInclusionFeePerGas = serializedUInt256Data(from: parameters.maxPriorityFeePerGasWei)
        input.maxFeePerGas = serializedUInt256Data(from: parameters.maxFeePerGasWei)
        input.toAddress = toAddress
        input.privateKey = privateKeyData

        var tx = EthereumTransaction()
        var transfer = EthereumTransaction.Transfer()
        transfer.amount = serializedUInt256Data(from: valueWei)
        tx.transfer = transfer
        input.transaction = tx

        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        guard output.errorMessage.isEmpty, !output.encoded.isEmpty else {
            throw EthereumWalletEngineError.rpcFailure(
                output.errorMessage.isEmpty ? "Wallet Core failed to sign Ethereum transaction." : output.errorMessage
            )
        }
        return output.encoded
    }

    /// Ethereum/EVM engine operation: Wallet core sign erc20 transaction.
    /// Ensures predictable behavior for refresh, persistence, and diagnostics flows.
    private static func walletCoreSignERC20Transaction(
        seedPhrase: String,
        tokenContract: String,
        recipientAddress: String,
        amountUnits: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        derivationAccount: UInt32,
        chain: EVMChainContext
    ) throws -> Data {
        let material = try walletCoreMaterial(
            seedPhrase: seedPhrase,
            account: derivationAccount,
            chain: chain,
            derivationPath: nil
        )
        return try walletCoreSignERC20Transaction(
            privateKeyData: material.privateKeyData,
            tokenContract: tokenContract,
            recipientAddress: recipientAddress,
            amountUnits: amountUnits,
            parameters: parameters,
            chainID: chainID
        )
    }

    private static func walletCoreSignERC20Transaction(
        privateKeyHex: String,
        tokenContract: String,
        recipientAddress: String,
        amountUnits: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int,
        chain: EVMChainContext
    ) throws -> Data {
        let material = try walletCoreMaterial(privateKeyHex: privateKeyHex, chain: chain)
        return try walletCoreSignERC20Transaction(
            privateKeyData: material.privateKeyData,
            tokenContract: tokenContract,
            recipientAddress: recipientAddress,
            amountUnits: amountUnits,
            parameters: parameters,
            chainID: chainID
        )
    }

    private static func walletCoreSignERC20Transaction(
        privateKeyData: Data,
        tokenContract: String,
        recipientAddress: String,
        amountUnits: Decimal,
        parameters: EthereumSendParameters,
        chainID: Int
    ) throws -> Data {
        var input = EthereumSigningInput()
        input.chainID = serializedUInt256Data(from: chainID)
        input.nonce = serializedUInt256Data(from: parameters.nonce)
        input.txMode = .enveloped
        input.gasLimit = serializedUInt256Data(from: parameters.gasLimit)
        input.maxInclusionFeePerGas = serializedUInt256Data(from: parameters.maxPriorityFeePerGasWei)
        input.maxFeePerGas = serializedUInt256Data(from: parameters.maxFeePerGasWei)
        input.toAddress = tokenContract
        input.privateKey = privateKeyData

        var tx = EthereumTransaction()
        var transfer = EthereumTransaction.ERC20Transfer()
        transfer.to = recipientAddress
        transfer.amount = serializedUInt256Data(from: amountUnits)
        tx.erc20Transfer = transfer
        input.transaction = tx

        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        guard output.errorMessage.isEmpty, !output.encoded.isEmpty else {
            throw EthereumWalletEngineError.rpcFailure(
                output.errorMessage.isEmpty ? "Wallet Core failed to sign ERC-20 transaction." : output.errorMessage
            )
        }
        return output.encoded
    }

    private static func walletCoreMaterial(
        seedPhrase: String,
        account: UInt32,
        chain: EVMChainContext,
        derivationPath: String?
    ) throws -> WalletCoreDerivationMaterial {
        let resolvedPath = derivationPath ?? chain.derivationPath(account: account)
        return try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .ethereum,
            derivationPath: resolvedPath
        )
    }

    private static func walletCoreMaterial(
        privateKeyHex: String,
        chain _: EVMChainContext
    ) throws -> WalletCoreDerivationMaterial {
        try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .ethereum)
    }
}
