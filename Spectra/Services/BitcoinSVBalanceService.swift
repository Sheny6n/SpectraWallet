// MARK: - File Overview
// Bitcoin SV balance/history service backed by Blockchair address and transaction APIs.
//
// Responsibilities:
// - Fetches BSV balances, history pages, UTXOs, and transaction status.
// - Normalizes BSV provider responses into app-domain models.

import Foundation

struct BitcoinSVHistorySnapshot: Equatable {
    let txid: String
    let amountBSV: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct BitcoinSVHistoryPage {
    let snapshots: [BitcoinSVHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

struct BitcoinSVTransactionStatus: Equatable {
    let confirmed: Bool
    let blockHeight: Int?
}

struct BitcoinSVUTXO: Equatable {
    let txid: String
    let vout: Int
    let value: UInt64
}

enum BitcoinSVBalanceService {
    private static let blockchairBaseURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.blockchairBaseURL
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let fallbackTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    private static let satoshisPerBSV: Double = 100_000_000

    static func endpointCatalog() -> [String] {
        [blockchairBaseURL]
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        endpointCatalog().map { endpoint in
            (endpoint: endpoint, probeURL: endpoint + "/stats")
        }
    }

    private struct BlockchairAddressResponse: Decodable {
        struct Context: Decodable {
            let code: Int?
        }

        let data: [String: AddressDashboard]
        let context: Context?
    }

    private struct AddressDashboard: Decodable {
        struct AddressDetails: Decodable {
            let balance: Int64?
            let transactionCount: Int?

            enum CodingKeys: String, CodingKey {
                case balance
                case transactionCount = "transaction_count"
            }
        }

        struct UTXOEntry: Decodable {
            let transactionHash: String
            let index: Int
            let value: UInt64

            enum CodingKeys: String, CodingKey {
                case transactionHash = "transaction_hash"
                case index
                case value
            }
        }

        let address: AddressDetails
        let transactions: [String]
        let utxo: [UTXOEntry]?
    }

    private struct BlockchairTransactionResponse: Decodable {
        let data: [String: TransactionDashboard]
    }

    private struct TransactionDashboard: Decodable {
        struct TransactionDetails: Decodable {
            let blockID: Int?
            let hash: String
            let time: String?

            enum CodingKeys: String, CodingKey {
                case blockID = "block_id"
                case hash
                case time
            }
        }

        struct Input: Decodable {
            let recipient: String?
            let value: Int64?
        }

        struct Output: Decodable {
            let recipient: String?
            let value: Int64?
        }

        let transaction: TransactionDetails
        let inputs: [Input]
        let outputs: [Output]
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let dashboard = try await fetchAddressDashboard(for: address, limit: 1, offset: 0)
        let balance = max(0, dashboard.address.balance ?? 0)
        return Double(balance) / satoshisPerBSV
    }

    static func hasTransactionHistory(for address: String) async throws -> Bool {
        let dashboard = try await fetchAddressDashboard(for: address, limit: 1, offset: 0)
        return !(dashboard.transactions.isEmpty) || (dashboard.address.transactionCount ?? 0) > 0
    }

    static func fetchUTXOs(for address: String) async throws -> [BitcoinSVUTXO] {
        let dashboard = try await fetchAddressDashboard(for: address, limit: 100, offset: 0)
        return (dashboard.utxo ?? []).map {
            BitcoinSVUTXO(txid: $0.transactionHash, vout: $0.index, value: $0.value)
        }
    }

    static func fetchTransactionStatus(txid: String) async throws -> BitcoinSVTransactionStatus {
        let transaction = try await fetchTransactionDetails(txid: txid)
        return BitcoinSVTransactionStatus(
            confirmed: transaction.transaction.blockID != nil,
            blockHeight: transaction.transaction.blockID
        )
    }

    static func fetchTransactionPage(
        for address: String,
        limit: Int,
        cursor: String? = nil
    ) async throws -> BitcoinSVHistoryPage {
        let offset = Int(cursor ?? "0") ?? 0
        let dashboard = try await fetchAddressDashboard(for: address, limit: limit, offset: offset)
        let ownAddresses = ownAddressVariants(for: address)
        let txids = Array(dashboard.transactions.prefix(limit))
        var snapshots: [BitcoinSVHistorySnapshot] = []

        for txid in txids {
            let transaction = try await fetchTransactionDetails(txid: txid)
            let snapshot = snapshot(for: transaction, ownAddresses: ownAddresses)
            snapshots.append(snapshot)
        }

        let nextOffset = offset + txids.count
        let hasMore = (dashboard.address.transactionCount ?? 0) > nextOffset
        return BitcoinSVHistoryPage(
            snapshots: snapshots.sorted { $0.createdAt > $1.createdAt },
            nextCursor: hasMore ? String(nextOffset) : nil,
            sourceUsed: "blockchair"
        )
    }

    private static func fetchAddressDashboard(
        for address: String,
        limit: Int,
        offset: Int
    ) async throws -> AddressDashboard {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockchairBaseURL)/dashboards/address/\(encoded)?limit=\(max(1, limit)),\(max(1, limit))&offset=\(max(0, offset)),0") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BlockchairAddressResponse.self, from: data)
        if let dashboard = decoded.data[trimmed] {
            return dashboard
        }
        if let dashboard = decoded.data.values.first {
            return dashboard
        }
        throw URLError(.cannotParseResponse)
    }

    private static func fetchTransactionDetails(txid: String) async throws -> TransactionDashboard {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockchairBaseURL)/dashboards/transaction/\(encoded)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BlockchairTransactionResponse.self, from: data)
        if let transaction = decoded.data[trimmed] {
            return transaction
        }
        if let transaction = decoded.data.values.first {
            return transaction
        }
        throw URLError(.cannotParseResponse)
    }

    private static func snapshot(
        for transaction: TransactionDashboard,
        ownAddresses: Set<String>
    ) -> BitcoinSVHistorySnapshot {
        let outgoingValue = transaction.inputs.reduce(Int64(0)) { partialResult, input in
            guard let recipient = input.recipient?.lowercased(), ownAddresses.contains(recipient) else {
                return partialResult
            }
            return partialResult + max(0, input.value ?? 0)
        }
        let incomingOutputs = transaction.outputs.filter { output in
            guard let recipient = output.recipient?.lowercased() else { return false }
            return ownAddresses.contains(recipient)
        }
        let incomingValue = incomingOutputs.reduce(Int64(0)) { $0 + max(0, $1.value ?? 0) }
        let amount = max(0, incomingValue - outgoingValue)
        let isReceive = incomingValue >= outgoingValue

        let counterparty = if isReceive {
            transaction.inputs.compactMap(\.recipient).first ?? "Unknown"
        } else {
            transaction.outputs.first { output in
                guard let recipient = output.recipient?.lowercased() else { return false }
                return !ownAddresses.contains(recipient)
            }?.recipient ?? "Unknown"
        }

        let createdAt = parseDate(transaction.transaction.time) ?? Date()
        return BitcoinSVHistorySnapshot(
            txid: transaction.transaction.hash,
            amountBSV: Double(abs(amount)) / satoshisPerBSV,
            kind: isReceive ? .receive : .send,
            status: transaction.transaction.blockID == nil ? .pending : .confirmed,
            counterpartyAddress: counterparty,
            blockHeight: transaction.transaction.blockID,
            createdAt: createdAt
        )
    }

    private static func ownAddressVariants(for address: String) -> Set<String> {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return [trimmed, lowered]
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = iso8601Formatter.date(from: value) {
            return date
        }
        return fallbackTimestampFormatter.date(from: value)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        return try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
    }
}
