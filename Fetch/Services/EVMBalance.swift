import Foundation
struct EthereumCustomFeeConfiguration: Equatable {
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
}
struct EthereumTransactionReceipt: Equatable {
    let transactionHash: String
    let blockNumber: Int? let status: String? let gasUsed: Decimal? let effectiveGasPriceWei: Decimal? var isConfirmed: Bool { blockNumber != nil }
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
    let rpcError: String? let blockscoutTransferCount: Int
    let blockscoutError: String? let etherscanTransferCount: Int
    let etherscanError: String? let ethplorerTransferCount: Int
    let ethplorerError: String? let sourceUsed: String
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
