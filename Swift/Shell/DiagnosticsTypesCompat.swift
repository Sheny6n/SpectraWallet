import Foundation

// UniFFI converts acronym-prefixed Rust struct names into Swift using
// UpperCamelCase (e.g. `XRPHistoryDiagnostics` -> `XrpHistoryDiagnostics`).
// Preserve the historical Swift names via typealiases so existing call
// sites keep compiling.
typealias XRPHistoryDiagnostics = XrpHistoryDiagnostics
typealias TONHistoryDiagnostics = TonHistoryDiagnostics
typealias ICPHistoryDiagnostics = IcpHistoryDiagnostics

// Phase A compatibility shims for diagnostic record types that are now
// owned by the Rust core (see `core/src/diagnostics/types.rs`). UniFFI
// generates these types with camelCase field names derived mechanically
// from Rust snake_case (e.g. `wallet_id` -> `walletId`, `trc20` ->
// `trc20`) and `Int32` counts. Swift call sites historically use
// `walletID`, `tronScanTRC20Count`, and plain `Int`; these extensions
// bridge the naming / integer-width gap so the ~213 existing call
// sites keep compiling byte-unchanged. Remove these shims once call
// sites are migrated off the legacy names.

// MARK: - BitcoinHistoryDiagnostics

extension BitcoinHistoryDiagnostics {
    init(walletID: String, identifier: String, sourceUsed: String, transactionCount: Int, nextCursor: String?, error: String?) {
        self.init(walletId: walletID, identifier: identifier, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), nextCursor: nextCursor, error: error)
    }
    var walletID: String { get { walletId } set { walletId = newValue } }
}

// MARK: - EthereumTokenTransferHistoryDiagnostics

extension EthereumTokenTransferHistoryDiagnostics {
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
        self.init(
            address: address,
            rpcTransferCount: Int32(rpcTransferCount),
            rpcError: rpcError,
            blockscoutTransferCount: Int32(blockscoutTransferCount),
            blockscoutError: blockscoutError,
            etherscanTransferCount: Int32(etherscanTransferCount),
            etherscanError: etherscanError,
            ethplorerTransferCount: Int32(ethplorerTransferCount),
            ethplorerError: ethplorerError,
            sourceUsed: sourceUsed,
            transferScanCount: Int32(transferScanCount),
            decodedTransferCount: Int32(decodedTransferCount),
            unsupportedTransferDropCount: Int32(unsupportedTransferDropCount),
            decodingCompletenessRatio: decodingCompletenessRatio
        )
    }
}

// MARK: - TronHistoryDiagnostics

extension TronHistoryDiagnostics {
    init(address: String, tronScanTxCount: Int, tronScanTRC20Count: Int, sourceUsed: String, error: String?) {
        self.init(address: address, tronScanTxCount: Int32(tronScanTxCount), tronScanTrc20Count: Int32(tronScanTRC20Count), sourceUsed: sourceUsed, error: error)
    }
    var tronScanTRC20Count: Int32 { get { tronScanTrc20Count } set { tronScanTrc20Count = newValue } }
}

// MARK: - SolanaHistoryDiagnostics

extension SolanaHistoryDiagnostics {
    init(address: String, rpcCount: Int, sourceUsed: String, error: String?) {
        self.init(address: address, rpcCount: Int32(rpcCount), sourceUsed: sourceUsed, error: error)
    }
}

// MARK: - Simple address/source/count/error shape (10 chains)

extension XRPHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension StellarHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension MoneroHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension SuiHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension AptosHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension TONHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension ICPHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension NearHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension PolkadotHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}

extension CardanoHistoryDiagnostics {
    init(address: String, sourceUsed: String, transactionCount: Int, error: String?) {
        self.init(address: address, sourceUsed: sourceUsed, transactionCount: Int32(transactionCount), error: error)
    }
}
