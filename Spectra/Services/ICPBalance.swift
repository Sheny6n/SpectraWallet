import Foundation

enum ICPBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The ICP account identifier is not valid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The ICP Rosetta response was invalid.", comment: "")
        case .httpError(let code):
            let format = NSLocalizedString("The ICP Rosetta endpoint returned HTTP %d.", comment: "")
            return String(format: format, locale: .current, code)
        case .rpcError(let message):
            let format = NSLocalizedString("ICP Rosetta error: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

struct ICPHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct ICPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum ICPBalanceService {
    static let rosettaEndpoints = ChainBackendRegistry.ICPRuntimeEndpoints.rosettaBaseURLs
    private static let endpointReliabilityNamespace = "icp.rosetta"

    private static let networkIdentifier = NetworkIdentifier(
        blockchain: "Internet Computer",
        network: "00000000000000020101"
    )
    private static let e8Divisor = Decimal(string: "100000000")!

    static func endpointCatalog() -> [String] {
        rosettaEndpoints
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        rosettaEndpoints.map { ($0, "\($0)/network/list") }
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidICPAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw ICPBalanceServiceError.invalidAddress
        }

        var lastError: Error?
        for endpoint in rosettaEndpoints {
            do {
                let request = AccountBalanceRequest(
                    networkIdentifier: networkIdentifier,
                    accountIdentifier: AccountIdentifier(address: normalized)
                )
                let response: AccountBalanceResponse = try await post(
                    endpoint: endpoint,
                    path: "/account/balance",
                    requestBody: request
                )
                guard let balanceValue = response.balances.first?.value,
                      let balanceDecimal = Decimal(string: balanceValue) else {
                    throw ICPBalanceServiceError.invalidResponse
                }
                return decimalToDouble(balanceDecimal / e8Divisor)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ICPBalanceServiceError.invalidResponse
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [ICPHistorySnapshot], diagnostics: ICPHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                ICPHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: ICPBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let boundedLimit = max(1, min(limit, 80))
        var lastError: String?
        for endpoint in rosettaEndpoints {
            do {
                let request = SearchTransactionsRequest(
                    networkIdentifier: networkIdentifier,
                    accountIdentifier: AccountIdentifier(address: normalized),
                    transactionIdentifier: nil,
                    limit: boundedLimit
                )
                let response: SearchTransactionsResponse = try await post(
                    endpoint: endpoint,
                    path: "/search/transactions",
                    requestBody: request
                )
                let snapshots = response.transactions.compactMap { snapshot(from: $0, ownerAddress: normalized) }
                return (
                    snapshots,
                    ICPHistoryDiagnostics(
                        address: normalized,
                        sourceUsed: endpoint,
                        transactionCount: snapshots.count,
                        error: nil
                    )
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        return (
            [],
            ICPHistoryDiagnostics(
                address: normalized,
                sourceUsed: rosettaEndpoints.first ?? "none",
                transactionCount: 0,
                error: lastError ?? ICPBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    static func submitSignedTransaction(_ signedTransactionHex: String) async throws -> String {
        let trimmed = signedTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ICPBalanceServiceError.invalidResponse
        }

        var lastError: Error?
        for endpoint in orderedRosettaEndpoints() {
            do {
                let request = ConstructionSubmitRequest(
                    networkIdentifier: networkIdentifier,
                    signedTransaction: trimmed
                )
                let response: ConstructionSubmitResponse = try await post(
                    endpoint: endpoint,
                    path: "/construction/submit",
                    requestBody: request
                )
                guard let hash = response.transactionIdentifier?.hash?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !hash.isEmpty else {
                    throw ICPBalanceServiceError.invalidResponse
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint, success: true)
                return hash
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }

        throw lastError ?? ICPBalanceServiceError.invalidResponse
    }

    static func verifyTransactionIfAvailable(_ transactionHash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else {
            return .deferred
        }

        var lastError: String?
        for endpoint in orderedRosettaEndpoints() {
            do {
                let request = SearchTransactionsRequest(
                    networkIdentifier: networkIdentifier,
                    accountIdentifier: nil,
                    transactionIdentifier: TransactionIdentifier(hash: normalizedHash),
                    limit: 1
                )
                let response: SearchTransactionsResponse = try await post(
                    endpoint: endpoint,
                    path: "/search/transactions",
                    requestBody: request
                )
                if response.transactions.contains(where: {
                    $0.transaction.transactionIdentifier.hash?.caseInsensitiveCompare(normalizedHash) == .orderedSame
                }) {
                    return .verified
                }
            } catch {
                lastError = error.localizedDescription
            }
        }

        if let lastError {
            return .failed(lastError)
        }
        return .deferred
    }

    private static func snapshot(from entry: SearchTransactionEntry, ownerAddress: String) -> ICPHistorySnapshot? {
        let operations = entry.transaction.operations
        let transferOperations = operations.filter {
            $0.type?.caseInsensitiveCompare("TRANSACTION") == .orderedSame
        }
        guard let ownerOperation = transferOperations.first(where: { normalizedAddress($0.account?.address ?? "") == ownerAddress }),
              let valueText = ownerOperation.amount?.value,
              let valueDecimal = Decimal(string: valueText) else {
            return nil
        }

        let transactionHash = entry.transaction.transactionIdentifier.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !transactionHash.isEmpty else { return nil }

        let statusText = ownerOperation.status?.lowercased() ?? ""
        let status: TransactionStatus = statusText.contains("complete") ? .confirmed : .pending
        let kind: TransactionKind = valueDecimal.sign == .minus ? .send : .receive
        let amount = decimalToDouble((valueDecimal.magnitude) / e8Divisor)
        let counterparty = transferOperations.first {
            normalizedAddress($0.account?.address ?? "") != ownerAddress
        }?.account?.address ?? ownerAddress

        let createdAt = entry.transaction.metadata?.timestamp.map {
            Date(timeIntervalSince1970: Double($0) / 1_000_000_000.0)
        } ?? Date()

        return ICPHistorySnapshot(
            transactionHash: transactionHash,
            kind: kind,
            amount: amount,
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: status
        )
    }

    private static func post<RequestBody: Encodable, ResponseBody: Decodable>(
        endpoint: String,
        path: String,
        requestBody: RequestBody
    ) async throws -> ResponseBody {
        guard let url = URL(string: endpoint + path) else {
            throw ICPBalanceServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw ICPBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if let rosettaError = try? JSONDecoder().decode(RosettaErrorResponse.self, from: data),
               let message = rosettaError.details?.errorMessage ?? rosettaError.message {
                throw ICPBalanceServiceError.rpcError(message)
            }
            throw ICPBalanceServiceError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decimalToDouble(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    private static func orderedRosettaEndpoints() -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: rosettaEndpoints
        )
    }

}

private struct NetworkIdentifier: Codable {
    let blockchain: String
    let network: String
}

private struct AccountIdentifier: Codable {
    let address: String
}

private struct CurrencyAmount: Codable {
    let value: String?
}

private struct AccountBalanceRequest: Codable {
    let networkIdentifier: NetworkIdentifier
    let accountIdentifier: AccountIdentifier

    enum CodingKeys: String, CodingKey {
        case networkIdentifier = "network_identifier"
        case accountIdentifier = "account_identifier"
    }
}

private struct AccountBalanceResponse: Codable {
    let balances: [CurrencyAmount]
}

private struct SearchTransactionsRequest: Codable {
    let networkIdentifier: NetworkIdentifier
    let accountIdentifier: AccountIdentifier?
    let transactionIdentifier: TransactionIdentifier?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case networkIdentifier = "network_identifier"
        case accountIdentifier = "account_identifier"
        case transactionIdentifier = "transaction_identifier"
        case limit
    }
}

private struct SearchTransactionsResponse: Codable {
    let transactions: [SearchTransactionEntry]
}

private struct SearchTransactionEntry: Codable {
    let blockIdentifier: BlockIdentifier
    let transaction: RosettaTransaction

    enum CodingKeys: String, CodingKey {
        case blockIdentifier = "block_identifier"
        case transaction
    }
}

private struct BlockIdentifier: Codable {
    let index: Int64?
    let hash: String?
}

private struct RosettaTransaction: Codable {
    let transactionIdentifier: TransactionIdentifier
    let operations: [RosettaOperation]
    let metadata: RosettaTransactionMetadata?

    enum CodingKeys: String, CodingKey {
        case transactionIdentifier = "transaction_identifier"
        case operations
        case metadata
    }
}

private struct TransactionIdentifier: Codable {
    let hash: String?
}

private struct RosettaOperation: Codable {
    let type: String?
    let status: String?
    let account: AccountIdentifier?
    let amount: CurrencyAmount?
}

private struct RosettaTransactionMetadata: Codable {
    let timestamp: Int64?
}

private struct ConstructionSubmitRequest: Codable {
    let networkIdentifier: NetworkIdentifier
    let signedTransaction: String

    enum CodingKeys: String, CodingKey {
        case networkIdentifier = "network_identifier"
        case signedTransaction = "signed_transaction"
    }
}

private struct ConstructionSubmitResponse: Codable {
    let transactionIdentifier: TransactionIdentifier?

    enum CodingKeys: String, CodingKey {
        case transactionIdentifier = "transaction_identifier"
    }
}

private struct RosettaErrorResponse: Codable {
    struct Details: Codable {
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case errorMessage = "error_message"
        }
    }

    let message: String?
    let details: Details?
}
