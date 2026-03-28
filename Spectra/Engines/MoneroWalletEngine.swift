// MARK: - File Overview
// Monero engine wrapper for address derivation and transaction workflow integration.
//
// Responsibilities:
// - Encapsulates Monero-specific wallet operations for app-level usage.
// - Bridges chain semantics into shared app transaction state models.

import Foundation

enum MoneroWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case backendNotConfigured
    case backendRejected(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The Monero address is not valid.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("The Monero amount is not valid.", comment: "")
        case .backendNotConfigured:
            return NSLocalizedString("Monero backend is not configured.", comment: "")
        case .backendRejected(let message):
            return NSLocalizedString(message, comment: "")
        case .invalidResponse:
            return NSLocalizedString("The Monero backend response was invalid.", comment: "")
        }
    }
}

struct MoneroSendPreview: Equatable {
    let estimatedNetworkFeeXMR: Double
    let priorityLabel: String
}

struct MoneroSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeXMR: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum MoneroWalletEngine {
    private struct PreviewRequest: Encodable {
        let fromAddress: String
        let toAddress: String
        let amountXMR: Double
    }

    private struct PreviewResponse: Decodable {
        let estimatedFeeXMR: Double
        let priority: String?
    }

    private struct SendRequest: Encodable {
        let fromAddress: String
        let toAddress: String
        let amountXMR: Double
    }

    private struct SendResponse: Decodable {
        let txid: String
        let feeXMR: Double?
    }

    /// Handles "estimateSendPreview" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> MoneroSendPreview {
        let source = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidMoneroAddress(source),
              AddressValidation.isValidMoneroAddress(destination) else {
            throw MoneroWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw MoneroWalletEngineError.invalidAmount
        }
        let candidates = MoneroBalanceService.candidateBackendBaseURLs()
        guard !candidates.isEmpty else {
            throw MoneroWalletEngineError.backendNotConfigured
        }
        var lastError: Error = MoneroWalletEngineError.invalidResponse
        for (index, baseURL) in candidates.enumerated() {
            let endpoint = baseURL.appendingPathComponent("v1/monero/estimate-fee")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = MoneroBalanceService.configuredBackendAPIKey() {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(PreviewRequest(fromAddress: source, toAddress: destination, amountXMR: amount))
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    lastError = MoneroWalletEngineError.backendRejected(message)
                    if index < candidates.count - 1, [404, 405, 429, 500, 501, 502, 503, 504].contains(http.statusCode) {
                        continue
                    }
                    throw lastError
                }
                let decoded = try JSONDecoder().decode(PreviewResponse.self, from: data)
                guard decoded.estimatedFeeXMR.isFinite, decoded.estimatedFeeXMR >= 0 else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                return MoneroSendPreview(
                    estimatedNetworkFeeXMR: decoded.estimatedFeeXMR,
                    priorityLabel: decoded.priority ?? "normal"
                )
            } catch {
                lastError = error
                if index < candidates.count - 1 {
                    continue
                }
            }
        }
        throw lastError
    }

    /// Handles "sendInBackground" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    static func sendInBackground(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async throws -> MoneroSendResult {
        let source = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidMoneroAddress(source),
              AddressValidation.isValidMoneroAddress(destination) else {
            throw MoneroWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw MoneroWalletEngineError.invalidAmount
        }
        let candidates = MoneroBalanceService.candidateBackendBaseURLs()
        guard !candidates.isEmpty else {
            throw MoneroWalletEngineError.backendNotConfigured
        }
        var lastError: Error = MoneroWalletEngineError.invalidResponse
        for (index, baseURL) in candidates.enumerated() {
            let endpoint = baseURL.appendingPathComponent("v1/monero/send")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = MoneroBalanceService.configuredBackendAPIKey() {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(SendRequest(fromAddress: source, toAddress: destination, amountXMR: amount))
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    lastError = MoneroWalletEngineError.backendRejected(message)
                    if index < candidates.count - 1, [404, 405, 429, 500, 501, 502, 503, 504].contains(http.statusCode) {
                        continue
                    }
                    throw lastError
                }
                let decoded = try JSONDecoder().decode(SendResponse.self, from: data)
                let txid = decoded.txid.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !txid.isEmpty else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                return MoneroSendResult(
                    transactionHash: txid,
                    estimatedNetworkFeeXMR: max(0, decoded.feeXMR ?? 0),
                    verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: source, transactionHash: txid)
                )
            } catch {
                lastError = error
                if index < candidates.count - 1 {
                    continue
                }
            }
        }
        throw lastError
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHash.isEmpty else {
            return .deferred
        }
        let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        if let snapshot = result.snapshots.first(where: { $0.transactionHash.lowercased() == normalizedHash }) {
            switch snapshot.status {
            case .failed:
                return .failed("The Monero backend reported the transaction as failed.")
            case .pending, .confirmed:
                return .verified
            }
        }
        if let error = result.diagnostics.error, !error.isEmpty {
            return .failed(error)
        }
        return .deferred
    }
}
