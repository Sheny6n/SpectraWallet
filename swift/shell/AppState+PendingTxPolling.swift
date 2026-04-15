import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshPendingEthereumTransactions() async { await refreshPendingEVMTransactions(chainName: "Ethereum") }
    func refreshPendingArbitrumTransactions() async { await refreshPendingEVMTransactions(chainName: "Arbitrum") }
    func refreshPendingOptimismTransactions() async { await refreshPendingEVMTransactions(chainName: "Optimism") }
    func refreshPendingETCTransactions() async { await refreshPendingEVMTransactions(chainName: "Ethereum Classic") }
    func refreshPendingBNBTransactions() async { await refreshPendingEVMTransactions(chainName: "BNB Chain") }
    func refreshPendingAvalancheTransactions() async { await refreshPendingEVMTransactions(chainName: "Avalanche") }
    func refreshPendingHyperliquidTransactions() async { await refreshPendingEVMTransactions(chainName: "Hyperliquid") }
    func refreshPendingEVMTransactions(chainName: String) async {
        let now = Date()
        guard let chainId = SpectraChainID.id(for: chainName) else { return }
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == chainName
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }
        guard !pendingTransactions.isEmpty else { return }
        var resolvedReceipts: [UUID: (TransactionStatus, EthereumTransactionReceipt)] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                guard let receiptJSON = try await WalletServiceBridge.shared.fetchEVMReceiptJSON(
                    chainId: chainId, txHash: transactionHash
                ) else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                    continue
                }
                guard let classified = classifyEvmReceiptJson(json: receiptJSON) else {
                    throw NSError(domain: "EvmReceipt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid receipt JSON"])
                }
                if classified.isConfirmed {
                    let resolvedStatus: TransactionStatus = classified.isFailed ? .failed : .confirmed
                    let receipt = EthereumTransactionReceipt(
                        transactionHash: transactionHash, blockNumber: classified.blockNumber.map(Int.init), status: classified.isFailed ? "0x0" : "0x1", gasUsed: nil, effectiveGasPriceWei: nil
                    )
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                    resolvedReceipts[transaction.id] = (resolvedStatus, receipt)
                } else { markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now) }
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }}
        let resolvedStatuses = resolvedReceipts.mapValues { resolvedStatus, receipt in
            PendingTransactionStatusResolution(
                status: resolvedStatus, receiptBlockNumber: receipt.blockNumber, confirmations: nil, dogecoinNetworkFeeDoge: nil
            )
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }
}
