import Foundation

extension DogecoinWalletEngine {
    static func fetchSpendableUTXOs(for address: String, networkMode: DogecoinNetworkMode) throws -> [DogecoinUTXO] {
        do {
            let utxos = sanitizeUTXOs(try fetchBlockCypherUTXOs(for: address, networkMode: networkMode))
            if !utxos.isEmpty {
                cacheUTXOs(utxos, for: address)
                return utxos
            }
            return cachedUTXOs(for: address) ?? []
        } catch {
            if let cached = cachedUTXOs(for: address) {
                return cached
            }
            throw DogecoinWalletEngineError.networkFailure(error.localizedDescription)
        }
    }

    static func sanitizeUTXOs(_ utxos: [DogecoinUTXO]) -> [DogecoinUTXO] {
        var deduped: [String: DogecoinUTXO] = [:]
        for utxo in utxos where utxo.value > 0 {
            let key = outpointKey(hash: utxo.transactionHash, index: utxo.index)
            if let existing = deduped[key] {
                deduped[key] = existing.value >= utxo.value ? existing : utxo
            } else {
                deduped[key] = utxo
            }
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            if lhs.transactionHash != rhs.transactionHash {
                return lhs.transactionHash < rhs.transactionHash
            }
            return lhs.index < rhs.index
        }
    }

    static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
    }

    static func blockcypherURL(path: String, networkMode: DogecoinNetworkMode) -> URL? {
        switch networkMode {
        case .mainnet:
            return BlockCypherProvider.url(path: path, network: .dogecoinMainnet)
        case .testnet:
            return BlockCypherProvider.url(path: path, network: .dogecoinTestnet)
        }
    }

    static func normalizedAddressCacheKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func cacheUTXOs(_ utxos: [DogecoinUTXO], for address: String) {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress[key] = CachedUTXOSet(utxos: utxos, updatedAt: Date())
    }

    static func cachedUTXOs(for address: String) -> [DogecoinUTXO]? {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        guard let cached = utxoCacheByAddress[key] else { return nil }
        guard Date().timeIntervalSince(cached.updatedAt) <= utxoCacheTTLSeconds else {
            utxoCacheByAddress[key] = nil
            return nil
        }
        return cached.utxos
    }

    static func fetchBlockCypherUTXOs(for address: String, networkMode: DogecoinNetworkMode) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let baseURL = blockcypherURL(path: "/addrs/\(encodedAddress)", networkMode: networkMode),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "unspentOnly", value: "true"),
            URLQueryItem(name: "includeScript", value: "true"),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components.url else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherProvider.AddressRefsResponse.self, from: data)
        let confirmed = payload.txrefs ?? []
        let pending = payload.unconfirmedTxrefs ?? []
        return (confirmed + pending).compactMap {
            guard let txOutputIndex = $0.txOutputIndex, let value = $0.value else { return nil }
            return DogecoinUTXO(transactionHash: $0.txHash, index: txOutputIndex, value: value)
        }
    }

    static func resolveNetworkFeeRateDOGEPerKB(
        feePriority: FeePriority,
        networkMode: DogecoinNetworkMode
    ) throws -> Double {
        let candidates = try fetchBlockCypherFeeRateCandidatesDOGEPerKB(networkMode: networkMode)
        let baseRate = candidates.sorted()[candidates.count / 2]
        let boundedRate = max(minRelayFeePerKB, min(baseRate, 10))
        return adjustedFeeRateDOGEPerKB(baseRate: boundedRate, feePriority: feePriority)
    }

    static func adjustedFeeRateDOGEPerKB(baseRate: Double, feePriority: FeePriority) -> Double {
        feePolicy.adjustedFeeRatePerKB(
            baseRate: baseRate,
            multiplier: UTXOFeePriorityMultiplierPolicy.multiplier(for: feePriority),
            maxRate: 25
        )
    }

    static func fetchBlockCypherFeeRateCandidatesDOGEPerKB(networkMode: DogecoinNetworkMode) throws -> [Double] {
        guard let url = blockcypherURL(path: "", networkMode: networkMode) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin network fee endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherProvider.NetworkFeesResponse.self, from: data)
        let candidates = [payload.lowFeePerKB, payload.mediumFeePerKB, payload.highFeePerKB]
            .compactMap { $0 }
            .map { $0 / koinuPerDOGE }
            .filter { $0 > 0 }

        guard !candidates.isEmpty else {
            throw DogecoinWalletEngineError.networkFailure("Fee-rate data was missing from BlockCypher.")
        }
        return candidates
    }

    static func performSynchronousRequest(
        _ request: URLRequest,
        timeout: TimeInterval = networkTimeoutSeconds,
        retries: Int = networkRetryCount
    ) throws -> Data {
        do {
            return try UTXOEngineSupport.performSynchronousRequest(
                request,
                timeout: timeout,
                retries: retries
            )
        } catch {
            throw DogecoinWalletEngineError.networkFailure(error.localizedDescription)
        }
    }
}
