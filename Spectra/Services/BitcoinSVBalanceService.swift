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
    private static let whatsonchainBaseURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainBaseURL
    private static let whatsonchainChainInfoURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainChainInfoURL
    private static let satoshisPerBSV: Double = 100_000_000

    static func endpointCatalog() -> [String] {
        [whatsonchainBaseURL]
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        endpointCatalog().map { endpoint in
            (endpoint: endpoint, probeURL: whatsonchainChainInfoURL)
        }
    }

    private struct WhatsOnChainBalanceResponse: Decodable {
        let confirmed: Int64?
        let unconfirmed: Int64?
    }

    private struct WhatsOnChainHistoryEntry: Decodable {
        let txHash: String
        let height: Int?

        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
            case height
        }
    }

    private struct WhatsOnChainUnspentEntry: Decodable {
        let txHash: String
        let outputIndex: Int
        let value: UInt64

        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
            case outputIndex = "tx_pos"
            case value
        }
    }

    private struct WhatsOnChainTransaction: Decodable {
        struct Input: Decodable {
            struct ScriptSignature: Decodable {
                let asm: String?
                let hex: String?
            }

            let txid: String?
            let vout: Int?
            let scriptSig: ScriptSignature?
            let sequence: UInt64?
            let address: String?
            let value: Double?
        }

        struct Output: Decodable {
            struct ScriptPubKey: Decodable {
                let addresses: [String]?
                let address: String?
            }

            let value: Double?
            let n: Int?
            let scriptPubKey: ScriptPubKey?
        }

        let txid: String
        let confirmations: Int?
        let blockheight: Int?
        let time: TimeInterval?
        let blocktime: TimeInterval?
        let vin: [Input]
        let vout: [Output]
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let trimmed = try normalizedAddress(address)
        let balance: WhatsOnChainBalanceResponse = try await fetchDecodable(
            path: "/address/\(trimmed)/balance"
        )
        let confirmed = max(0, balance.confirmed ?? 0)
        let unconfirmed = max(0, balance.unconfirmed ?? 0)
        return Double(confirmed + unconfirmed) / satoshisPerBSV
    }

    static func hasTransactionHistory(for address: String) async throws -> Bool {
        let trimmed = try normalizedAddress(address)
        let confirmed: [WhatsOnChainHistoryEntry] = try await fetchDecodable(
            path: "/address/\(trimmed)/confirmed/history"
        )
        if !confirmed.isEmpty {
            return true
        }
        let unconfirmed: [WhatsOnChainHistoryEntry] = try await fetchDecodable(
            path: "/address/\(trimmed)/unconfirmed/history"
        )
        return !unconfirmed.isEmpty
    }

    static func fetchUTXOs(for address: String) async throws -> [BitcoinSVUTXO] {
        let trimmed = try normalizedAddress(address)
        let utxos: [WhatsOnChainUnspentEntry] = try await fetchDecodable(
            path: "/address/\(trimmed)/confirmed/unspent"
        )
        return utxos.map {
            BitcoinSVUTXO(txid: $0.txHash, vout: $0.outputIndex, value: $0.value)
        }
    }

    static func fetchTransactionStatus(txid: String) async throws -> BitcoinSVTransactionStatus {
        let transaction = try await fetchTransactionDetails(txid: txid)
        let confirmations = max(0, transaction.confirmations ?? 0)
        return BitcoinSVTransactionStatus(
            confirmed: confirmations > 0 || transaction.blockheight != nil,
            blockHeight: transaction.blockheight
        )
    }

    static func fetchTransactionPage(
        for address: String,
        limit: Int,
        cursor: String? = nil
    ) async throws -> BitcoinSVHistoryPage {
        let trimmed = try normalizedAddress(address)
        let normalizedLimit = max(1, limit)
        let ownAddresses = ownAddressVariants(for: trimmed)

        let unconfirmedEntries: [WhatsOnChainHistoryEntry]
        let confirmedEntries: [WhatsOnChainHistoryEntry]
        let nextCursor: String?

        if let cursor, !cursor.isEmpty {
            let token = cursor.replacingOccurrences(of: "confirmed:", with: "")
            confirmedEntries = try await fetchHistoryPage(
                path: "/address/\(trimmed)/confirmed/history",
                limit: normalizedLimit,
                cursor: token.isEmpty ? nil : token
            )
            unconfirmedEntries = []
            nextCursor = confirmedEntries.count == normalizedLimit
                ? "confirmed:\(tokenForLastHistoryEntry(confirmedEntries.last))"
                : nil
        } else {
            unconfirmedEntries = try await fetchHistoryPage(
                path: "/address/\(trimmed)/unconfirmed/history",
                limit: normalizedLimit,
                cursor: nil
            )
            let remainingLimit = max(0, normalizedLimit - unconfirmedEntries.count)
            if remainingLimit > 0 {
                confirmedEntries = try await fetchHistoryPage(
                    path: "/address/\(trimmed)/confirmed/history",
                    limit: remainingLimit,
                    cursor: nil
                )
            } else {
                confirmedEntries = []
            }
            nextCursor = confirmedEntries.count == remainingLimit && remainingLimit > 0
                ? "confirmed:\(tokenForLastHistoryEntry(confirmedEntries.last))"
                : nil
        }

        let txids = Array(Set((unconfirmedEntries + confirmedEntries).map(\.txHash)))
        var snapshots: [BitcoinSVHistorySnapshot] = []
        for txid in txids {
            let transaction = try await fetchTransactionDetails(txid: txid)
            snapshots.append(snapshot(for: transaction, ownAddresses: ownAddresses))
        }

        return BitcoinSVHistoryPage(
            snapshots: snapshots.sorted { $0.createdAt > $1.createdAt },
            nextCursor: nextCursor,
            sourceUsed: "whatsonchain"
        )
    }

    private static func fetchHistoryPage(
        path: String,
        limit: Int,
        cursor: String?
    ) async throws -> [WhatsOnChainHistoryEntry] {
        var queryItems = [URLQueryItem(name: "limit", value: String(max(1, limit)))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "start", value: cursor))
        }
        return try await fetchDecodable(path: path, queryItems: queryItems)
    }

    private static func fetchTransactionDetails(txid: String) async throws -> WhatsOnChainTransaction {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await fetchDecodable(path: "/tx/hash/\(trimmed)")
    }

    private static func snapshot(
        for transaction: WhatsOnChainTransaction,
        ownAddresses: Set<String>
    ) -> BitcoinSVHistorySnapshot {
        let outgoingValue = transaction.vin.reduce(0.0) { partialResult, input in
            guard let address = input.address?.lowercased(), ownAddresses.contains(address) else {
                return partialResult
            }
            return partialResult + max(0, input.value ?? 0)
        }
        let incomingOutputs = transaction.vout.filter { output in
            let outputAddresses = resolvedAddresses(for: output)
            return outputAddresses.contains { ownAddresses.contains($0.lowercased()) }
        }
        let incomingValue = incomingOutputs.reduce(0.0) { $0 + max(0, $1.value ?? 0) }
        let netAmount = incomingValue - outgoingValue
        let isReceive = netAmount >= 0

        let counterparty = if isReceive {
            transaction.vin.compactMap(\.address).first ?? "Unknown"
        } else {
            transaction.vout.first { output in
                let outputAddresses = resolvedAddresses(for: output)
                return outputAddresses.contains { !ownAddresses.contains($0.lowercased()) }
            }
            .flatMap { resolvedAddresses(for: $0).first } ?? "Unknown"
        }

        let timestamp = transaction.blocktime ?? transaction.time
        let createdAt = timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date()
        let confirmations = max(0, transaction.confirmations ?? 0)

        return BitcoinSVHistorySnapshot(
            txid: transaction.txid,
            amountBSV: abs(netAmount),
            kind: isReceive ? .receive : .send,
            status: confirmations > 0 || transaction.blockheight != nil ? .confirmed : .pending,
            counterpartyAddress: counterparty,
            blockHeight: transaction.blockheight,
            createdAt: createdAt
        )
    }

    private static func resolvedAddresses(for output: WhatsOnChainTransaction.Output) -> [String] {
        if let addresses = output.scriptPubKey?.addresses, !addresses.isEmpty {
            return addresses
        }
        if let address = output.scriptPubKey?.address, !address.isEmpty {
            return [address]
        }
        return []
    }

    private static func tokenForLastHistoryEntry(_ entry: WhatsOnChainHistoryEntry?) -> String {
        guard let entry else { return "" }
        let height = entry.height.map(String.init) ?? ""
        return height.isEmpty ? entry.txHash : "\(height):\(entry.txHash)"
    }

    private static func normalizedAddress(_ address: String) throws -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return encoded
    }

    private static func ownAddressVariants(for address: String) -> Set<String> {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return [trimmed, lowered]
    }

    private static func fetchDecodable<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard var components = URLComponents(string: whatsonchainBaseURL + path) else {
            throw URLError(.badURL)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
    }
}
