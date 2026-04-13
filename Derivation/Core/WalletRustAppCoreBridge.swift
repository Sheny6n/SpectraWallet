import Foundation
enum WalletRustAppCoreBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case invalidPayload(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain): return "The Rust app core does not support \(chain) yet."
        case .rustCoreReturnedNullResponse: return "The Rust app core returned an empty response."
        case .rustCoreFailed(let message): return message
        case .invalidPayload(let message): return message
        }}
}
private extension Data {
    func asJSONString() throws -> String {
        guard let json = String(data: self, encoding: .utf8) else { throw WalletRustAppCoreBridgeError.invalidPayload("Payload was not valid UTF-8 JSON.") }
        return json
    }
}
private struct WalletRustDerivationPathResolutionPayload: Decodable {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: String
}
private struct WalletRustSeedDerivationPathsPayload: Decodable {
    let isCustomEnabled: Bool
    let bitcoin: String
    let bitcoinCash: String
    let bitcoinSV: String
    let litecoin: String
    let dogecoin: String
    let ethereum: String
    let ethereumClassic: String
    let arbitrum: String
    let optimism: String
    let avalanche: String
    let hyperliquid: String
    let tron: String
    let solana: String
    let stellar: String
    let xrp: String
    let cardano: String
    let sui: String
    let aptos: String
    let ton: String
    let internetComputer: String
    let near: String
    let polkadot: String
    var model: SeedDerivationPaths {
        SeedDerivationPaths(
            isCustomEnabled: isCustomEnabled, bitcoin: bitcoin, bitcoinCash: bitcoinCash, bitcoinSV: bitcoinSV, litecoin: litecoin, dogecoin: dogecoin, ethereum: ethereum, ethereumClassic: ethereumClassic, arbitrum: arbitrum, optimism: optimism, avalanche: avalanche, hyperliquid: hyperliquid, tron: tron, solana: solana, stellar: stellar, xrp: xrp, cardano: cardano, sui: sui, aptos: aptos, ton: ton, internetComputer: internetComputer, near: near, polkadot: polkadot
        )
    }
}
enum WalletRustAppCoreBridge {
    static func migrateLegacyWalletStoreData(_ data: Data) throws -> Data { try decodeJSONStringToData(try coreMigrateLegacyWalletStoreJson(requestJson: data.asJSONString())) }
    static func exportLegacyWalletStoreData(fromCoreStateData data: Data) throws -> Data { try decodeJSONStringToData(try coreExportLegacyWalletStoreJson(requestJson: data.asJSONString())) }
    static func buildPersistedSnapshotData(appStateData: Data, secretObservations: [WalletRustSecretObservation]) throws -> Data {
        guard let appStateJSON = String(data: appStateData, encoding: .utf8) else { throw WalletRustAppCoreBridgeError.invalidPayload("Core state payload was not valid UTF-8 JSON.") }
        let request = WalletRustPersistedSnapshotBuildRequest(appStateJSON: appStateJSON, secretObservations: secretObservations)
        return try decodeJSONStringToData(try coreBuildPersistedSnapshotJson(requestJson: encodeJSONString(request)))
    }
    static func walletSecretIndex(fromCoreSnapshotData data: Data) throws -> WalletRustWalletSecretIndex { try decodePayload(WalletRustWalletSecretIndex.self, json: try coreWalletSecretIndexJson(requestJson: data.asJSONString())) }
    static func planWalletImport(_ request: WalletRustImportPlanRequest) throws -> WalletRustImportPlan { try decodePayload(WalletRustImportPlan.self, json: try corePlanWalletImportJson(requestJson: encodeJSONString(request))) }
    static func activeMaintenancePlan(_ request: WalletRustActiveMaintenancePlanRequest) throws -> WalletRustActiveMaintenancePlan { try sendCoreJSONRequest(request, decode: WalletRustActiveMaintenancePlan.self, invoke: coreActiveMaintenancePlanJson) }
    static func shouldRunBackgroundMaintenance(_ request: WalletRustBackgroundMaintenanceRequest) throws -> Bool { try sendCoreJSONRequest(request, decode: Bool.self, invoke: coreShouldRunBackgroundMaintenanceJson) }
    static func chainRefreshPlans(_ request: WalletRustChainRefreshPlanRequest) throws -> [WalletRustChainRefreshPlan] { try sendCoreJSONRequest(request, decode: [WalletRustChainRefreshPlan].self, invoke: coreChainRefreshPlansJson) }
    static func historyRefreshPlans(_ request: WalletRustHistoryRefreshPlanRequest) throws -> [String] { try sendCoreJSONRequest(request, decode: [String].self, invoke: coreHistoryRefreshPlansJson) }
    static func normalizeHistory(_ request: WalletRustNormalizeHistoryRequest) throws -> [WalletRustNormalizedHistoryEntry] { try sendCoreJSONRequest(request, decode: [WalletRustNormalizedHistoryEntry].self, invoke: coreNormalizeHistoryJson) }
    static func mergeBitcoinHistorySnapshots(_ request: WalletRustMergeBitcoinHistorySnapshotsRequest) throws -> [WalletRustBitcoinHistorySnapshotPayload] {
        try sendCoreJSONRequest(
            request, decode: [WalletRustBitcoinHistorySnapshotPayload].self, invoke: coreMergeBitcoinHistorySnapshotsJson
        )
    }
    static func planEVMRefreshTargets(_ request: WalletRustEVMRefreshTargetsRequest) throws -> WalletRustEVMRefreshPlan { try sendCoreJSONRequest(request, decode: WalletRustEVMRefreshPlan.self, invoke: corePlanEvmRefreshTargetsJson) }
    static func planDogecoinRefreshTargets(_ request: WalletRustDogecoinRefreshTargetsRequest) throws -> [WalletRustDogecoinRefreshWalletTarget] { try sendCoreJSONRequest(request, decode: [WalletRustDogecoinRefreshWalletTarget].self, invoke: corePlanDogecoinRefreshTargetsJson) }
    static func planTransferAvailability(_ request: WalletRustTransferAvailabilityRequest) throws -> WalletRustTransferAvailabilityPlan { try sendCoreJSONRequest(request, decode: WalletRustTransferAvailabilityPlan.self, invoke: corePlanTransferAvailabilityJson) }
    static func planStoreDerivedState(_ request: WalletRustStoreDerivedStateRequest) throws -> WalletRustStoreDerivedStatePlan { try sendCoreJSONRequest(request, decode: WalletRustStoreDerivedStatePlan.self, invoke: corePlanStoreDerivedStateJson) }
    static func aggregateOwnedAddresses(_ request: WalletRustOwnedAddressAggregationRequest) throws -> [String] { try sendCoreJSONRequest(request, decode: [String].self, invoke: coreAggregateOwnedAddressesJson) }
    static func planReceiveSelection(_ request: WalletRustReceiveSelectionRequest) throws -> WalletRustReceiveSelectionPlan { try sendCoreJSONRequest(request, decode: WalletRustReceiveSelectionPlan.self, invoke: corePlanReceiveSelectionJson) }
    static func planSelfSendConfirmation(_ request: WalletRustSelfSendConfirmationRequest) throws -> WalletRustSelfSendConfirmationPlan { try sendCoreJSONRequest(request, decode: WalletRustSelfSendConfirmationPlan.self, invoke: corePlanSelfSendConfirmationJson) }
    static func planSendPreviewRouting(_ request: WalletRustSendPreviewRoutingRequest) throws -> WalletRustSendPreviewRoutingPlan { try sendCoreJSONRequest(request, decode: WalletRustSendPreviewRoutingPlan.self, invoke: corePlanSendPreviewRoutingJson) }
    static func planSendSubmitPreflight(_ request: WalletRustSendSubmitPreflightRequest) throws -> WalletRustSendSubmitPreflightPlan { try sendCoreJSONRequest(request, decode: WalletRustSendSubmitPreflightPlan.self, invoke: corePlanSendSubmitPreflightJson) }
    static func mergeTransactions(_ request: WalletRustTransactionMergeRequest) throws -> [WalletRustTransactionRecord] { try sendCoreJSONRequest(request, decode: [WalletRustTransactionRecord].self, invoke: coreMergeTransactionsJson) }
    static func chainPresets() throws -> [WalletDerivationChainPreset] { try decodePayload([WalletDerivationChainPreset].self, json: try appCoreChainPresetsJson()) }
    static func requestCompilationPresets() throws -> [WalletDerivationRequestCompilationPreset] { try decodePayload([WalletDerivationRequestCompilationPreset].self, json: try appCoreRequestCompilationPresetsJson()) }
    static func derivationPaths(for preset: SeedDerivationPreset?) throws -> SeedDerivationPaths {
        let accountIndex = preset?.accountIndex ?? 0
        let payload = try decodePayload(WalletRustSeedDerivationPathsPayload.self, json: try appCoreDerivationPathsForPresetJson(accountIndex: accountIndex))
        return payload.model
    }
    static func resolve(chain: SeedDerivationChain, path: String) throws -> WalletRustResolvedDerivationPath {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else { throw WalletRustAppCoreBridgeError.rustCoreUnsupportedChain(chain.rawValue) }
        let payload = try decodePayload(
            WalletRustDerivationPathResolutionPayload.self, json: try appCoreResolveDerivationPathJson(chain: ffiChain.rawValue, derivationPath: path)
        )
        return WalletRustResolvedDerivationPath(
            chain: payload.chain, normalizedPath: payload.normalizedPath, accountIndex: payload.accountIndex, flavor: SeedDerivationFlavor(rawValue: payload.flavor) ?? .standard
        )
    }
    private static func decodePayload<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        guard let payload = json.data(using: .utf8), !payload.isEmpty else { throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core returned an empty payload.") }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustAppCoreBridgeError.invalidPayload(error.localizedDescription)
        }}
    private static func sendCoreJSONRequest<Request: Encodable, Response: Decodable>(
        _ request: Request, decode responseType: Response.Type, invoke: @escaping (String) throws -> String
    ) throws -> Response {
        try decodePayload(responseType, json: try invoke(encodeJSONString(request)))
    }
    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { throw WalletRustAppCoreBridgeError.invalidPayload("Encoded request was not valid UTF-8 JSON.") }
        return json
    }
    private static func decodeJSONStringToData(_ json: String) throws -> Data {
        guard let data = json.data(using: .utf8) else { throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core payload was not valid UTF-8.") }
        return data
    }
}
