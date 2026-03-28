import Foundation

enum PolkadotBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString("The Polkadot address is not valid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("The Polkadot provider response was invalid.", comment: "")
        case .httpError(let code):
            let format = NSLocalizedString("The Polkadot provider returned HTTP %d.", comment: "")
            return String(format: format, locale: .current, code)
        }
    }
}

struct PolkadotHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct PolkadotHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum PolkadotBalanceService {
    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let dotDivisor = Decimal(string: "10000000000")!
    private static let scanBlockLimit = 256

    private static let sidecarEndpoints = ChainBackendRegistry.PolkadotRuntimeEndpoints.sidecarBaseURLs

    private static let rpcEndpoints = ChainBackendRegistry.PolkadotRuntimeEndpoints.rpcBaseURLs

    static func endpointCatalog() -> [String] {
        sidecarEndpoints + rpcEndpoints
    }

    static func rpcEndpointCatalog() -> [String] {
        rpcEndpoints
    }

    static func sidecarEndpointCatalog() -> [String] {
        sidecarEndpoints
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        sidecarEndpoints.map { ($0, "\($0)/transaction/material") } +
            rpcEndpoints.map { ($0, $0) }
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidPolkadotAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw PolkadotBalanceServiceError.invalidAddress
        }

        var lastError: Error?
        for endpoint in sidecarEndpoints {
            do {
                let info = try await fetchBalanceInfo(address: normalized, endpoint: endpoint)
                if let free = decimalString(info.free) {
                    return decimalToDouble(free / dotDivisor)
                }
                throw PolkadotBalanceServiceError.invalidResponse
            } catch {
                lastError = error
            }
        }

        throw lastError ?? PolkadotBalanceServiceError.invalidResponse
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [PolkadotHistorySnapshot], diagnostics: PolkadotHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                PolkadotHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: PolkadotBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let boundedLimit = max(1, min(limit, 80))
        var lastError: String?
        for endpoint in sidecarEndpoints {
            do {
                let snapshots = try await fetchSidecarHistory(address: normalized, endpoint: endpoint, limit: boundedLimit)
                return (
                    snapshots,
                    PolkadotHistoryDiagnostics(
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
            PolkadotHistoryDiagnostics(
                address: normalized,
                sourceUsed: sidecarEndpoints.first ?? "none",
                transactionCount: 0,
                error: lastError ?? PolkadotBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    private struct SidecarBalanceInfo: Decodable {
        let free: String?
        let nonce: Int?
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchBalanceInfo(address: String, endpoint: String) async throws -> SidecarBalanceInfo {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(endpoint)/accounts/\(encoded)/balance-info") else {
            throw PolkadotBalanceServiceError.invalidResponse
        }
        let (data, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw PolkadotBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw PolkadotBalanceServiceError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(SidecarBalanceInfo.self, from: data)
    }

    private static func fetchSidecarHistory(address: String, endpoint: String, limit: Int) async throws -> [PolkadotHistorySnapshot] {
        guard let headURL = URL(string: "\(endpoint)/blocks/head") else {
            throw PolkadotBalanceServiceError.invalidResponse
        }
        let (headData, headResponse) = try await SpectraNetworkRouter.shared.data(from: headURL, profile: .chainRead)
        guard let headHTTP = headResponse as? HTTPURLResponse,
              (200 ... 299).contains(headHTTP.statusCode) else {
            throw PolkadotBalanceServiceError.httpError((headResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let headObject = try jsonObject(from: headData)
        let headNumber = stringValue(at: ["number"], in: headObject).flatMap(Int.init)
            ?? stringValue(at: ["header", "number"], in: headObject).flatMap(Int.init)
        guard let startHeight = headNumber else {
            throw PolkadotBalanceServiceError.invalidResponse
        }

        var snapshots: [PolkadotHistorySnapshot] = []
        let lowerBound = max(0, startHeight - scanBlockLimit)
        for height in stride(from: startHeight, through: lowerBound, by: -1) {
            guard snapshots.count < limit else { break }
            guard let blockURL = URL(string: "\(endpoint)/blocks/\(height)") else { continue }

            do {
                let (blockData, blockResponse) = try await SpectraNetworkRouter.shared.data(from: blockURL, profile: .chainRead)
                guard let blockHTTP = blockResponse as? HTTPURLResponse,
                      (200 ... 299).contains(blockHTTP.statusCode) else {
                    continue
                }

                let blockObject = try jsonObject(from: blockData)
                let blockDate = stringValue(at: ["extrinsics", "0", "args", "now"], in: blockObject)
                    .flatMap(dateFromSidecarTimestamp) ?? Date()

                let extrinsics = arrayValue(at: ["extrinsics"], in: blockObject)
                for extrinsic in extrinsics {
                    guard snapshots.count < limit else { break }
                    guard let pallet = stringValue(at: ["method", "pallet"], in: extrinsic)?.lowercased(),
                          let method = stringValue(at: ["method", "method"], in: extrinsic)?.lowercased(),
                          pallet == "balances",
                          method.contains("transfer"),
                          boolValue(at: ["success"], in: extrinsic) ?? true else {
                        continue
                    }

                    let toAddress = stringValue(at: ["method", "args", "dest", "id"], in: extrinsic)
                        ?? stringValue(at: ["method", "args", "dest"], in: extrinsic)
                    let fromAddress = stringValue(at: ["signature", "signer", "id"], in: extrinsic)
                        ?? stringValue(at: ["signature", "signer"], in: extrinsic)
                    guard let txHash = stringValue(at: ["hash"], in: extrinsic), !txHash.isEmpty else {
                        continue
                    }

                    let amountString = stringValue(at: ["method", "args", "value"], in: extrinsic)
                        ?? stringValue(at: ["method", "args", "amount"], in: extrinsic)
                        ?? "0"
                    let amountDecimal = decimalString(amountString) ?? 0
                    let amount = decimalToDouble(amountDecimal / dotDivisor)

                    if normalizedAddress(toAddress ?? "") == address {
                        snapshots.append(.init(transactionHash: txHash, kind: .receive, amount: amount, counterpartyAddress: fromAddress ?? "", createdAt: blockDate, status: .confirmed))
                    } else if normalizedAddress(fromAddress ?? "") == address {
                        snapshots.append(.init(transactionHash: txHash, kind: .send, amount: amount, counterpartyAddress: toAddress ?? "", createdAt: blockDate, status: .confirmed))
                    }
                }
            } catch {
                continue
            }
        }

        return snapshots.sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }

    private static func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func stringValue(at path: [String], in object: Any) -> String? {
        var current: Any? = object
        for component in path {
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any] {
                current = dictionary[component]
            } else {
                return nil
            }
        }
        if let text = current as? String { return text }
        if let number = current as? NSNumber { return number.stringValue }
        return nil
    }

    private static func arrayValue(at path: [String], in object: Any) -> [Any] {
        var current: Any? = object
        for component in path {
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any] {
                current = dictionary[component]
            } else {
                return []
            }
        }
        return current as? [Any] ?? []
    }

    private static func boolValue(at path: [String], in object: Any) -> Bool? {
        var current: Any? = object
        for component in path {
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any] {
                current = dictionary[component]
            } else {
                return nil
            }
        }
        return current as? Bool
    }

    private static func decimalString(_ text: String?) -> Decimal? {
        guard let text else { return nil }
        return Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func dateFromSidecarTimestamp(_ rawValue: String) -> Date? {
        if let milliseconds = Double(rawValue), milliseconds > 1_000 {
            return Date(timeIntervalSince1970: milliseconds / 1_000.0)
        }
        return iso8601Formatter.date(from: rawValue)
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
