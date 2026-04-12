import Foundation
import SwiftUI

@MainActor
extension WalletStore {
    // MARK: - Pending Transaction Polling
    func refreshPendingEthereumTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Ethereum")
    }

    func refreshPendingArbitrumTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Arbitrum")
    }

    func refreshPendingOptimismTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Optimism")
    }

    func refreshPendingETCTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Ethereum Classic")
    }

    func refreshPendingBNBTransactions() async {
        await refreshPendingEVMTransactions(chainName: "BNB Chain")
    }

    func refreshPendingAvalancheTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Avalanche")
    }

    func refreshPendingHyperliquidTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Hyperliquid")
    }

    // Polls pending EVM tx statuses and upgrades local records to confirmed/failed as receipts arrive.
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
                    chainId: chainId,
                    txHash: transactionHash
                ) else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                    continue
                }
                let receipt = try Self.decodeEVMReceipt(json: receiptJSON, txHash: transactionHash)
                if receipt.isConfirmed {
                    let resolvedStatus: TransactionStatus = receipt.isFailed ? .failed : .confirmed
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                    resolvedReceipts[transaction.id] = (resolvedStatus, receipt)
                } else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                }
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }

        let resolvedStatuses = resolvedReceipts.mapValues { resolvedStatus, receipt in
            PendingTransactionStatusResolution(
                status: resolvedStatus,
                receiptBlockNumber: receipt.blockNumber,
                confirmations: nil,
                dogecoinNetworkFeeDOGE: nil
            )
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    // Fetches token transfer history and maps provider records into normalized transaction model.

    // Diagnostics runners:
    // Each chain has history + endpoint probes so users can distinguish
    // "provider reachable" from "provider returning usable chain data".

    // MARK: - Helpers

    private static func decodeEVMReceipt(json: String, txHash: String) throws -> EthereumTransactionReceipt {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "EvmReceipt", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid receipt JSON"])
        }
        let blockNumber = obj["block_number"] as? Int
        let status = obj["status"] as? String
        let gasUsed = (obj["gas_used"] as? String).flatMap { Decimal(string: $0) }
        let effectiveGasPriceWei = (obj["effective_gas_price_wei"] as? String).flatMap { Decimal(string: $0) }
        return EthereumTransactionReceipt(
            transactionHash: txHash,
            blockNumber: blockNumber,
            status: status,
            gasUsed: gasUsed,
            effectiveGasPriceWei: effectiveGasPriceWei
        )
    }
}
