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
    private static let tronGridRPCBases = ChainBackendRegistry.TronRuntimeEndpoints.tronGridBroadcastBaseURLs

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
        let balance: FlexibleInt64?
        let tokens: [TronScanTokenBalance]?
    }

    private struct TronScanTokenBalance: Decodable {
        let tokenId: String?
        let tokenName: String?
        let tokenAbbr: String?
        let tokenDecimal: Int?
        let tokenType: String?
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

    private struct FlexibleInt64: Decodable {
        let value: Int64

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int64.self) {
                value = intValue
                return
            }
            if let stringValue = try? container.decode(String.self) {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let intValue = Int64(trimmed) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Expected an Int64-compatible string."
                    )
                }
                value = intValue
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected Int64 or string-backed Int64."
            )
        }
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
        // Some Tron providers return already-normalized decimal balances
        // ("3.25" TRX) while others return smallest-unit integers ("3250000").
        if trimmed.contains(".") || trimmed.lowercased().contains("e") {
            let value = NSDecimalNumber(decimal: decimal).doubleValue
            guard value.isFinite, value >= 0 else { return nil }
            return value
        }
        let divisor = pow(10, Double(min(max(decimals, 0), 18)))
        let value = NSDecimalNumber(decimal: decimal).doubleValue / divisor
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func normalizedInt64(_ raw: Any?) -> Int64? {
        switch raw {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int64(trimmed) {
                return value
            }
            if let decimal = Decimal(string: trimmed) {
                let value = NSDecimalNumber(decimal: decimal).doubleValue
                guard value.isFinite, value >= 0 else { return nil }
                return Int64(value.rounded())
            }
            return nil
        default:
            return nil
        }
    }

    private static func tronScanTopLevelBalanceSun(from object: [String: Any]) -> Int64 {
        if let direct = normalizedInt64(object["balance"]) {
            return direct
        }
        if let dataObject = object["data"] as? [String: Any],
           let nested = normalizedInt64(dataObject["balance"]) {
            return nested
        }
        if let dataRows = object["data"] as? [[String: Any]],
           let first = dataRows.first,
           let nested = normalizedInt64(first["balance"]) {
            return nested
        }
        return 0
    }

    private static func normalizedString(_ raw: Any?) -> String? {
        switch raw {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func tronScanTokenRows(from object: [String: Any]) -> [[String: Any]] {
        if let rows = object["tokens"] as? [[String: Any]] {
            return rows
        }
        if let rows = object["withPriceTokens"] as? [[String: Any]] {
            return rows
        }
        if let rows = object["tokenBalances"] as? [[String: Any]] {
            return rows
        }
        if let data = object["data"] as? [String: Any] {
            if let rows = data["tokens"] as? [[String: Any]] {
                return rows
            }
            if let rows = data["withPriceTokens"] as? [[String: Any]] {
                return rows
            }
            if let rows = data["tokenBalances"] as? [[String: Any]] {
                return rows
            }
        }
        return flattenedJSONObjectRows(from: object)
    }

    private static func flattenedJSONObjectRows(from raw: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []

        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                results.append(dictionary)
                for nestedValue in dictionary.values {
                    visit(nestedValue)
                }
                return
            }

            if let array = value as? [Any] {
                for nestedValue in array {
                    visit(nestedValue)
                }
            }
        }

        visit(raw)
        return results
    }

    private static func tronScanRowContractAddress(_ row: [String: Any]) -> String? {
        normalizedString(row["tokenId"])
            ?? normalizedString(row["token_id"])
            ?? normalizedString(row["contract_address"])
            ?? normalizedString(row["contractAddress"])
    }

    private static func tronScanRowSymbol(_ row: [String: Any]) -> String? {
        normalizedString(row["tokenAbbr"])
            ?? normalizedString(row["token_abbr"])
            ?? normalizedString(row["abbr"])
            ?? normalizedString(row["symbol"])
    }

    private static func tronScanRowName(_ row: [String: Any]) -> String? {
        normalizedString(row["tokenName"])
            ?? normalizedString(row["token_name"])
            ?? normalizedString(row["name"])
    }

    private static func tronScanRowDecimals(_ row: [String: Any]) -> Int {
        if let value = normalizedInt64(row["tokenDecimal"]) {
            return Int(value)
        }
        if let value = normalizedInt64(row["token_decimal"]) {
            return Int(value)
        }
        if let value = normalizedInt64(row["decimals"]) {
            return Int(value)
        }
        return 6
    }

    private static func tronScanRowBalanceString(_ row: [String: Any]) -> String? {
        normalizedString(row["balance"])
            ?? normalizedString(row["amount"])
            ?? normalizedString(row["quantity"])
            ?? normalizedString(row["balanceStr"])
            ?? normalizedString(row["value"])
    }

    private static func tronScanNativeBalanceFallback(from rows: [[String: Any]]) -> Double? {
        guard let nativeRow = rows.first(where: { row in
            if tronScanRowContractAddress(row) == "_" { return true }
            if tronScanRowSymbol(row)?.lowercased() == "trx" { return true }
            if tronScanRowName(row)?.lowercased() == "trx" { return true }
            return false
        }) else {
            return nil
        }
        return normalizedTokenAmount(
            tronScanRowBalanceString(nativeRow),
            decimals: tronScanRowDecimals(nativeRow)
        )
    }

    private static func tronScanTrackedTokenBalances(
        from rows: [[String: Any]],
        trackedTokens: [TrackedTRC20Token]
    ) -> [TronTokenBalanceSnapshot] {
        let tokenLookup = Dictionary(uniqueKeysWithValues: trackedTokens.map { ($0.contractAddress.lowercased(), $0) })
        var balancesByContract: [String: TronTokenBalanceSnapshot] = [:]

        for row in rows {
            guard let contract = tronScanRowContractAddress(row)?.lowercased(),
                  let tracked = tokenLookup[contract] else {
                continue
            }
            let balance = normalizedTokenAmount(
                tronScanRowBalanceString(row),
                decimals: tracked.decimals
            ) ?? 0
            let snapshot = TronTokenBalanceSnapshot(
                symbol: tracked.symbol,
                contractAddress: tracked.contractAddress,
                balance: balance
            )
            if let existing = balancesByContract[tracked.contractAddress], existing.balance > snapshot.balance {
                continue
            }
            balancesByContract[tracked.contractAddress] = snapshot
        }

        return trackedTokens.compactMap { tracked in
            balancesByContract[tracked.contractAddress]
        }
    }

    private static func tronScanNativeBalanceFallback(from tokens: [TronScanTokenBalance]) -> Double? {
        guard let nativeRow = tokens.first(where: { token in
            if token.tokenId == "_" { return true }
            if token.tokenAbbr?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "trx" { return true }
            if token.tokenName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "trx" { return true }
            return false
        }) else {
            return nil
        }
        return normalizedTokenAmount(nativeRow.balance, decimals: nativeRow.tokenDecimal ?? 6)
    }

    private static func tronScanResourceURL(from accountInfoBase: String) -> URL? {
        guard var components = URLComponents(string: accountInfoBase) else {
            return nil
        }
        components.path = "/api/account/resourcev2"
        return components.url
    }

    private static func tronScanTokenOverviewURL(from accountInfoBase: String) -> URL? {
        guard var components = URLComponents(string: accountInfoBase) else {
            return nil
        }
        components.path = "/api/account/token_asset_overview"
        return components.url
    }

    private static func tronScanTokenOverviewBalanceFallback(for address: String, accountInfoBase: String) async -> Double? {
        guard let overviewBaseURL = tronScanTokenOverviewURL(from: accountInfoBase),
              var components = URLComponents(url: overviewBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "address", value: address)]
        guard let url = components.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await fetchData(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = object["data"] as? [[String: Any]] else {
                return nil
            }

            guard let nativeRow = rows.first(where: { row in
                if (row["tokenId"] as? String) == "_" { return true }
                if (row["tokenAbbr"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "trx" { return true }
                if (row["tokenName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "trx" { return true }
                return false
            }) else {
                return nil
            }

            let decimals = normalizedInt64(nativeRow["tokenDecimal"]).map(Int.init) ?? 6
            if let rawBalance = nativeRow["balance"] as? String {
                return normalizedTokenAmount(rawBalance, decimals: decimals)
            }
            if let rawBalance = normalizedInt64(nativeRow["balance"]) {
                return normalizedTokenAmount(String(rawBalance), decimals: decimals)
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func tronScanStakedBalanceFallback(for address: String, accountInfoBase: String) async -> Double? {
        guard let resourceBaseURL = tronScanResourceURL(from: accountInfoBase),
              var components = URLComponents(url: resourceBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "address", value: address)]
        guard let url = components.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await fetchData(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let rows = object["data"] as? [[String: Any]] {
                let stakedSun = rows.reduce(into: Int64(0)) { partialResult, row in
                    partialResult += normalizedInt64(row["balance"]) ?? 0
                }
                if stakedSun > 0 {
                    return Double(stakedSun) / 1_000_000.0
                }
            }

            let fallbackKeys = [
                "frozenBalance",
                "frozen_balance",
                "frozenBalanceForBandwidth",
                "frozenBalanceForEnergy"
            ]
            let fallbackSun = fallbackKeys.reduce(into: Int64(0)) { partialResult, key in
                partialResult += normalizedInt64(object[key]) ?? 0
            }
            guard fallbackSun > 0 else {
                return nil
            }
            return Double(fallbackSun) / 1_000_000.0
        } catch {
            return nil
        }
    }

    private static func tronGridRPCNativeBalanceFallback(for address: String) async -> Double? {
        for base in tronGridRPCBases {
            guard let nowBlockURL = URL(string: "\(base)/wallet/getnowblock"),
                  let accountBalanceURL = URL(string: "\(base)/wallet/getaccountbalance"),
                  let accountURL = URL(string: "\(base)/wallet/getaccount") else {
                continue
            }

            do {
                var nowBlockRequest = URLRequest(url: nowBlockURL)
                nowBlockRequest.httpMethod = "POST"
                nowBlockRequest.timeoutInterval = 20
                nowBlockRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                nowBlockRequest.httpBody = try JSONSerialization.data(withJSONObject: [:])

                let (nowBlockData, nowBlockResponse) = try await fetchData(for: nowBlockRequest)
                if let http = nowBlockResponse as? HTTPURLResponse,
                   (200 ... 299).contains(http.statusCode),
                   let blockObject = try JSONSerialization.jsonObject(with: nowBlockData) as? [String: Any],
                   let blockID = normalizedString(blockObject["blockID"]),
                   let blockHeader = blockObject["block_header"] as? [String: Any],
                   let rawData = blockHeader["raw_data"] as? [String: Any],
                   let blockNumber = normalizedInt64(rawData["number"]) {
                    var accountBalanceRequest = URLRequest(url: accountBalanceURL)
                    accountBalanceRequest.httpMethod = "POST"
                    accountBalanceRequest.timeoutInterval = 20
                    accountBalanceRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    accountBalanceRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                        "account_identifier": [
                            "address": address
                        ],
                        "block_identifier": [
                            "hash": blockID,
                            "number": blockNumber
                        ],
                        "visible": true
                    ])

                    let (accountBalanceData, accountBalanceResponse) = try await fetchData(for: accountBalanceRequest)
                    if let accountBalanceHTTP = accountBalanceResponse as? HTTPURLResponse,
                       (200 ... 299).contains(accountBalanceHTTP.statusCode),
                       let object = try JSONSerialization.jsonObject(with: accountBalanceData) as? [String: Any] {
                        let liquidSun = normalizedInt64(object["balance"]) ?? 0
                        let frozenSun = (object["frozen"] as? [[String: Any]])?.reduce(into: Int64(0)) { partialResult, row in
                            partialResult += normalizedInt64(row["frozen_balance"]) ?? normalizedInt64(row["balance"]) ?? 0
                        } ?? 0
                        let delegatedFrozenV2Sun = (object["delegated_frozenV2"] as? [[String: Any]])?.reduce(into: Int64(0)) { partialResult, row in
                            partialResult += normalizedInt64(row["frozen_balance"]) ?? normalizedInt64(row["balance"]) ?? 0
                        } ?? 0
                        let totalSun = liquidSun + frozenSun + delegatedFrozenV2Sun
                        if totalSun > 0 {
                            return Double(totalSun) / 1_000_000.0
                        }
                    }
                }

                var request = URLRequest(url: accountURL)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "address": address,
                    "visible": true
                ])

                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let liquidSun = normalizedInt64(object["balance"]) ?? 0
                let frozenV2Sun = (object["frozenV2"] as? [[String: Any]])?.reduce(into: Int64(0)) { partialResult, row in
                    partialResult += normalizedInt64(row["amount"]) ?? normalizedInt64(row["balance"]) ?? 0
                } ?? 0
                let frozenSun = (object["frozen"] as? [[String: Any]])?.reduce(into: Int64(0)) { partialResult, row in
                    partialResult += normalizedInt64(row["frozen_balance"]) ?? normalizedInt64(row["balance"]) ?? 0
                } ?? 0

                let totalSun = liquidSun + frozenV2Sun + frozenSun
                if totalSun > 0 {
                    return Double(totalSun) / 1_000_000.0
                }
            } catch {
                continue
            }
        }

        return nil
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

        let tronScanResult = try? await fetchBalancesFromTronScan(for: normalized, trackedTokens: trackedTokens)
        let tronGridResult = try? await fetchBalancesFromTronGrid(for: normalized, trackedTokens: trackedTokens)

        if let tronScanResult, let tronGridResult {
            let tronScanHasTokenBalances = tronScanResult.tokenBalances.contains { $0.balance > 0 }
            let tronGridHasTokenBalances = tronGridResult.tokenBalances.contains { $0.balance > 0 }
            if tronGridResult.trxBalance > tronScanResult.trxBalance {
                return tronGridResult
            }
            if tronScanResult.trxBalance > tronGridResult.trxBalance {
                return tronScanResult
            }
            if tronGridHasTokenBalances && !tronScanHasTokenBalances {
                return tronGridResult
            }
            return tronScanResult
        }

        if let tronScanResult {
            return tronScanResult
        }

        if let tronGridResult {
            return tronGridResult
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

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                let trxSun = tronScanTopLevelBalanceSun(from: object)
                let topLevelTRXBalance = Double(trxSun) / 1_000_000.0
                let tokenRows = tronScanTokenRows(from: object)
                let tokenFallbackTRXBalance = tronScanNativeBalanceFallback(from: tokenRows)
                let tokenOverviewFallbackTRXBalance: Double?
                if topLevelTRXBalance <= 0, (tokenFallbackTRXBalance ?? 0) <= 0 {
                    tokenOverviewFallbackTRXBalance = await tronScanTokenOverviewBalanceFallback(
                        for: address,
                        accountInfoBase: base
                    )
                } else {
                    tokenOverviewFallbackTRXBalance = nil
                }
                let stakedFallbackTRXBalance: Double?
                if topLevelTRXBalance <= 0,
                   (tokenFallbackTRXBalance ?? 0) <= 0,
                   (tokenOverviewFallbackTRXBalance ?? 0) <= 0 {
                    stakedFallbackTRXBalance = await tronScanStakedBalanceFallback(for: address, accountInfoBase: base)
                } else {
                    stakedFallbackTRXBalance = nil
                }
                let trxBalance = topLevelTRXBalance > 0
                    ? topLevelTRXBalance
                    : (tokenFallbackTRXBalance ?? tokenOverviewFallbackTRXBalance ?? stakedFallbackTRXBalance ?? topLevelTRXBalance)

                let tokenBalances = tronScanTrackedTokenBalances(from: tokenRows, trackedTokens: trackedTokens)

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
                      let rows = object["data"] as? [[String: Any]] else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                if rows.isEmpty {
                    let tokenBalances = trackedTokens.map { token in
                        TronTokenBalanceSnapshot(
                            symbol: token.symbol,
                            contractAddress: token.contractAddress,
                            balance: 0
                        )
                    }
                    return (0, tokenBalances)
                }

                guard let account = rows.first else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                let trxSun = normalizedInt64(account["balance"]) ?? 0
                let topLevelTRXBalance = Double(trxSun) / 1_000_000.0
                let rpcFallbackTRXBalance: Double?
                if topLevelTRXBalance <= 0 {
                    rpcFallbackTRXBalance = await tronGridRPCNativeBalanceFallback(for: address)
                } else {
                    rpcFallbackTRXBalance = nil
                }
                let trxBalance = rpcFallbackTRXBalance ?? topLevelTRXBalance

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
        let nativeContractTypes: Set<String> = ["TransferContract", "TransferAssetContract"]
        guard let contractType, nativeContractTypes.contains(contractType) else { return nil }

        let parameter = contract?["parameter"] as? [String: Any]
        let value = parameter?["value"] as? [String: Any]

        let from = (value?["owner_address"] as? String) ?? (row["from"] as? String)
        let to = (value?["to_address"] as? String) ?? (row["to"] as? String)
        guard let from, let to = to else { return nil }

        let amountSun = normalizedInt64(value?["amount"])
            ?? normalizedInt64(value?["quant"])
            ?? normalizedInt64(value?["call_value"])
            ?? normalizedInt64(row["amount"])
            ?? normalizedInt64(row["value"])
            ?? normalizedInt64(row["quant"])
            ?? 0
        let amount = Double(amountSun) / 1_000_000.0
        guard amount > 0 else { return nil }

        let timestampMS = normalizedInt64(row["block_timestamp"])
            ?? normalizedInt64(row["timestamp"])
            ?? 0
        let createdAt = Date(timeIntervalSince1970: Double(timestampMS) / 1_000.0)

        let fromLower = from.lowercased()
        let toLower = to.lowercased()
        let kind: TransactionKind
        let counterparty: String
        if toLower == lowerAddress {
            kind = .receive
            counterparty = from
        } else if fromLower == lowerAddress {
            kind = .send
            counterparty = to
        } else {
            kind = .receive
            counterparty = from
        }

        let contractRet = (row["ret"] as? [[String: Any]])?.first?["contractRet"] as? String
        let status: TransactionStatus = (contractRet == nil || contractRet == "SUCCESS") ? .confirmed : .failed

        return TronHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amount,
            symbol: "TRX",
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: status
        )
    }

    private static func fetchUSDTTRC20Transfers(address: String, limit: Int) async -> (items: [TronHistorySnapshot], error: String?) {
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)/transactions/trc20?limit=\(max(1, min(limit, 200)))&contract_address=\(usdtTronContract)&only_confirmed=false&order_by=block_timestamp,desc") else {
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
                    trc20HistorySnapshot(from: row, lowerAddress: lowerAddress)
                }
                return (snapshots, nil)
            } catch {
                continue
            }
        }
        return ([], TronBalanceServiceError.invalidResponse.localizedDescription)
    }

    private static func trc20HistorySnapshot(from row: [String: Any], lowerAddress: String) -> TronHistorySnapshot? {
        let hash = (row["transaction_id"] as? String) ?? (row["txID"] as? String)
        guard let hash, !hash.isEmpty else { return nil }

        let tokenInfo = row["token_info"] as? [String: Any]
        let contract = (tokenInfo?["address"] as? String) ?? (row["contract_address"] as? String)
        guard contract?.lowercased() == usdtTronContract.lowercased() else { return nil }

        let from = (row["from"] as? String) ?? ""
        let to = (row["to"] as? String) ?? ""
        guard !from.isEmpty, !to.isEmpty else { return nil }

        let decimals = normalizedInt64(tokenInfo?["decimals"]).map(Int.init) ?? 6
        let rawValue = normalizedString(row["value"]) ?? normalizedString(row["amount"])
        let amount = normalizedTokenAmount(rawValue, decimals: decimals) ?? 0
        guard amount > 0 else { return nil }

        let timestampMS = normalizedInt64(row["block_timestamp"])
            ?? normalizedInt64(row["timestamp"])
            ?? 0
        let createdAt = Date(timeIntervalSince1970: Double(timestampMS) / 1_000.0)

        let fromLower = from.lowercased()
        let toLower = to.lowercased()
        let kind: TransactionKind
        let counterparty: String
        if toLower == lowerAddress {
            kind = .receive
            counterparty = from
        } else if fromLower == lowerAddress {
            kind = .send
            counterparty = to
        } else {
            kind = .receive
            counterparty = from
        }

        return TronHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amount,
            symbol: "USDT",
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: .confirmed
        )
    }

    private static func dedupeAndSort(native: (items: [TronHistorySnapshot], error: String?), usdt: (items: [TronHistorySnapshot], error: String?)) -> [TronHistorySnapshot] {
        var ordered: [TronHistorySnapshot] = []
        var seen: Set<String> = []

        for item in native.items + usdt.items {
            if seen.insert(item.transactionHash).inserted {
                ordered.append(item)
            }
        }

        return ordered.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.transactionHash > rhs.transactionHash
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await URLSession.shared.data(for: request)
    }
}
