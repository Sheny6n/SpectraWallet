import Foundation
private protocol SimpleAddressHistoryDiag {
    var address: String { get }
    var sourceUsed: String { get }
    var transactionCount: Int { get }
    var error: String? { get }
}
extension CardanoHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension XRPHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension StellarHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension MoneroHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension SuiHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension AptosHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension TONHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension ICPHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension NearHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension PolkadotHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension WalletStore {
    private func prettyJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) else { return nil }
        return sanitizeDiagnosticsString(string)
    }
    private func sanitizeDiagnosticsString(_ input: String) -> String {
        let knownWords = Set(BIP39EnglishWordList.words.map { $0.lowercased() })
        let mutable = NSMutableString(string: input)
        func replaceMatches(pattern: String, replacement: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let matches = regex.matches(in: mutable as String, range: NSRange(location: 0, length: mutable.length))
            for match in matches.sorted(by: { $0.range.location > $1.range.location }) {
                mutable.replaceCharacters(in: match.range, with: replacement)
            }}
        replaceMatches(pattern: #"\b(?:xprv|yprv|zprv|tprv|uprv|vprv)[1-9A-HJ-NP-Za-km-z]{32,}\b"#, replacement: "[REDACTED_EXTENDED_PRIVATE_KEY]")
        replaceMatches(pattern: #"\b(?:0x)?[A-Fa-f0-9]{64}\b"#, replacement: "[REDACTED_PRIVATE_KEY]")
        let wordPattern = #"\b[a-zA-Z]{2,}\b"#
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else { return mutable as String }
        let matches = regex.matches(in: mutable as String, range: NSRange(location: 0, length: mutable.length))
        guard !matches.isEmpty else { return mutable as String }
        let currentNSString = mutable
        var sequences: [[NSRange]] = []
        var current: [NSRange] = []
        for match in matches {
            let word = currentNSString.substring(with: match.range).lowercased()
            if knownWords.contains(word) { current.append(match.range) } else {
                if current.count >= 12 { sequences.append(current) }
                current.removeAll(keepingCapacity: true)
            }}
        if current.count >= 12 { sequences.append(current) }
        let replacementRanges = sequences.flatMap { $0 }.sorted { $0.location > $1.location }
        for range in replacementRanges { mutable.replaceCharacters(in: range, with: "[REDACTED_SEED_WORD]") }
        return mutable as String
    }
    private func evmDiagnosticsJSON(history: [UUID: EthereumTokenTransferHistoryDiagnostics], endpoints: [EthereumEndpointHealthResult], historyLastUpdatedAt: Date?, endpointsLastUpdatedAt: Date?, extra: [String: Any] = [:]) -> String? {
        let historyDicts = history.map { (walletID, item) in
            ["walletID": walletID.uuidString, "address": item.address, "rpcTransferCount": item.rpcTransferCount, "rpcError": item.rpcError ?? "", "blockscoutTransferCount": item.blockscoutTransferCount, "blockscoutError": item.blockscoutError ?? "", "etherscanTransferCount": item.etherscanTransferCount, "etherscanError": item.etherscanError ?? "", "ethplorerTransferCount": item.ethplorerTransferCount, "ethplorerError": item.ethplorerError ?? "", "sourceUsed": item.sourceUsed, "transferScanCount": item.transferScanCount, "decodedTransferCount": item.decodedTransferCount, "unsupportedTransferDropCount": item.unsupportedTransferDropCount, "decodingCompletenessRatio": item.decodingCompletenessRatio] as [String: Any]
        }
        let endpointDicts = endpoints.map { item in ["label": item.label, "endpoint": item.endpoint, "reachable": item.reachable, "statusCode": item.statusCode ?? -1, "detail": item.detail] as [String: Any] }
        var payload: [String: Any] = [
            "historyLastUpdatedAt": historyLastUpdatedAt?.timeIntervalSince1970 ?? 0, "endpointsLastUpdatedAt": endpointsLastUpdatedAt?.timeIntervalSince1970 ?? 0, "history": historyDicts, "endpoints": endpointDicts
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return prettyJSONString(from: payload)
    }
    private func utxoDiagnosticsJSON(history: [UUID: BitcoinHistoryDiagnostics], endpoints: [BitcoinEndpointHealthResult], historyLastUpdatedAt: Date?, endpointsLastUpdatedAt: Date?, extra: [String: Any] = [:]) -> String? {
        let historyDicts = history.values.map { item in ["walletID": item.walletID.uuidString, "identifier": item.identifier, "sourceUsed": item.sourceUsed, "transactionCount": item.transactionCount, "nextCursor": item.nextCursor ?? "", "error": item.error ?? ""] }
        let endpointDicts = endpoints.map { item in ["endpoint": item.endpoint, "reachable": item.reachable, "statusCode": item.statusCode ?? -1, "detail": item.detail] as [String: Any] }
        var payload: [String: Any] = [
            "historyLastUpdatedAt": historyLastUpdatedAt?.timeIntervalSince1970 ?? 0, "endpointsLastUpdatedAt": endpointsLastUpdatedAt?.timeIntervalSince1970 ?? 0, "history": historyDicts, "endpoints": endpointDicts
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return prettyJSONString(from: payload)
    }
    private func simpleAddressDiagnosticsJSON<T: SimpleAddressHistoryDiag>(
        history: [UUID: T], endpoints: [BitcoinEndpointHealthResult], historyLastUpdatedAt: Date?, endpointsLastUpdatedAt: Date?, extra: [String: Any] = [:]
    ) -> String? {
        let historyDicts = history.map { (walletID, item) in
            ["walletID": walletID.uuidString, "address": item.address, "sourceUsed": item.sourceUsed, "transactionCount": item.transactionCount, "error": item.error ?? ""] as [String: Any]
        }
        let endpointDicts = endpoints.map { item in ["endpoint": item.endpoint, "reachable": item.reachable, "statusCode": item.statusCode ?? -1, "detail": item.detail] as [String: Any] }
        var payload: [String: Any] = [
            "historyLastUpdatedAt": historyLastUpdatedAt?.timeIntervalSince1970 ?? 0, "endpointsLastUpdatedAt": endpointsLastUpdatedAt?.timeIntervalSince1970 ?? 0, "history": historyDicts, "endpoints": endpointDicts
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return prettyJSONString(from: payload)
    }
    func bitcoinDiagnosticsJSON() -> String? {
        utxoDiagnosticsJSON(
            history: bitcoinHistoryDiagnosticsByWallet, endpoints: bitcoinEndpointHealthResults, historyLastUpdatedAt: bitcoinHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: bitcoinEndpointHealthLastUpdatedAt, extra: ["networkMode": bitcoinNetworkMode.rawValue]
        )
    }
    func tronDiagnosticsJSON() -> String? {
        let history = tronHistoryDiagnosticsByWallet.map { (walletID, item) in
            ["walletID": walletID.uuidString, "address": item.address, "tronScanTxCount": item.tronScanTxCount, "tronScanTRC20Count": item.tronScanTRC20Count, "sourceUsed": item.sourceUsed, "error": item.error ?? ""] as [String: Any]
        }
        let endpoints = tronEndpointHealthResults.map { item in ["endpoint": item.endpoint, "reachable": item.reachable, "statusCode": item.statusCode ?? -1, "detail": item.detail] as [String: Any] }
        return prettyJSONString(from: [
            "historyLastUpdatedAt": tronHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0, "endpointsLastUpdatedAt": tronEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0, "lastSendErrorAt": tronLastSendErrorAt?.timeIntervalSince1970 ?? 0, "lastSendErrorDetails": tronLastSendErrorDetails ?? "", "history": history, "endpoints": endpoints
        ] as [String: Any])
    }
    func solanaDiagnosticsJSON() -> String? {
        let history = solanaHistoryDiagnosticsByWallet.map { (walletID, item) in
            ["walletID": walletID.uuidString, "address": item.address, "rpcCount": item.rpcCount, "sourceUsed": item.sourceUsed, "error": item.error ?? ""] as [String: Any]
        }
        let endpoints = solanaEndpointHealthResults.map { item in ["endpoint": item.endpoint, "reachable": item.reachable, "statusCode": item.statusCode ?? -1, "detail": item.detail] as [String: Any] }
        return prettyJSONString(from: [
            "historyLastUpdatedAt": solanaHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0, "endpointsLastUpdatedAt": solanaEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0, "history": history, "endpoints": endpoints
        ] as [String: Any])
    }
    func litecoinDiagnosticsJSON() -> String? {
        utxoDiagnosticsJSON(
            history: litecoinHistoryDiagnosticsByWallet, endpoints: litecoinEndpointHealthResults, historyLastUpdatedAt: litecoinHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: litecoinEndpointHealthLastUpdatedAt
        )
    }
    func dogecoinDiagnosticsJSON() -> String? {
        utxoDiagnosticsJSON(
            history: dogecoinHistoryDiagnosticsByWallet, endpoints: dogecoinEndpointHealthResults, historyLastUpdatedAt: dogecoinHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: dogecoinEndpointHealthLastUpdatedAt
        )
    }
    func bitcoinCashDiagnosticsJSON() -> String? {
        utxoDiagnosticsJSON(
            history: bitcoinCashHistoryDiagnosticsByWallet, endpoints: bitcoinCashEndpointHealthResults, historyLastUpdatedAt: bitcoinCashHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: bitcoinCashEndpointHealthLastUpdatedAt
        )
    }
    func bitcoinSVDiagnosticsJSON() -> String? {
        utxoDiagnosticsJSON(
            history: bitcoinSVHistoryDiagnosticsByWallet, endpoints: bitcoinSVEndpointHealthResults, historyLastUpdatedAt: bitcoinSVHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: bitcoinSVEndpointHealthLastUpdatedAt
        )
    }
    func ethereumDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: ethereumHistoryDiagnosticsByWallet, endpoints: ethereumEndpointHealthResults, historyLastUpdatedAt: ethereumHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: ethereumEndpointHealthLastUpdatedAt
        )
    }
    func bnbDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: bnbHistoryDiagnosticsByWallet, endpoints: bnbEndpointHealthResults, historyLastUpdatedAt: bnbHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: bnbEndpointHealthLastUpdatedAt
        )
    }
    func arbitrumDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: arbitrumHistoryDiagnosticsByWallet, endpoints: arbitrumEndpointHealthResults, historyLastUpdatedAt: arbitrumHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: arbitrumEndpointHealthLastUpdatedAt
        )
    }
    func optimismDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: optimismHistoryDiagnosticsByWallet, endpoints: optimismEndpointHealthResults, historyLastUpdatedAt: optimismHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: optimismEndpointHealthLastUpdatedAt
        )
    }
    func avalancheDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: avalancheHistoryDiagnosticsByWallet, endpoints: avalancheEndpointHealthResults, historyLastUpdatedAt: avalancheHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: avalancheEndpointHealthLastUpdatedAt
        )
    }
    func hyperliquidDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: hyperliquidHistoryDiagnosticsByWallet, endpoints: hyperliquidEndpointHealthResults, historyLastUpdatedAt: hyperliquidHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: hyperliquidEndpointHealthLastUpdatedAt
        )
    }
    func etcDiagnosticsJSON() -> String? {
        evmDiagnosticsJSON(
            history: etcHistoryDiagnosticsByWallet, endpoints: etcEndpointHealthResults, historyLastUpdatedAt: etcHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: etcEndpointHealthLastUpdatedAt
        )
    }
    func cardanoDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: cardanoHistoryDiagnosticsByWallet, endpoints: cardanoEndpointHealthResults, historyLastUpdatedAt: cardanoHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: cardanoEndpointHealthLastUpdatedAt
        )
    }
    func xrpDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: xrpHistoryDiagnosticsByWallet, endpoints: xrpEndpointHealthResults, historyLastUpdatedAt: xrpHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: xrpEndpointHealthLastUpdatedAt
        )
    }
    func stellarDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: stellarHistoryDiagnosticsByWallet, endpoints: stellarEndpointHealthResults, historyLastUpdatedAt: stellarHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: stellarEndpointHealthLastUpdatedAt
        )
    }
    func moneroDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: moneroHistoryDiagnosticsByWallet, endpoints: moneroEndpointHealthResults, historyLastUpdatedAt: moneroHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: moneroEndpointHealthLastUpdatedAt
        )
    }
    func suiDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: suiHistoryDiagnosticsByWallet, endpoints: suiEndpointHealthResults, historyLastUpdatedAt: suiHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: suiEndpointHealthLastUpdatedAt
        )
    }
    func aptosDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: aptosHistoryDiagnosticsByWallet, endpoints: aptosEndpointHealthResults, historyLastUpdatedAt: aptosHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: aptosEndpointHealthLastUpdatedAt
        )
    }
    func tonDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: tonHistoryDiagnosticsByWallet, endpoints: tonEndpointHealthResults, historyLastUpdatedAt: tonHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: tonEndpointHealthLastUpdatedAt
        )
    }
    func icpDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: icpHistoryDiagnosticsByWallet, endpoints: icpEndpointHealthResults, historyLastUpdatedAt: icpHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: icpEndpointHealthLastUpdatedAt
        )
    }
    func nearDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: nearHistoryDiagnosticsByWallet, endpoints: nearEndpointHealthResults, historyLastUpdatedAt: nearHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: nearEndpointHealthLastUpdatedAt
        )
    }
    func polkadotDiagnosticsJSON() -> String? {
        simpleAddressDiagnosticsJSON(
            history: polkadotHistoryDiagnosticsByWallet, endpoints: polkadotEndpointHealthResults, historyLastUpdatedAt: polkadotHistoryDiagnosticsLastUpdatedAt, endpointsLastUpdatedAt: polkadotEndpointHealthLastUpdatedAt
        )
    }
    func exportDiagnosticsBundle() throws -> URL {
        let payload = buildDiagnosticsBundlePayload()
        let data = try Self.diagnosticsBundleEncoder.encode(payload)
        let stamp = Self.exportFilenameTimestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = try diagnosticsBundleExportsDirectoryURL().appendingPathComponent("spectra-diagnostics-\(stamp)").appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
    func diagnosticsBundleExportsDirectoryURL() throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("Diagnostics Bundles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func diagnosticsBundleExportURLs() -> [URL] {
        guard let directory = try? diagnosticsBundleExportsDirectoryURL(), let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return urls.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }}
    func deleteDiagnosticsBundleExport(at url: URL) throws { try FileManager.default.removeItem(at: url) }
    @discardableResult
    func importDiagnosticsBundle(from url: URL) throws -> DiagnosticsBundlePayload {
        let data = try Data(contentsOf: url)
        let payload = try Self.diagnosticsBundleDecoder.decode(DiagnosticsBundlePayload.self, from: data)
        lastImportedDiagnosticsBundle = payload
        return payload
    }
    private func buildDiagnosticsBundlePayload() -> DiagnosticsBundlePayload {
        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion = (info["CFBundleShortVersionString"] as? String) ?? "unknown"
        let buildNumber = (info["CFBundleVersion"] as? String) ?? "unknown"
        let metadata = DiagnosticsEnvironmentMetadata(
            appVersion: appVersion, buildNumber: buildNumber, osVersion: ProcessInfo.processInfo.operatingSystemVersionString, localeIdentifier: Locale.current.identifier, timeZoneIdentifier: TimeZone.current.identifier, pricingProvider: pricingProvider.rawValue, selectedFiatCurrency: selectedFiatCurrency.rawValue, walletCount: wallets.count, transactionCount: transactions.count
        )
        return DiagnosticsBundlePayload(
            schemaVersion: 1, generatedAt: Date(), environment: metadata, chainDegradedMessages: diagnostics.chainDegradedMessages, bitcoinDiagnosticsJSON: bitcoinDiagnosticsJSON() ?? "{}", bitcoinSVDiagnosticsJSON: bitcoinSVDiagnosticsJSON() ?? "{}", litecoinDiagnosticsJSON: litecoinDiagnosticsJSON() ?? "{}", ethereumDiagnosticsJSON: ethereumDiagnosticsJSON() ?? "{}", arbitrumDiagnosticsJSON: arbitrumDiagnosticsJSON() ?? "{}", optimismDiagnosticsJSON: optimismDiagnosticsJSON() ?? "{}", bnbDiagnosticsJSON: bnbDiagnosticsJSON() ?? "{}", avalancheDiagnosticsJSON: avalancheDiagnosticsJSON() ?? "{}", hyperliquidDiagnosticsJSON: hyperliquidDiagnosticsJSON() ?? "{}", tronDiagnosticsJSON: tronDiagnosticsJSON() ?? "{}", solanaDiagnosticsJSON: solanaDiagnosticsJSON() ?? "{}", stellarDiagnosticsJSON: stellarDiagnosticsJSON() ?? "{}"
        )
    }
}
