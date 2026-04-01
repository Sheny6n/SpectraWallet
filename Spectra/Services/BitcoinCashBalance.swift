import Foundation

struct BitcoinCashHistorySnapshot: Equatable {
    let txid: String
    let amountBCH: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct BitcoinCashHistoryPage {
    let snapshots: [BitcoinCashHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

struct BitcoinCashTransactionStatus: Equatable {
    let confirmed: Bool
    let blockHeight: Int?
}

struct BitcoinCashUTXO: Equatable {
    let txid: String
    let vout: Int
    let value: UInt64
}

enum BitcoinCashBalanceService {
    private enum Provider: String, CaseIterable {
        case blockchair
        case actorforth
    }

    private static let blockchairBaseURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairBaseURL
    private static let actorforthBaseURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.actorforthBaseURL
    private static let blockchairTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    private static let satoshisPerBCH: Double = 100_000_000

    static func endpointCatalog() -> [String] {
        [
            blockchairBaseURL,
            actorforthBaseURL,
        ]
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        [
            (endpoint: blockchairBaseURL, probeURL: blockchairBaseURL + "/stats"),
            (endpoint: actorforthBaseURL, probeURL: actorforthBaseURL + "/blockchain/getBlockchainInfo"),
        ]
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

    private struct ActorForthEnvelope<Payload: Decodable>: Decodable {
        let status: String?
        let message: String?
        let data: Payload?
    }

    private struct ActorForthAddressDetails: Decodable {
        let balanceSat: Int64?
        let txApperances: Int?
        let transactions: [String]?

        enum CodingKeys: String, CodingKey {
            case balanceSat
            case txApperances
            case transactions
        }
    }

    private struct ActorForthUTXOPayload: Decodable {
        struct Entry: Decodable {
            let txid: String?
            let vout: Int?
            let satoshis: UInt64?
        }

        let utxos: [Entry]?
    }

    private struct ActorForthTransactionPayload: Decodable {
        struct Input: Decodable {
            let legacyAddress: String?
            let cashAddress: String?
            let valueSat: Int64?

            enum CodingKeys: String, CodingKey {
                case legacyAddress
                case cashAddress
                case valueSat
            }
        }

        struct Output: Decodable {
            let legacyAddress: String?
            let cashAddress: String?
            let value: String?
            let valueSat: Int64?

            enum CodingKeys: String, CodingKey {
                case legacyAddress
                case cashAddress
                case value
                case valueSat
            }
        }

        let txid: String?
        let confirmations: Int?
        let blockheight: Int?
        let time: TimeInterval?
        let vin: [Input]?
        let vout: [Output]?
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(candidates: Provider.allCases) { provider in
            switch provider {
            case .blockchair:
                let dashboard = try await fetchBlockchairAddressDashboard(for: trimmed, limit: 1, offset: 0)
                let balance = max(0, dashboard.address.balance ?? 0)
                return Double(balance) / satoshisPerBCH
            case .actorforth:
                let details = try await fetchActorForthAddressDetails(for: trimmed)
                let balance = max(0, details.balanceSat ?? 0)
                return Double(balance) / satoshisPerBCH
            }
        }
    }

    static func hasTransactionHistory(for address: String) async throws -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(candidates: Provider.allCases) { provider in
            switch provider {
            case .blockchair:
                let dashboard = try await fetchBlockchairAddressDashboard(for: trimmed, limit: 1, offset: 0)
                return !(dashboard.transactions.isEmpty) || (dashboard.address.transactionCount ?? 0) > 0
            case .actorforth:
                let details = try await fetchActorForthAddressDetails(for: trimmed)
                return !(details.transactions ?? []).isEmpty || (details.txApperances ?? 0) > 0
            }
        }
    }

    static func fetchUTXOs(for address: String) async throws -> [BitcoinCashUTXO] {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        let blockchairUTXOs = try? await fetchBlockchairUTXOs(for: trimmed)
        let actorforthUTXOs = try? await fetchActorForthResolvedUTXOs(for: trimmed)

        switch (blockchairUTXOs, actorforthUTXOs) {
        case let (.some(blockchair), .some(actorforth)):
            return try mergeConsistentUTXOs(
                blockchairUTXOs: blockchair,
                actorforthUTXOs: actorforth
            )
        case let (.some(blockchair), .none):
            return blockchair
        case let (.none, .some(actorforth)):
            return actorforth
        case (.none, .none):
            throw URLError(.cannotLoadFromNetwork)
        }
    }

    static func fetchTransactionStatus(txid: String) async throws -> BitcoinCashTransactionStatus {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(candidates: Provider.allCases) { provider in
            switch provider {
            case .blockchair:
                let transaction = try await fetchBlockchairTransactionDetails(txid: trimmed)
                return BitcoinCashTransactionStatus(
                    confirmed: transaction.transaction.blockID != nil,
                    blockHeight: transaction.transaction.blockID
                )
            case .actorforth:
                let transaction = try await fetchActorForthTransactionDetails(txid: trimmed)
                let confirmations = max(0, transaction.confirmations ?? 0)
                return BitcoinCashTransactionStatus(
                    confirmed: confirmations > 0 || transaction.blockheight != nil,
                    blockHeight: transaction.blockheight
                )
            }
        }
    }

    static func fetchTransactionPage(
        for address: String,
        limit: Int,
        cursor: String? = nil
    ) async throws -> BitcoinCashHistoryPage {
        let offset = Int(cursor ?? "0") ?? 0
        let dashboard = try await fetchBlockchairAddressDashboard(for: address, limit: limit, offset: offset)
        let ownAddresses = ownAddressVariants(for: address)
        let txids = Array(dashboard.transactions.prefix(limit))
        var snapshots: [BitcoinCashHistorySnapshot] = []

        for txid in txids {
            let transaction = try await fetchBlockchairTransactionDetails(txid: txid)
            let snapshot = snapshot(for: transaction, ownAddresses: ownAddresses)
            snapshots.append(snapshot)
        }

        let nextOffset = offset + txids.count
        let hasMore = (dashboard.address.transactionCount ?? 0) > nextOffset
        return BitcoinCashHistoryPage(
            snapshots: snapshots.sorted { $0.createdAt > $1.createdAt },
            nextCursor: hasMore ? String(nextOffset) : nil,
            sourceUsed: "blockchair"
        )
    }

    private static func fetchBlockchairAddressDashboard(
        for address: String,
        limit: Int,
        offset: Int
    ) async throws -> AddressDashboard {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockchairBaseURL)/dashboards/address/\(encoded)?limit=\(max(1, limit)),\(max(1, limit))&offset=\(max(0, offset)),0") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BlockchairAddressResponse.self, from: data)
        if let dashboard = decoded.data[address] {
            return dashboard
        }
        if let dashboard = decoded.data.values.first {
            return dashboard
        }
        throw URLError(.cannotParseResponse)
    }

    private static func fetchBlockchairTransactionDetails(txid: String) async throws -> TransactionDashboard {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockchairBaseURL)/dashboards/transaction/\(encoded)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BlockchairTransactionResponse.self, from: data)
        if let transaction = decoded.data[txid] {
            return transaction
        }
        if let transaction = decoded.data.values.first {
            return transaction
        }
        throw URLError(.cannotParseResponse)
    }

    private static func fetchActorForthAddressDetails(for address: String) async throws -> ActorForthAddressDetails {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(actorforthBaseURL)/address/details/\(encoded)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(ActorForthEnvelope<ActorForthAddressDetails>.self, from: data)
        guard let payload = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return payload
    }

    private static func fetchActorForthUTXOs(for address: String) async throws -> ActorForthUTXOPayload {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(actorforthBaseURL)/address/utxo/\(encoded)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(ActorForthEnvelope<ActorForthUTXOPayload>.self, from: data)
        guard let payload = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return payload
    }

    private static func fetchActorForthTransactionDetails(txid: String) async throws -> ActorForthTransactionPayload {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(actorforthBaseURL)/transaction/details/\(encoded)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(ActorForthEnvelope<ActorForthTransactionPayload>.self, from: data)
        guard let payload = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return payload
    }

    private static func fetchBlockchairUTXOs(for address: String) async throws -> [BitcoinCashUTXO] {
        let dashboard = try await fetchBlockchairAddressDashboard(for: address, limit: 100, offset: 0)
        return sanitizeUTXOs((dashboard.utxo ?? []).map {
            BitcoinCashUTXO(txid: $0.transactionHash, vout: $0.index, value: $0.value)
        })
    }

    private static func fetchActorForthResolvedUTXOs(for address: String) async throws -> [BitcoinCashUTXO] {
        let payload = try await fetchActorForthUTXOs(for: address)
        return sanitizeUTXOs((payload.utxos ?? []).compactMap { entry in
            guard let txid = entry.txid,
                  let vout = entry.vout,
                  let satoshis = entry.satoshis else {
                return nil
            }
            return BitcoinCashUTXO(txid: txid, vout: vout, value: satoshis)
        })
    }

    nonisolated private static func sanitizeUTXOs(_ utxos: [BitcoinCashUTXO]) -> [BitcoinCashUTXO] {
        var deduplicated: [String: BitcoinCashUTXO] = [:]
        for utxo in utxos where !utxo.txid.isEmpty && utxo.vout >= 0 && utxo.value > 0 {
            let key = outpointKey(hash: utxo.txid, index: utxo.vout)
            if let existing = deduplicated[key] {
                guard existing.value == utxo.value else {
                    continue
                }
            }
            deduplicated[key] = utxo
        }
        return deduplicated.values.sorted {
            if $0.value == $1.value {
                return outpointKey(hash: $0.txid, index: $0.vout) < outpointKey(hash: $1.txid, index: $1.vout)
            }
            return $0.value > $1.value
        }
    }

    nonisolated private static func mergeConsistentUTXOs(
        blockchairUTXOs: [BitcoinCashUTXO],
        actorforthUTXOs: [BitcoinCashUTXO]
    ) throws -> [BitcoinCashUTXO] {
        guard !blockchairUTXOs.isEmpty else { return actorforthUTXOs }
        guard !actorforthUTXOs.isEmpty else { return blockchairUTXOs }

        let blockchairByOutpoint = Dictionary(uniqueKeysWithValues: blockchairUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let actorforthByOutpoint = Dictionary(uniqueKeysWithValues: actorforthUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let overlappingKeys = Set(blockchairByOutpoint.keys).intersection(actorforthByOutpoint.keys)

        guard !overlappingKeys.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        for key in overlappingKeys {
            guard blockchairByOutpoint[key]?.value == actorforthByOutpoint[key]?.value else {
                throw URLError(.cannotParseResponse)
            }
        }

        var merged = blockchairByOutpoint
        for (key, utxo) in actorforthByOutpoint where merged.index(forKey: key) == nil {
            merged[key] = utxo
        }
        return merged.values.sorted {
            if $0.value == $1.value {
                return outpointKey(hash: $0.txid, index: $0.vout) < outpointKey(hash: $1.txid, index: $1.vout)
            }
            return $0.value > $1.value
        }
    }

    nonisolated private static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
    }

    private static func runWithProviderFallback<T>(
        candidates: [Provider],
        operation: @escaping (Provider) async throws -> T
    ) async throws -> T {
        var firstError: Error?
        var lastError: Error?
        for provider in candidates {
            do {
                return try await operation(provider)
            } catch {
                if firstError == nil {
                    firstError = error
                }
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw firstError ?? lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private static func snapshot(
        for transaction: TransactionDashboard,
        ownAddresses: Set<String>
    ) -> BitcoinCashHistorySnapshot {
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
        return BitcoinCashHistorySnapshot(
            txid: transaction.transaction.hash,
            amountBCH: Double(abs(amount)) / satoshisPerBCH,
            kind: isReceive ? .receive : .send,
            status: transaction.transaction.blockID == nil ? .pending : .confirmed,
            counterpartyAddress: counterparty,
            blockHeight: transaction.transaction.blockID,
            createdAt: createdAt
        )
    }

    private static func ownAddressVariants(for address: String) -> Set<String> {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var variants: Set<String> = [trimmed]
        if trimmed.hasPrefix("bitcoincash:") {
            variants.insert(String(trimmed.dropFirst("bitcoincash:".count)))
        } else {
            variants.insert("bitcoincash:\(trimmed)")
        }
        return variants
    }

    private static func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        return blockchairTimestampFormatter.date(from: rawValue)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
    }
}
