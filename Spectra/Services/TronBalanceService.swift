import Foundation

enum TronBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Tron")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Tron")
        case .httpError(let status):
            let format = NSLocalizedString("The Tron provider returned HTTP %d.", comment: "")
            return String(format: format, locale: .current, status)
        }
    }
}

struct TronTokenBalanceSnapshot: Equatable {
    let symbol: String
    let contractAddress: String?
    let balance: Double
}

struct TronHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let symbol: String
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct TronHistoryDiagnostics: Equatable {
    let address: String
    let tronScanTxCount: Int
    let tronScanTRC20Count: Int
    let sourceUsed: String
    let error: String?
}

enum TronBalanceService {
    static let usdtTronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    static let usddTronContract = "TXDk8mbtRbXeYuMNS83CfKPaYYT8XWv9Hz"
    static let usd1TronContract = "TPFqcBAaaUMCSVRCqPaQ9QnzKhmuoLR6Rc"
    static let bttTronContract = "TAFjULxiVgT4qWk6UZwjqwZXTSaGaqnVp4"

    struct TrackedTRC20Token: Equatable {
        let symbol: String
        let contractAddress: String
        let decimals: Int
    }

    static let defaultTrackedTRC20Tokens: [TrackedTRC20Token] = [
        TrackedTRC20Token(symbol: "USDT", contractAddress: usdtTronContract, decimals: 6),
        TrackedTRC20Token(symbol: "USDD", contractAddress: usddTronContract, decimals: 18),
        TrackedTRC20Token(symbol: "USD1", contractAddress: usd1TronContract, decimals: 18),
        TrackedTRC20Token(symbol: "BTT", contractAddress: bttTronContract, decimals: 18),
    ]

    private static let tronScanAddressInfoBases = ChainBackendRegistry.TronRuntimeEndpoints.tronScanAddressInfoBases
    private static let tronGridAccountsBases = ChainBackendRegistry.TronRuntimeEndpoints.tronGridAccountsBases

    static func endpointCatalog() -> [String] {
        var endpoints: [String] = []
        for endpoint in tronScanAddressInfoBases + tronGridAccountsBases {
            if !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        endpointCatalog().map { endpoint in
            if endpoint.contains("tronscan") {
                return (endpoint: endpoint, probeURL: ChainBackendRegistry.TronRuntimeEndpoints.tronScanProbeURL)
            }
            return (endpoint: endpoint, probeURL: ChainBackendRegistry.TronRuntimeEndpoints.tronGridProbeURL)
        }
    }

    private struct TronScanAddressInfoResponse: Decodable {
        let balance: Int64?
        let tokens: [TronScanTokenBalance]?
    }

    private struct TronScanTokenBalance: Decodable {
        let tokenId: String?
        let balance: String?
    }

    private struct TronGridTRC20HistoryResponse: Decodable {
        let data: [TronGridTRC20HistoryItem]?
    }

    private struct TronGridTRC20HistoryItem: Decodable {
        let transaction_id: String?
        let from: String?
        let to: String?
        let value: String?
        let block_timestamp: Int64?
        let token_info: TronGridTokenInfo?
    }

    private struct TronGridTokenInfo: Decodable {
        let address: String?
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTokenAmount(_ raw: String?, decimals: Int) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decimal = Decimal(string: trimmed) else {
            return nil
        }
        let divisor = pow(10, Double(min(max(decimals, 0), 18)))
        let value = NSDecimalNumber(decimal: decimal).doubleValue / divisor
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidTronAddress(address)
    }

    static func fetchBalances(for address: String) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        try await fetchBalances(for: address, trackedTokens: defaultTrackedTRC20Tokens)
    }

    static func fetchBalances(
        for address: String,
        trackedTokens: [TrackedTRC20Token]
    ) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw TronBalanceServiceError.invalidAddress
        }

        do {
            return try await fetchBalancesFromTronScan(for: normalized, trackedTokens: trackedTokens)
        } catch {
            return try await fetchBalancesFromTronGrid(for: normalized, trackedTokens: trackedTokens)
        }
    }

    private static func fetchBalancesFromTronScan(
        for address: String,
        trackedTokens: [TrackedTRC20Token]
    ) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        var lastError: Error = TronBalanceServiceError.invalidResponse
        for base in tronScanAddressInfoBases {
            var components = URLComponents(string: base)
            components?.queryItems = [URLQueryItem(name: "address", value: address)]
            guard let url = components?.url else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    lastError = TronBalanceServiceError.httpError(http.statusCode)
                    continue
                }

                let decoded = try JSONDecoder().decode(TronScanAddressInfoResponse.self, from: data)
                let trxSun = decoded.balance ?? 0
                let trxBalance = Double(trxSun) / 1_000_000.0

                let tokenLookup = Dictionary(uniqueKeysWithValues: trackedTokens.map { ($0.contractAddress.lowercased(), $0) })
                let tokenBalances: [TronTokenBalanceSnapshot] = (decoded.tokens ?? []).compactMap { token in
                    guard let contract = token.tokenId?.lowercased(),
                          let tracked = tokenLookup[contract] else {
                        return nil
                    }
                    let decimals = tracked.decimals
                    let balance = normalizedTokenAmount(token.balance, decimals: decimals) ?? 0
                    return TronTokenBalanceSnapshot(
                        symbol: tracked.symbol,
                        contractAddress: tracked.contractAddress,
                        balance: balance
                    )
                }

                return (trxBalance, tokenBalances)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func fetchBalancesFromTronGrid(
        for address: String,
        trackedTokens: [TrackedTRC20Token]
    ) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        var lastError: Error = TronBalanceServiceError.invalidResponse
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)") else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["data"] as? [[String: Any]],
                      let account = rows.first else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                let trxSun = (account["balance"] as? NSNumber)?.int64Value ?? 0
                let trxBalance = Double(trxSun) / 1_000_000.0

                var balancesByContract: [String: Double] = [:]
                let tokenLookup = Dictionary(uniqueKeysWithValues: trackedTokens.map { ($0.contractAddress.lowercased(), $0) })
                if let trc20Rows = account["trc20"] as? [[String: String]] {
                    for row in trc20Rows {
                        for (contract, rawAmount) in row {
                            let normalizedContract = contract.lowercased()
                            guard let tracked = tokenLookup[normalizedContract] else { continue }
                            let balance = normalizedTokenAmount(rawAmount, decimals: tracked.decimals) ?? 0
                            balancesByContract[tracked.contractAddress] = balance
                        }
                    }
                }

                let tokenBalances: [TronTokenBalanceSnapshot] = trackedTokens.map { token in
                    TronTokenBalanceSnapshot(
                        symbol: token.symbol,
                        contractAddress: token.contractAddress,
                        balance: balancesByContract[token.contractAddress] ?? 0
                    )
                }

                return (trxBalance, tokenBalances)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 50) async -> (snapshots: [TronHistorySnapshot], diagnostics: TronHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                TronHistoryDiagnostics(
                    address: normalized,
                    tronScanTxCount: 0,
                    tronScanTRC20Count: 0,
                    sourceUsed: "none",
                    error: TronBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let txResult = await fetchNativeTransfers(address: normalized, limit: limit)
        let trc20Result = await fetchUSDTTRC20Transfers(address: normalized, limit: limit)
        let merged = dedupeAndSort(native: txResult, usdt: trc20Result)
        let errorMessage = [txResult.error, trc20Result.error].compactMap { $0 }.joined(separator: " | ")

        return (
            merged,
            TronHistoryDiagnostics(
                address: normalized,
                tronScanTxCount: txResult.items.count,
                tronScanTRC20Count: trc20Result.items.count,
                sourceUsed: "trongrid",
                error: errorMessage.isEmpty ? nil : errorMessage
            )
        )
    }

    private static func fetchNativeTransfers(address: String, limit: Int) async -> (items: [TronHistorySnapshot], error: String?) {
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)/transactions?limit=\(max(1, min(limit, 200)))&only_confirmed=false&order_by=block_timestamp,desc&visible=true") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    continue
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["data"] as? [[String: Any]] else {
                    continue
                }
                let lowerAddress = address.lowercased()
                let snapshots = rows.compactMap { row in
                    nativeHistorySnapshot(from: row, lowerAddress: lowerAddress)
                }
                return (snapshots, nil)
            } catch {
                continue
            }
        }
        return ([], TronBalanceServiceError.invalidResponse.localizedDescription)
    }

    private static func nativeHistorySnapshot(from row: [String: Any], lowerAddress: String) -> TronHistorySnapshot? {
        let hash = (row["txID"] as? String) ?? (row["txid"] as? String) ?? (row["transaction_id"] as? String)
        guard let hash, !hash.isEmpty else { return nil }

        let rawData = row["raw_data"] as? [String: Any]
        let contracts = rawData?["contract"] as? [[String: Any]]
        let contract = contracts?.first
        let contractType = (contract?["type"] as? String) ?? (row["type"] as? String)
        guard contractType == "TransferContract" else { return nil }

        let parameter = contract?["parameter"] as? [String: Any]
        let value = parameter?["value"] as? [String: Any]

        let from = (value?["owner_address"] as? String) ?? (row["from"] as? String)
        let to = (value?["to_address"] as? String) ?? (row["to"] as? String)
        guard let from, let to else { return nil }

        let fromLower = from.lowercased()
        let toLower = to.lowercased()
        guard fromLower == lowerAddress || toLower == lowerAddress else { return nil }

        let valueAmountNumber = (value?["amount"] as? NSNumber)?.doubleValue
        let valueAmountString = Double(value?["amount"] as? String ?? "")
        let rowAmountNumber = (row["amount"] as? NSNumber)?.doubleValue
        let rowAmountString = Double(row["amount"] as? String ?? "")
        let rawAmount = valueAmountNumber ?? valueAmountString ?? rowAmountNumber ?? rowAmountString ?? 0
        let amount = rawAmount / 1_000_000.0
        guard amount > 0 else { return nil }

        let rowTimestampNumber = (row["block_timestamp"] as? NSNumber)?.doubleValue
        let rowTimestampString = Double(row["block_timestamp"] as? String ?? "")
        let rawTimestampNumber = (rawData?["timestamp"] as? NSNumber)?.doubleValue
        let rawTimestampString = Double(rawData?["timestamp"] as? String ?? "")
        let timestampMillis = rowTimestampNumber ?? rowTimestampString ?? rawTimestampNumber ?? rawTimestampString ?? 0
        let createdAt = Date(timeIntervalSince1970: max(0, timestampMillis / 1_000.0))

        let contractRet = ((row["ret"] as? [[String: Any]])?.first?["contractRet"] as? String)?.uppercased()
        let status: TransactionStatus = (contractRet == nil || contractRet == "SUCCESS") ? .confirmed : .pending
        let isOutgoing = fromLower == lowerAddress

        return TronHistorySnapshot(
            transactionHash: hash,
            kind: isOutgoing ? .send : .receive,
            amount: amount,
            symbol: "TRX",
            counterpartyAddress: isOutgoing ? to : from,
            createdAt: createdAt,
            status: status
        )
    }

    private static func fetchUSDTTRC20Transfers(address: String, limit: Int) async -> (items: [TronHistorySnapshot], error: String?) {
        await fetchUSDTTRC20TransfersFromTronGrid(address: address, limit: limit)
    }

    private static func fetchUSDTTRC20TransfersFromTronGrid(address: String, limit: Int) async -> (items: [TronHistorySnapshot], error: String?) {
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)/transactions/trc20?limit=\(max(1, min(limit, 200)))&contract_address=\(usdtTronContract)") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    continue
                }
                let decoded = try JSONDecoder().decode(TronGridTRC20HistoryResponse.self, from: data)
                let lowerAddress = address.lowercased()
                let snapshots = (decoded.data ?? []).compactMap { item -> TronHistorySnapshot? in
                    guard let txid = item.transaction_id, !txid.isEmpty else { return nil }
                    guard let from = item.from, let to = item.to else { return nil }
                    if let contract = item.token_info?.address,
                       contract.caseInsensitiveCompare(usdtTronContract) != .orderedSame {
                        return nil
                    }
                    let fromLower = from.lowercased()
                    let toLower = to.lowercased()
                    guard fromLower == lowerAddress || toLower == lowerAddress else { return nil }
                    let decimals = 6
                    let amount = normalizedTokenAmount(item.value, decimals: decimals) ?? 0
                    let isOutgoing = fromLower == lowerAddress
                    let createdAt = Date(timeIntervalSince1970: Double(max(0, item.block_timestamp ?? 0)) / 1_000.0)
                    return TronHistorySnapshot(
                        transactionHash: txid,
                        kind: isOutgoing ? .send : .receive,
                        amount: amount,
                        symbol: "USDT",
                        counterpartyAddress: isOutgoing ? to : from,
                        createdAt: createdAt,
                        status: .confirmed
                    )
                }
                return (snapshots, nil)
            } catch {
                continue
            }
        }
        return ([], TronBalanceServiceError.invalidResponse.localizedDescription)
    }

    private static func dedupeAndSort(native: (items: [TronHistorySnapshot], error: String?), usdt: (items: [TronHistorySnapshot], error: String?)) -> [TronHistorySnapshot] {
        var map: [String: TronHistorySnapshot] = [:]
        for item in native.items + usdt.items {
            let key = "\(item.transactionHash.lowercased())|\(item.symbol)"
            if let existing = map[key] {
                if item.createdAt > existing.createdAt {
                    map[key] = item
                }
            } else {
                map[key] = item
            }
        }
        return map.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
    }
}
