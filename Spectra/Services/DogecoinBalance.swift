import Foundation
import CryptoKit

struct DogecoinTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int?
    let networkFeeDOGE: Double?
    let confirmations: Int?
}

private struct DogecoinAddressPayload: Decodable {
    let confirmedBalance: String?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case confirmedBalance = "confirmed_balance"
        case balance
    }
}

private struct DogecoinAddressDashboardResponse: Decodable {
    let data: [String: DogecoinAddressDashboardEntry]
}

private struct DogecoinAddressDashboardEntry: Decodable {
    let transactions: [String]
}

private struct DogecoinTransactionDashboardResponse: Decodable {
    let data: [String: DogecoinTransactionDashboardEntry]
}

private struct BlockCypherDogecoinAddressResponse: Decodable {
    struct TransactionReference: Decodable {
        let txHash: String

        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
        }
    }

    let txrefs: [TransactionReference]?
    let unconfirmedTxrefs: [TransactionReference]?

    enum CodingKeys: String, CodingKey {
        case txrefs
        case unconfirmedTxrefs = "unconfirmed_txrefs"
    }
}

private struct BlockCypherDogecoinTransactionResponse: Decodable {
    struct Input: Decodable {
        let addresses: [String]?
        let outputValue: Int64?
        let value: Int64?

        enum CodingKeys: String, CodingKey {
            case addresses
            case outputValue = "output_value"
            case value
        }
    }

    struct Output: Decodable {
        let addresses: [String]?
        let value: Int64?
    }

    let hash: String?
    let received: String?
    let blockHeight: Int?
    let confirmations: Int?
    let inputs: [Input]?
    let outputs: [Output]?

    enum CodingKeys: String, CodingKey {
        case hash
        case received
        case blockHeight = "block_height"
        case confirmations
        case inputs
        case outputs
    }
}

private struct BlockCypherDogecoinNetworkResponse: Decodable {
    let height: Int?
}

private struct BlockCypherDogecoinBalanceResponse: Decodable {
    let finalBalance: Int64?
    let balance: Int64?

    enum CodingKeys: String, CodingKey {
        case finalBalance = "final_balance"
        case balance
    }
}

private struct DogecoinTransactionDashboardEntry: Decodable {
    let transaction: DogecoinDashboardTransaction
    let inputs: [DogecoinDashboardTransfer]
    let outputs: [DogecoinDashboardTransfer]
}

private struct DogecoinDashboardTransaction: Decodable {
    let hash: String?
    let time: String?
    let blockID: Int?

    enum CodingKeys: String, CodingKey {
        case hash
        case time
        case blockID = "block_id"
    }
}

private struct DogecoinDashboardTransfer: Decodable {
    let recipient: String?
    let value: Int64?
}

enum DogecoinBalanceService {
    private static let blockchairTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private enum ProviderEndpoint: String, CaseIterable {
        case blockchair
        case blockcypher
        case dogechain
    }

    struct AddressTransactionSnapshot {
        let hash: String
        let kind: TransactionKind
        let status: TransactionStatus
        let amount: Double
        let counterpartyAddress: String
        let createdAt: Date
        let blockNumber: Int?
    }

    struct DogecoinHistoryPage {
        let snapshots: [AddressTransactionSnapshot]
        let nextCursor: String?
        let sourceUsed: String
    }

    static func isValidDogecoinAddress(_ address: String) -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (25 ... 40).contains(trimmedAddress.count) else {
            return false
        }

        guard let decoded = base58Decode(trimmedAddress), decoded.count == 25 else {
            return false
        }

        let payload = decoded.prefix(21)
        let checksum = decoded.suffix(4)
        let computedChecksum = doubleSHA256(payload).prefix(4)
        guard checksum.elementsEqual(computedChecksum) else {
            return false
        }

        guard let version = payload.first else { return false }
        return version == 0x1e || version == 0x16
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDogecoinAddress(trimmedAddress) else {
            throw URLError(.badURL)
        }

        return try await runWithProviderFallback(candidates: [.dogechain, .blockcypher]) { provider in
            switch provider {
            case .dogechain:
                return try await fetchBalanceViaDogechain(for: trimmedAddress)
            case .blockcypher:
                return try await fetchBalanceViaBlockcypher(for: trimmedAddress)
            case .blockchair:
                throw URLError(.cannotLoadFromNetwork)
            }
        }
    }

    private static func fetchBalanceViaDogechain(for address: String) async throws -> Double {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = dogechainURL(path: "/address/balance/\(encodedAddress)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(DogecoinAddressPayload.self, from: data)
        let balanceText = payload.confirmedBalance ?? payload.balance ?? "0"
        guard let balance = Double(balanceText) else {
            throw URLError(.cannotParseResponse)
        }
        return max(0, balance)
    }

    private static func fetchBalanceViaBlockcypher(for address: String) async throws -> Double {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/addrs/\(encodedAddress)/balance") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(BlockCypherDogecoinBalanceResponse.self, from: data)
        let balanceKoinu = max(0, payload.finalBalance ?? payload.balance ?? 0)
        return Double(balanceKoinu) / 100_000_000
    }

    static func fetchRecentTransactions(for address: String, limit: Int = 15) async throws -> [AddressTransactionSnapshot] {
        try await fetchTransactionPage(for: address, limit: limit, cursor: nil).snapshots
    }

    static func fetchTransactionPage(for address: String, limit: Int = 15, cursor: String? = nil) async throws -> DogecoinHistoryPage {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDogecoinAddress(trimmedAddress) else {
            throw URLError(.badURL)
        }

        let clampedLimit = max(1, min(limit, 200))
        let offset = max(0, Int(cursor ?? "") ?? 0)
        var providerSnapshots: [[AddressTransactionSnapshot]] = []
        var lastError: Error?

        for provider in orderedProviders([.blockchair, .blockcypher]) {
            do {
                let snapshots: [AddressTransactionSnapshot]
                switch provider {
                case .blockchair:
                    snapshots = try await fetchRecentTransactionsViaBlockchair(for: trimmedAddress, limit: clampedLimit)
                case .blockcypher:
                    snapshots = try await fetchRecentTransactionsViaBlockcypher(for: trimmedAddress, limit: clampedLimit)
                case .dogechain:
                    continue
                }
                providerSnapshots.append(snapshots)
            } catch {
                lastError = error
            }
        }

        guard !providerSnapshots.isEmpty else {
            if let lastError {
                throw lastError
            }
            throw URLError(.cannotLoadFromNetwork)
        }

        let reconciled = reconcileTransactionSnapshots(providerSnapshots)
            .sorted { $0.createdAt > $1.createdAt }
        if offset >= reconciled.count {
            return DogecoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "dogecoin.providers")
        }
        let paged = Array(reconciled.dropFirst(offset).prefix(clampedLimit))
        let nextCursor = (offset + clampedLimit) < reconciled.count ? String(offset + clampedLimit) : nil
        return DogecoinHistoryPage(snapshots: paged, nextCursor: nextCursor, sourceUsed: "dogecoin.providers")
    }

    private static func fetchRecentTransactionsViaBlockchair(for address: String, limit: Int) async throws -> [AddressTransactionSnapshot] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }

        guard let baseURL = blockchairURL(path: "/dashboards/address/\(encodedAddress)") else {
            throw URLError(.badURL)
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let addressURL = components?.url else {
            throw URLError(.badURL)
        }

        let (addressData, addressResponse) = try await fetchData(from: addressURL)
        guard let addressHTTPResponse = addressResponse as? HTTPURLResponse, (200 ..< 300).contains(addressHTTPResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let addressPayload = try JSONDecoder().decode(DogecoinAddressDashboardResponse.self, from: addressData)
        guard let addressEntry = addressPayload.data.values.first else {
            return []
        }

        let transactionHashes = Array(addressEntry.transactions.prefix(limit))
        guard !transactionHashes.isEmpty else {
            return []
        }

        let hashList = transactionHashes.joined(separator: ",")
        guard let encodedHashList = hashList.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let transactionsURL = blockchairURL(path: "/dashboards/transactions/\(encodedHashList)") else {
            throw URLError(.badURL)
        }

        let (transactionsData, transactionsResponse) = try await fetchData(from: transactionsURL)
        guard let transactionsHTTPResponse = transactionsResponse as? HTTPURLResponse, (200 ..< 300).contains(transactionsHTTPResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let transactionPayload = try JSONDecoder().decode(DogecoinTransactionDashboardResponse.self, from: transactionsData)
        let normalizedAddress = address.lowercased()

        return transactionHashes.compactMap { hash -> AddressTransactionSnapshot? in
            guard let entry = transactionPayload.data[hash] else { return nil }
            return mapTransactionSnapshot(
                txHash: entry.transaction.hash ?? hash,
                timestamp: parseBlockchairTimestamp(entry.transaction.time),
                blockHeight: entry.transaction.blockID,
                confirmations: entry.transaction.blockID == nil ? 0 : nil,
                inputTransfers: entry.inputs.map { (recipient: $0.recipient, value: $0.value) },
                outputTransfers: entry.outputs.map { (recipient: $0.recipient, value: $0.value) },
                walletAddress: normalizedAddress,
                defaultCounterparty: address
            )
        }
    }

    private static func fetchRecentTransactionsViaBlockcypher(for address: String, limit: Int) async throws -> [AddressTransactionSnapshot] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let addressURL = blockcypherURL(path: "/addrs/\(encodedAddress)?limit=\(limit)&unspentOnly=false&includeScript=false") else {
            throw URLError(.badURL)
        }

        let (addressData, addressResponse) = try await fetchData(from: addressURL)
        guard let addressHTTPResponse = addressResponse as? HTTPURLResponse, (200 ..< 300).contains(addressHTTPResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let addressPayload = try JSONDecoder().decode(BlockCypherDogecoinAddressResponse.self, from: addressData)
        let allRefs = (addressPayload.txrefs ?? []) + (addressPayload.unconfirmedTxrefs ?? [])
        let hashes = Array(Set(allRefs.map(\.txHash))).prefix(limit)
        guard !hashes.isEmpty else { return [] }

        var snapshots: [AddressTransactionSnapshot] = []
        for hash in hashes {
            guard let encodedHash = hash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let txURL = blockcypherURL(path: "/txs/\(encodedHash)") else {
                continue
            }

            do {
                let (txData, txResponse) = try await fetchData(from: txURL)
                guard let txHTTPResponse = txResponse as? HTTPURLResponse, (200 ..< 300).contains(txHTTPResponse.statusCode) else {
                    continue
                }
                let payload = try JSONDecoder().decode(BlockCypherDogecoinTransactionResponse.self, from: txData)
                guard let txHash = payload.hash else { continue }
                let snapshot = mapTransactionSnapshot(
                    txHash: txHash,
                    timestamp: parseBlockcypherTimestamp(payload.received),
                    blockHeight: payload.blockHeight,
                    confirmations: payload.confirmations,
                    inputTransfers: (payload.inputs ?? []).map { (recipient: $0.addresses?.first, value: $0.outputValue ?? $0.value) },
                    outputTransfers: (payload.outputs ?? []).map { (recipient: $0.addresses?.first, value: $0.value) },
                    walletAddress: address.lowercased(),
                    defaultCounterparty: address
                )
                if let snapshot {
                    snapshots.append(snapshot)
                }
            } catch {
                continue
            }
        }

        return snapshots
    }

    private static func mapTransactionSnapshot(
        txHash: String,
        timestamp: Date?,
        blockHeight: Int?,
        confirmations: Int?,
        inputTransfers: [(recipient: String?, value: Int64?)],
        outputTransfers: [(recipient: String?, value: Int64?)],
        walletAddress: String,
        defaultCounterparty: String
    ) -> AddressTransactionSnapshot? {
        let incomingValue = outputTransfers.reduce(Int64(0)) { partialResult, output in
            guard output.recipient?.lowercased() == walletAddress else { return partialResult }
            return partialResult + max(0, output.value ?? 0)
        }

        let outgoingValue = inputTransfers.reduce(Int64(0)) { partialResult, input in
            guard input.recipient?.lowercased() == walletAddress else { return partialResult }
            return partialResult + max(0, input.value ?? 0)
        }

        let netValue = incomingValue - outgoingValue
        guard netValue != 0 else { return nil }

        let kind: TransactionKind = netValue > 0 ? .receive : .send
        let amount = Double(abs(netValue)) / 100_000_000

        let counterparty: String
        if kind == .receive {
            counterparty = inputTransfers.first(where: { $0.recipient?.lowercased() != walletAddress })?.recipient ?? defaultCounterparty
        } else {
            counterparty = outputTransfers.first(where: { $0.recipient?.lowercased() != walletAddress })?.recipient ?? defaultCounterparty
        }

        let isPending: Bool
        if let confirmations {
            isPending = confirmations <= 0
        } else {
            isPending = blockHeight == nil
        }

        return AddressTransactionSnapshot(
            hash: txHash,
            kind: kind,
            status: isPending ? .pending : .confirmed,
            amount: amount,
            counterpartyAddress: counterparty,
            createdAt: timestamp ?? Date.distantPast,
            blockNumber: blockHeight
        )
    }

    #if DEBUG
    static func reconcileSnapshotsForTesting(_ providerSnapshots: [[AddressTransactionSnapshot]]) -> [AddressTransactionSnapshot] {
        reconcileTransactionSnapshots(providerSnapshots)
    }
    #endif

    private static func reconcileTransactionSnapshots(_ providerSnapshots: [[AddressTransactionSnapshot]]) -> [AddressTransactionSnapshot] {
        var groupedByHash: [String: [AddressTransactionSnapshot]] = [:]
        for snapshots in providerSnapshots {
            for snapshot in snapshots {
                groupedByHash[snapshot.hash, default: []].append(snapshot)
            }
        }

        return groupedByHash.values.compactMap { group in
            guard let baseline = group.first else { return nil }
            if group.count == 1 {
                return baseline
            }

            let hasKindConflict = Set(group.map(\.kind)).count > 1
            let hasAmountConflict = (group.map(\.amount).max() ?? baseline.amount) - (group.map(\.amount).min() ?? baseline.amount) > 0.0001
            let hasCounterpartyConflict = Set(group.map { $0.counterpartyAddress.lowercased() }).count > 1

            let resolvedKind: TransactionKind
            if hasKindConflict {
                resolvedKind = group.contains(where: { $0.kind == .send }) ? .send : .receive
            } else {
                resolvedKind = baseline.kind
            }

            let resolvedAmount = group.map(\.amount).max() ?? baseline.amount
            let resolvedStatus: TransactionStatus = group.contains(where: { $0.status == .pending }) ? .pending : .confirmed
            let resolvedBlock = group.compactMap(\.blockNumber).max()
            let knownDates = group.map(\.createdAt).filter { $0 != Date.distantPast }
            let resolvedCreatedAt = knownDates.min() ?? baseline.createdAt

            let resolvedCounterparty = group
                .map(\.counterpartyAddress)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                ?? baseline.counterpartyAddress

            let finalStatus: TransactionStatus = (hasKindConflict || hasAmountConflict || hasCounterpartyConflict) ? .pending : resolvedStatus

            return AddressTransactionSnapshot(
                hash: baseline.hash,
                kind: resolvedKind,
                status: finalStatus,
                amount: resolvedAmount,
                counterpartyAddress: resolvedCounterparty,
                createdAt: resolvedCreatedAt,
                blockNumber: resolvedBlock
            )
        }
    }

    static func fetchTransactionStatus(txid: String) async throws -> DogecoinTransactionStatus {
        var capturedError: Error?
        let statusCandidates: [ProviderEndpoint] = [.blockchair, .blockcypher]

        for provider in orderedProviders(statusCandidates) {
            do {
                switch provider {
                case .blockchair:
                    let result = try await fetchTransactionStatusViaBlockchair(txid: txid)
                    return result
                case .blockcypher:
                    let result = try await fetchTransactionStatusViaBlockcypher(txid: txid)
                    return result
                case .dogechain:
                    continue
                }
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            throw capturedError
        }
        throw URLError(.cannotLoadFromNetwork)
    }

    private static func runWithProviderFallback<T>(
        candidates: [ProviderEndpoint],
        task: (ProviderEndpoint) async throws -> T
    ) async throws -> T {
        var capturedError: Error?
        for provider in orderedProviders(candidates) {
            do {
                return try await task(provider)
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            throw capturedError
        }
        throw URLError(.cannotLoadFromNetwork)
    }

    static func endpointCatalog() -> [String] {
        return [
            ChainBackendRegistry.DogecoinRuntimeEndpoints.blockchairBaseURL,
            ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL,
            ChainBackendRegistry.DogecoinRuntimeEndpoints.dogechainBaseURL,
        ]
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        return [
            (endpoint: currentBlockchairEndpoint(), probeURL: currentBlockchairEndpoint() + "/stats"),
            (endpoint: currentBlockcypherEndpoint(), probeURL: currentBlockcypherEndpoint()),
            (endpoint: currentDogechainEndpoint(), probeURL: currentDogechainEndpoint() + "/"),
        ]
    }

    private static func orderedProviders(_ candidates: [ProviderEndpoint]) -> [ProviderEndpoint] {
        Array(Set(candidates)).sorted { lhs, rhs in
            lhs.rawValue < rhs.rawValue
        }
    }

    private static func blockchairURL(path: String) -> URL? {
        URL(string: ChainBackendRegistry.DogecoinRuntimeEndpoints.blockchairBaseURL + path)
    }

    private static func blockcypherURL(path: String) -> URL? {
        URL(string: ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL + path)
    }

    private static func dogechainURL(path: String) -> URL? {
        URL(string: ChainBackendRegistry.DogecoinRuntimeEndpoints.dogechainBaseURL + path)
    }

    private static func currentBlockchairEndpoint() -> String {
        return ChainBackendRegistry.DogecoinRuntimeEndpoints.blockchairBaseURL
    }

    private static func currentBlockcypherEndpoint() -> String {
        return ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL
    }

    private static func currentDogechainEndpoint() -> String {
        return ChainBackendRegistry.DogecoinRuntimeEndpoints.dogechainBaseURL
    }

    private static func fetchTransactionStatusViaBlockchair(txid: String) async throws -> DogecoinTransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty,
              let encodedTXID = trimmedTXID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockchairURL(path: "/dashboards/transactions/\(encodedTXID)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(DogecoinTransactionDashboardResponse.self, from: data)
        guard let entry = payload.data.values.first else {
            throw URLError(.cannotParseResponse)
        }

        let blockHeight = entry.transaction.blockID
        let confirmations: Int?
        if let blockHeight {
            let chainTipHeight = try? await fetchDogecoinChainTipHeight()
            if let chainTipHeight, chainTipHeight >= blockHeight {
                confirmations = max(1, chainTipHeight - blockHeight + 1)
            } else {
                confirmations = 1
            }
        } else {
            confirmations = 0
        }

        return DogecoinTransactionStatus(
            confirmed: blockHeight != nil,
            blockHeight: blockHeight,
            networkFeeDOGE: {
                let inputTotalKoinu = entry.inputs.reduce(Int64(0)) { $0 + max(0, $1.value ?? 0) }
                let outputTotalKoinu = entry.outputs.reduce(Int64(0)) { $0 + max(0, $1.value ?? 0) }
                let feeKoinu = max(0, inputTotalKoinu - outputTotalKoinu)
                return Double(feeKoinu) / 100_000_000
            }(),
            confirmations: confirmations
        )
    }

    private static func fetchTransactionStatusViaBlockcypher(txid: String) async throws -> DogecoinTransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty,
              let encodedTXID = trimmedTXID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/txs/\(encodedTXID)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(BlockCypherDogecoinTransactionResponse.self, from: data)
        let confirmed = (payload.confirmations ?? 0) > 0 || payload.blockHeight != nil
        let inputTotalKoinu = (payload.inputs ?? []).reduce(Int64(0)) { partialResult, input in
            partialResult + max(0, input.outputValue ?? input.value ?? 0)
        }
        let outputTotalKoinu = (payload.outputs ?? []).reduce(Int64(0)) { partialResult, output in
            partialResult + max(0, output.value ?? 0)
        }
        let feeDOGE = Double(max(0, inputTotalKoinu - outputTotalKoinu)) / 100_000_000

        return DogecoinTransactionStatus(
            confirmed: confirmed,
            blockHeight: payload.blockHeight,
            networkFeeDOGE: feeDOGE,
            confirmations: payload.confirmations
        )
    }

    private static func parseBlockchairTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        if let unix = TimeInterval(timestamp) {
            return Date(timeIntervalSince1970: unix)
        }

        if let parsedISO = iso8601Formatter.date(from: timestamp) {
            return parsedISO
        }
        if let parsedFractionalISO = iso8601FractionalFormatter.date(from: timestamp) {
            return parsedFractionalISO
        }

        if let parsedLegacy = blockchairTimestampFormatter.date(from: timestamp) {
            return parsedLegacy
        }

        let normalized = timestamp.replacingOccurrences(of: "T", with: " ")
        return blockchairTimestampFormatter.date(from: normalized)
    }

    private static func parseBlockcypherTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timestamp)
    }

    private static func electrsDate(for blockTime: Int?) -> Date? {
        guard let blockTime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(blockTime))
    }

    private static func fetchDogecoinChainTipHeight() async throws -> Int {
        guard let url = blockcypherURL(path: "") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(BlockCypherDogecoinNetworkResponse.self, from: data)
        guard let height = payload.height, height > 0 else {
            throw URLError(.cannotParseResponse)
        }
        return height
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
    }

    private static func base58Decode(_ string: String) -> Data? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var alphabetMap: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() {
            alphabetMap[character] = index
        }

        var bytes = [UInt8](repeating: 0, count: 1)
        for character in string {
            guard let value = alphabetMap[character] else {
                return nil
            }

            var carry = value
            for index in (0 ..< bytes.count).reversed() {
                let total = Int(bytes[index]) * 58 + carry
                bytes[index] = UInt8(total & 0xff)
                carry = total >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }

        let leadingOnes = string.prefix { $0 == "1" }.count
        if leadingOnes > 0 {
            bytes.insert(contentsOf: repeatElement(0, count: leadingOnes), at: 0)
        }

        return Data(bytes)
    }

    private static func doubleSHA256<S: Sequence>(_ bytes: S) -> Data where S.Element == UInt8 {
        let first = SHA256.hash(data: Data(bytes))
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }
}
