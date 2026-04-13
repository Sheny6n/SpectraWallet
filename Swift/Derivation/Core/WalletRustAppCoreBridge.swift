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
        }
    }
}

private extension Data {
    func asJSONString() throws -> String {
        guard let json = String(data: self, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Payload was not valid UTF-8 JSON.")
        }
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
            isCustomEnabled: isCustomEnabled, bitcoin: bitcoin, bitcoinCash: bitcoinCash,
            bitcoinSV: bitcoinSV, litecoin: litecoin, dogecoin: dogecoin, ethereum: ethereum,
            ethereumClassic: ethereumClassic, arbitrum: arbitrum, optimism: optimism,
            avalanche: avalanche, hyperliquid: hyperliquid, tron: tron, solana: solana,
            stellar: stellar, xrp: xrp, cardano: cardano, sui: sui, aptos: aptos, ton: ton,
            internetComputer: internetComputer, near: near, polkadot: polkadot
        )
    }
}

enum WalletRustAppCoreBridge {

    // ─── Persistence boundary (state inherently lives as JSON on disk) ────────

    static func migrateLegacyWalletStoreData(_ data: Data) throws -> Data {
        try decodeJSONStringToData(try coreMigrateLegacyWalletStoreJson(requestJson: data.asJSONString()))
    }

    static func exportLegacyWalletStoreData(fromCoreStateData data: Data) throws -> Data {
        try decodeJSONStringToData(try coreExportLegacyWalletStoreJson(requestJson: data.asJSONString()))
    }

    static func buildPersistedSnapshotData(appStateData: Data, secretObservations: [WalletRustSecretObservation]) throws -> Data {
        guard let appStateJSON = String(data: appStateData, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Core state payload was not valid UTF-8 JSON.")
        }
        let request = WalletRustPersistedSnapshotBuildRequest(appStateJSON: appStateJSON, secretObservations: secretObservations)
        return try decodeJSONStringToData(try coreBuildPersistedSnapshotJson(requestJson: encodeJSONString(request)))
    }

    static func walletSecretIndex(fromCoreSnapshotData data: Data) throws -> WalletRustWalletSecretIndex {
        try decodePayload(WalletRustWalletSecretIndex.self, json: try coreWalletSecretIndexJson(snapshotJson: data.asJSONString()))
    }

    // ─── Typed bridge functions ───────────────────────────────────────────────

    static func planWalletImport(_ request: WalletRustImportPlanRequest) throws -> WalletRustImportPlan {
        let plan = try corePlanWalletImport(request: request.toFFI())
        return plan.toWalletRust()
    }

    static func activeMaintenancePlan(_ request: WalletRustActiveMaintenancePlanRequest) -> WalletRustActiveMaintenancePlan {
        let plan = coreActiveMaintenancePlan(request: request.toFFI())
        return WalletRustActiveMaintenancePlan(
            refreshPendingTransactions: plan.refreshPendingTransactions,
            refreshLivePrices: plan.refreshLivePrices
        )
    }

    static func shouldRunBackgroundMaintenance(_ request: WalletRustBackgroundMaintenanceRequest) -> Bool {
        coreShouldRunBackgroundMaintenance(request: request.toFFI())
    }

    static func chainRefreshPlans(_ request: WalletRustChainRefreshPlanRequest) -> [WalletRustChainRefreshPlan] {
        coreChainRefreshPlans(request: request.toFFI()).map { $0.toWalletRust() }
    }

    static func historyRefreshPlans(_ request: WalletRustHistoryRefreshPlanRequest) -> [String] {
        coreHistoryRefreshPlans(request: request.toFFI())
    }

    static func normalizeHistory(_ request: WalletRustNormalizeHistoryRequest) -> [WalletRustNormalizedHistoryEntry] {
        coreNormalizeHistory(request: request.toFFI()).map { $0.toWalletRust() }
    }

    static func mergeBitcoinHistorySnapshots(_ request: WalletRustMergeBitcoinHistorySnapshotsRequest) -> [WalletRustBitcoinHistorySnapshotPayload] {
        coreMergeBitcoinHistorySnapshots(request: request.toFFI()).map { $0.toWalletRust() }
    }

    static func planEVMRefreshTargets(_ request: WalletRustEVMRefreshTargetsRequest) -> WalletRustEVMRefreshPlan {
        let plan = corePlanEvmRefreshTargets(request: request.toFFI())
        return WalletRustEVMRefreshPlan(
            walletTargets: plan.walletTargets.map { $0.toWalletRust() },
            groupedTargets: plan.groupedTargets.map { $0.toWalletRust() }
        )
    }

    static func planDogecoinRefreshTargets(_ request: WalletRustDogecoinRefreshTargetsRequest) -> [WalletRustDogecoinRefreshWalletTarget] {
        corePlanDogecoinRefreshTargets(request: request.toFFI()).map { $0.toWalletRust() }
    }

    static func planTransferAvailability(_ request: WalletRustTransferAvailabilityRequest) -> WalletRustTransferAvailabilityPlan {
        let plan = corePlanTransferAvailability(request: request.toFFI())
        return plan.toWalletRust()
    }

    static func planStoreDerivedState(_ request: WalletRustStoreDerivedStateRequest) -> WalletRustStoreDerivedStatePlan {
        let plan = corePlanStoreDerivedState(request: request.toFFI())
        return plan.toWalletRust()
    }

    static func aggregateOwnedAddresses(_ request: WalletRustOwnedAddressAggregationRequest) -> [String] {
        coreAggregateOwnedAddresses(request: OwnedAddressAggregationRequest(candidateAddresses: request.candidateAddresses))
    }

    static func planReceiveSelection(_ request: WalletRustReceiveSelectionRequest) -> WalletRustReceiveSelectionPlan {
        let plan = corePlanReceiveSelection(request: request.toFFI())
        return WalletRustReceiveSelectionPlan(
            resolvedChainName: plan.resolvedChainName,
            selectedReceiveHoldingIndex: plan.selectedReceiveHoldingIndex.map { Int($0) }
        )
    }

    static func planSelfSendConfirmation(_ request: WalletRustSelfSendConfirmationRequest) -> WalletRustSelfSendConfirmationPlan {
        let plan = corePlanSelfSendConfirmation(request: request.toFFI())
        return WalletRustSelfSendConfirmationPlan(
            requiresConfirmation: plan.requiresConfirmation,
            consumeExistingConfirmation: plan.consumeExistingConfirmation,
            clearPendingConfirmation: plan.clearPendingConfirmation
        )
    }

    static func planSendPreviewRouting(_ request: WalletRustSendPreviewRoutingRequest) -> WalletRustSendPreviewRoutingPlan {
        let plan = corePlanSendPreviewRouting(request: request.toFFI())
        return WalletRustSendPreviewRoutingPlan(activePreviewKind: plan.activePreviewKind)
    }

    static func planSendSubmitPreflight(_ request: WalletRustSendSubmitPreflightRequest) throws -> WalletRustSendSubmitPreflightPlan {
        let plan = try corePlanSendSubmitPreflight(request: request.toFFI())
        return WalletRustSendSubmitPreflightPlan(
            submitKind: plan.submitKind,
            previewKind: plan.previewKind,
            normalizedDestinationAddress: plan.normalizedDestinationAddress,
            amount: plan.amount,
            chainName: plan.chainName,
            symbol: plan.symbol,
            nativeEVMSymbol: plan.nativeEvmSymbol,
            isNativeEVMAsset: plan.isNativeEvmAsset,
            allowsZeroAmount: plan.allowsZeroAmount
        )
    }

    static func mergeTransactions(_ request: WalletRustTransactionMergeRequest) -> [WalletRustTransactionRecord] {
        coreMergeTransactions(request: request.toFFI()).map { $0.toWalletRust() }
    }

    // ─── Derivation bridge (unchanged — calls derivation FFI, not core) ────────

    static func chainPresets() throws -> [WalletDerivationChainPreset] {
        try decodePayload([WalletDerivationChainPreset].self, json: try appCoreChainPresetsJson())
    }

    static func requestCompilationPresets() throws -> [WalletDerivationRequestCompilationPreset] {
        try decodePayload([WalletDerivationRequestCompilationPreset].self, json: try appCoreRequestCompilationPresetsJson())
    }

    static func derivationPaths(for preset: SeedDerivationPreset?) throws -> SeedDerivationPaths {
        let accountIndex = preset?.accountIndex ?? 0
        let payload = try decodePayload(WalletRustSeedDerivationPathsPayload.self, json: try appCoreDerivationPathsForPresetJson(accountIndex: accountIndex))
        return payload.model
    }

    static func resolve(chain: SeedDerivationChain, path: String) throws -> WalletRustResolvedDerivationPath {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustAppCoreBridgeError.rustCoreUnsupportedChain(chain.rawValue)
        }
        let payload = try decodePayload(
            WalletRustDerivationPathResolutionPayload.self,
            json: try appCoreResolveDerivationPathJson(chain: ffiChain.rawValue, derivationPath: path)
        )
        return WalletRustResolvedDerivationPath(
            chain: payload.chain, normalizedPath: payload.normalizedPath,
            accountIndex: payload.accountIndex, flavor: SeedDerivationFlavor(rawValue: payload.flavor) ?? .standard
        )
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static func decodePayload<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        guard let payload = json.data(using: .utf8), !payload.isEmpty else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core returned an empty payload.")
        }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustAppCoreBridgeError.invalidPayload(error.localizedDescription)
        }
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Encoded request was not valid UTF-8 JSON.")
        }
        return json
    }

    private static func decodeJSONStringToData(_ json: String) throws -> Data {
        guard let data = json.data(using: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core payload was not valid UTF-8.")
        }
        return data
    }
}

// ─── WalletRust* → UniFFI conversion extensions ───────────────────────────────

private extension WalletRustImportAddresses {
    func toFFI() -> WalletImportAddresses {
        WalletImportAddresses(
            bitcoinAddress: bitcoinAddress, bitcoinXpub: bitcoinXpub,
            bitcoinCashAddress: bitcoinCashAddress, bitcoinSvAddress: bitcoinSVAddress,
            litecoinAddress: litecoinAddress, dogecoinAddress: dogecoinAddress,
            ethereumAddress: ethereumAddress, ethereumClassicAddress: ethereumClassicAddress,
            tronAddress: tronAddress, solanaAddress: solanaAddress,
            xrpAddress: xrpAddress, stellarAddress: stellarAddress,
            moneroAddress: moneroAddress, cardanoAddress: cardanoAddress,
            suiAddress: suiAddress, aptosAddress: aptosAddress,
            tonAddress: tonAddress, icpAddress: icpAddress,
            nearAddress: nearAddress, polkadotAddress: polkadotAddress
        )
    }
}

private extension WalletImportAddresses {
    func toWalletRust() -> WalletRustImportAddresses {
        WalletRustImportAddresses(
            bitcoinAddress: bitcoinAddress, bitcoinXpub: bitcoinXpub,
            bitcoinCashAddress: bitcoinCashAddress, bitcoinSVAddress: bitcoinSvAddress,
            litecoinAddress: litecoinAddress, dogecoinAddress: dogecoinAddress,
            ethereumAddress: ethereumAddress, ethereumClassicAddress: ethereumClassicAddress,
            tronAddress: tronAddress, solanaAddress: solanaAddress,
            xrpAddress: xrpAddress, stellarAddress: stellarAddress,
            moneroAddress: moneroAddress, cardanoAddress: cardanoAddress,
            suiAddress: suiAddress, aptosAddress: aptosAddress,
            tonAddress: tonAddress, icpAddress: icpAddress,
            nearAddress: nearAddress, polkadotAddress: polkadotAddress
        )
    }
}

private extension WalletRustWatchOnlyEntries {
    func toFFI() -> WalletImportWatchOnlyEntries {
        WalletImportWatchOnlyEntries(
            bitcoinAddresses: bitcoinAddresses, bitcoinXpub: bitcoinXpub,
            bitcoinCashAddresses: bitcoinCashAddresses, bitcoinSvAddresses: bitcoinSVAddresses,
            litecoinAddresses: litecoinAddresses, dogecoinAddresses: dogecoinAddresses,
            ethereumAddresses: ethereumAddresses, tronAddresses: tronAddresses,
            solanaAddresses: solanaAddresses, xrpAddresses: xrpAddresses,
            stellarAddresses: stellarAddresses, cardanoAddresses: cardanoAddresses,
            suiAddresses: suiAddresses, aptosAddresses: aptosAddresses,
            tonAddresses: tonAddresses, icpAddresses: icpAddresses,
            nearAddresses: nearAddresses, polkadotAddresses: polkadotAddresses
        )
    }
}

private extension WalletRustImportPlanRequest {
    func toFFI() -> WalletImportRequest {
        WalletImportRequest(
            walletName: walletName,
            defaultWalletNameStartIndex: UInt64(defaultWalletNameStartIndex),
            primarySelectedChainName: primarySelectedChainName,
            selectedChainNames: selectedChainNames,
            plannedWalletIds: plannedWalletIDs,
            isWatchOnlyImport: isWatchOnlyImport,
            isPrivateKeyImport: isPrivateKeyImport,
            hasWalletPassword: hasWalletPassword,
            resolvedAddresses: resolvedAddresses.toFFI(),
            watchOnlyEntries: watchOnlyEntries.toFFI()
        )
    }
}

private extension WalletImportPlan {
    func toWalletRust() -> WalletRustImportPlan {
        WalletRustImportPlan(
            secretKind: secretKind,
            wallets: wallets.map { $0.toWalletRust() },
            secretInstructions: secretInstructions.map { $0.toWalletRust() }
        )
    }
}

private extension PlannedWallet {
    func toWalletRust() -> WalletRustPlannedWallet {
        WalletRustPlannedWallet(
            walletID: walletId, name: name, chainName: chainName,
            addresses: addresses.toWalletRust()
        )
    }
}

private extension WalletSecretInstruction {
    func toWalletRust() -> WalletRustSecretInstruction {
        WalletRustSecretInstruction(
            walletID: walletId, secretKind: secretKind,
            shouldStoreSeedPhrase: shouldStoreSeedPhrase,
            shouldStorePrivateKey: shouldStorePrivateKey,
            shouldStorePasswordVerifier: shouldStorePasswordVerifier
        )
    }
}

private extension WalletRustActiveMaintenancePlanRequest {
    func toFFI() -> ActiveMaintenancePlanRequest {
        ActiveMaintenancePlanRequest(
            nowUnix: nowUnix,
            lastPendingTransactionRefreshAtUnix: lastPendingTransactionRefreshAtUnix,
            lastLivePriceRefreshAtUnix: lastLivePriceRefreshAtUnix,
            hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork,
            shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh,
            pendingRefreshInterval: pendingRefreshInterval,
            priceRefreshInterval: priceRefreshInterval
        )
    }
}

private extension WalletRustBackgroundMaintenanceRequest {
    func toFFI() -> BackgroundMaintenanceRequest {
        BackgroundMaintenanceRequest(
            nowUnix: nowUnix,
            isNetworkReachable: isNetworkReachable,
            lastBackgroundMaintenanceAtUnix: lastBackgroundMaintenanceAtUnix,
            interval: interval
        )
    }
}

private extension WalletRustChainRefreshPlanRequest {
    func toFFI() -> ChainRefreshPlanRequest {
        ChainRefreshPlanRequest(
            chainIds: chainIDs,
            nowUnix: nowUnix,
            forceChainRefresh: forceChainRefresh,
            includeHistoryRefreshes: includeHistoryRefreshes,
            historyRefreshInterval: historyRefreshInterval,
            pendingTransactionMaintenanceChainIds: pendingTransactionMaintenanceChainIDs,
            degradedChainIds: degradedChainIDs,
            lastGoodChainSyncById: lastGoodChainSyncByID,
            lastHistoryRefreshAtByChainId: lastHistoryRefreshAtByChainID,
            automaticChainRefreshStalenessInterval: automaticChainRefreshStalenessInterval
        )
    }
}

private extension ChainRefreshPlan {
    func toWalletRust() -> WalletRustChainRefreshPlan {
        WalletRustChainRefreshPlan(chainID: chainId, chainName: chainName, refreshHistory: refreshHistory)
    }
}

private extension WalletRustHistoryRefreshPlanRequest {
    func toFFI() -> HistoryRefreshPlanRequest {
        HistoryRefreshPlanRequest(
            chainIds: chainIDs,
            nowUnix: nowUnix,
            interval: interval,
            lastHistoryRefreshAtByChainId: lastHistoryRefreshAtByChainID
        )
    }
}

private extension WalletRustHistoryWallet {
    func toFFI() -> HistoryWallet {
        HistoryWallet(walletId: walletID, selectedChain: selectedChain)
    }
}

private extension WalletRustHistoryTransaction {
    func toFFI() -> HistoryTransaction {
        HistoryTransaction(
            id: id, walletId: walletID, kind: kind, status: status,
            walletName: walletName, assetName: assetName, symbol: symbol,
            chainName: chainName, address: address, transactionHash: transactionHash,
            transactionHistorySource: transactionHistorySource, createdAtUnix: createdAtUnix
        )
    }
}

private extension WalletRustNormalizeHistoryRequest {
    func toFFI() -> NormalizeHistoryRequest {
        NormalizeHistoryRequest(
            wallets: wallets.map { $0.toFFI() },
            transactions: transactions.map { $0.toFFI() },
            unknownLabel: unknownLabel
        )
    }
}

private extension NormalizedHistoryEntry {
    func toWalletRust() -> WalletRustNormalizedHistoryEntry {
        WalletRustNormalizedHistoryEntry(
            id: id, transactionID: transactionId, dedupeKey: dedupeKey,
            createdAtUnix: createdAtUnix, kind: kind, status: status,
            walletName: walletName, assetName: assetName, symbol: symbol,
            chainName: chainName, address: address, transactionHash: transactionHash,
            sourceTag: sourceTag, providerCount: Int(providerCount), searchIndex: searchIndex
        )
    }
}

private extension WalletRustBitcoinHistorySnapshotPayload {
    func toFFI() -> BitcoinHistorySnapshot {
        BitcoinHistorySnapshot(
            txid: txid, amountBtc: amountBTC, kind: kind, status: status,
            counterpartyAddress: counterpartyAddress,
            blockHeight: blockHeight.map { Int64($0) },
            createdAtUnix: createdAtUnix
        )
    }
}

private extension BitcoinHistorySnapshot {
    func toWalletRust() -> WalletRustBitcoinHistorySnapshotPayload {
        WalletRustBitcoinHistorySnapshotPayload(
            txid: txid, amountBTC: amountBtc, kind: kind, status: status,
            counterpartyAddress: counterpartyAddress,
            blockHeight: blockHeight.map { Int($0) },
            createdAtUnix: createdAtUnix
        )
    }
}

private extension WalletRustMergeBitcoinHistorySnapshotsRequest {
    func toFFI() -> MergeBitcoinHistorySnapshotsRequest {
        MergeBitcoinHistorySnapshotsRequest(
            snapshots: snapshots.map { $0.toFFI() },
            ownedAddresses: ownedAddresses,
            limit: UInt64(limit)
        )
    }
}

private extension WalletRustEVMRefreshWalletInput {
    func toFFI() -> EvmRefreshWalletInput {
        EvmRefreshWalletInput(
            index: UInt64(index), walletId: walletID,
            selectedChain: selectedChain, address: address
        )
    }
}

private extension WalletRustEVMRefreshTargetsRequest {
    func toFFI() -> EvmRefreshTargetsRequest {
        EvmRefreshTargetsRequest(
            chainName: chainName,
            wallets: wallets.map { $0.toFFI() },
            allowedWalletIds: allowedWalletIDs,
            groupByNormalizedAddress: groupByNormalizedAddress
        )
    }
}

private extension EvmRefreshWalletTarget {
    func toWalletRust() -> WalletRustEVMRefreshWalletTarget {
        WalletRustEVMRefreshWalletTarget(
            index: Int(index), walletID: walletId,
            address: address, normalizedAddress: normalizedAddress
        )
    }
}

private extension EvmGroupedTarget {
    func toWalletRust() -> WalletRustEVMGroupedTarget {
        WalletRustEVMGroupedTarget(
            walletIDs: walletIds, address: address, normalizedAddress: normalizedAddress
        )
    }
}

private extension WalletRustDogecoinRefreshWalletInput {
    func toFFI() -> DogecoinRefreshWalletInput {
        DogecoinRefreshWalletInput(
            index: UInt64(index), walletId: walletID,
            selectedChain: selectedChain, addresses: addresses
        )
    }
}

private extension WalletRustDogecoinRefreshTargetsRequest {
    func toFFI() -> DogecoinRefreshTargetsRequest {
        DogecoinRefreshTargetsRequest(
            wallets: wallets.map { $0.toFFI() },
            allowedWalletIds: allowedWalletIDs
        )
    }
}

private extension DogecoinRefreshWalletTarget {
    func toWalletRust() -> WalletRustDogecoinRefreshWalletTarget {
        WalletRustDogecoinRefreshWalletTarget(
            index: Int(index), walletID: walletId, addresses: addresses
        )
    }
}

private extension WalletRustSendAssetRoutingInput {
    func toFFI() -> SendAssetRoutingInput {
        SendAssetRoutingInput(
            chainName: chainName, symbol: symbol,
            isEvmChain: isEVMChain,
            supportsSolanaSendCoin: supportsSolanaSendCoin,
            supportsNearTokenSend: supportsNearTokenSend
        )
    }
}

private extension WalletRustSendPreviewRoutingRequest {
    func toFFI() -> SendPreviewRoutingRequest {
        SendPreviewRoutingRequest(asset: asset?.toFFI())
    }
}

private extension WalletRustSendSubmitPreflightRequest {
    func toFFI() -> SendSubmitPreflightRequest {
        SendSubmitPreflightRequest(
            walletFound: walletFound, assetFound: assetFound,
            destinationAddress: destinationAddress, amountInput: amountInput,
            availableBalance: availableBalance, asset: asset?.toFFI()
        )
    }
}

private extension WalletRustTransferHoldingInput {
    func toFFI() -> TransferHoldingInput {
        TransferHoldingInput(
            index: UInt64(index), chainName: chainName, symbol: symbol,
            supportsSend: supportsSend, supportsReceiveAddress: supportsReceiveAddress,
            isLiveChain: isLiveChain, supportsEvmToken: supportsEVMToken,
            supportsSolanaSendCoin: supportsSolanaSendCoin
        )
    }
}

private extension WalletRustTransferWalletInput {
    func toFFI() -> TransferWalletInput {
        TransferWalletInput(
            walletId: walletID, hasSigningMaterial: hasSigningMaterial,
            holdings: holdings.map { $0.toFFI() }
        )
    }
}

private extension WalletRustTransferAvailabilityRequest {
    func toFFI() -> TransferAvailabilityRequest {
        TransferAvailabilityRequest(wallets: wallets.map { $0.toFFI() })
    }
}

private extension TransferAvailabilityPlan {
    func toWalletRust() -> WalletRustTransferAvailabilityPlan {
        WalletRustTransferAvailabilityPlan(
            wallets: wallets.map { $0.toWalletRust() },
            sendEnabledWalletIDs: sendEnabledWalletIds,
            receiveEnabledWalletIDs: receiveEnabledWalletIds
        )
    }
}

private extension WalletTransferAvailability {
    func toWalletRust() -> WalletRustWalletTransferAvailability {
        WalletRustWalletTransferAvailability(
            walletID: walletId,
            sendHoldingIndices: sendHoldingIndices.map { Int($0) },
            receiveHoldingIndices: receiveHoldingIndices.map { Int($0) },
            receiveChains: receiveChains
        )
    }
}

private extension WalletRustStoreDerivedHoldingInput {
    func toFFI() -> StoreDerivedHoldingInput {
        StoreDerivedHoldingInput(
            holdingIndex: UInt64(holdingIndex), assetIdentityKey: assetIdentityKey,
            symbolUpper: symbolUpper, amount: amount, isPricedAsset: isPricedAsset
        )
    }
}

private extension WalletRustStoreDerivedWalletInput {
    func toFFI() -> StoreDerivedWalletInput {
        StoreDerivedWalletInput(
            walletId: walletID, includeInPortfolioTotal: includeInPortfolioTotal,
            hasSigningMaterial: hasSigningMaterial, isPrivateKeyBacked: isPrivateKeyBacked,
            holdings: holdings.map { $0.toFFI() }
        )
    }
}

private extension WalletRustStoreDerivedStateRequest {
    func toFFI() -> StoreDerivedStateRequest {
        StoreDerivedStateRequest(wallets: wallets.map { $0.toFFI() })
    }
}

private extension WalletHoldingRef {
    func toWalletRust() -> WalletRustWalletHoldingRef {
        WalletRustWalletHoldingRef(walletID: walletId, holdingIndex: Int(holdingIndex))
    }
}

private extension GroupedPortfolioHolding {
    func toWalletRust() -> WalletRustGroupedPortfolioHolding {
        WalletRustGroupedPortfolioHolding(
            assetIdentityKey: assetIdentityKey, walletID: walletId,
            holdingIndex: Int(holdingIndex), totalAmount: totalAmount
        )
    }
}

private extension StoreDerivedStatePlan {
    func toWalletRust() -> WalletRustStoreDerivedStatePlan {
        WalletRustStoreDerivedStatePlan(
            includedPortfolioHoldingRefs: includedPortfolioHoldingRefs.map { $0.toWalletRust() },
            uniquePriceRequestHoldingRefs: uniquePriceRequestHoldingRefs.map { $0.toWalletRust() },
            groupedPortfolio: groupedPortfolio.map { $0.toWalletRust() },
            signingMaterialWalletIDs: signingMaterialWalletIds,
            privateKeyBackedWalletIDs: privateKeyBackedWalletIds
        )
    }
}

private extension WalletRustReceiveSelectionHoldingInput {
    func toFFI() -> ReceiveSelectionHoldingInput {
        ReceiveSelectionHoldingInput(
            holdingIndex: UInt64(holdingIndex), chainName: chainName,
            hasContractAddress: hasContractAddress
        )
    }
}

private extension WalletRustReceiveSelectionRequest {
    func toFFI() -> ReceiveSelectionRequest {
        ReceiveSelectionRequest(
            receiveChainName: receiveChainName,
            availableReceiveChains: availableReceiveChains,
            availableReceiveHoldings: availableReceiveHoldings.map { $0.toFFI() }
        )
    }
}

private extension WalletRustPendingSelfSendConfirmationInput {
    func toFFI() -> PendingSelfSendConfirmationInput {
        PendingSelfSendConfirmationInput(
            walletId: walletID, chainName: chainName, symbol: symbol,
            destinationAddressLowercased: destinationAddressLowercased,
            amount: amount, createdAtUnix: createdAtUnix
        )
    }
}

private extension WalletRustSelfSendConfirmationRequest {
    func toFFI() -> SelfSendConfirmationRequest {
        SelfSendConfirmationRequest(
            pendingConfirmation: pendingConfirmation?.toFFI(),
            walletId: walletID, chainName: chainName, symbol: symbol,
            destinationAddress: destinationAddress, amount: amount,
            nowUnix: nowUnix, windowSeconds: windowSeconds, ownedAddresses: ownedAddresses
        )
    }
}

private extension WalletRustTransactionRecord {
    func toFFI() -> TransactionRecord {
        TransactionRecord(
            id: id, walletId: walletID, kind: kind, status: status,
            walletName: walletName, assetName: assetName, symbol: symbol,
            chainName: chainName, amount: amount, address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce.map { Int64($0) },
            receiptBlockNumber: receiptBlockNumber.map { Int64($0) },
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: receiptNetworkFeeETH,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount.map { Int64($0) },
            dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations.map { Int64($0) },
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex,
            signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAtUnix: createdAtUnix
        )
    }
}

private extension TransactionRecord {
    func toWalletRust() -> WalletRustTransactionRecord {
        WalletRustTransactionRecord(
            id: id, walletID: walletId, kind: kind, status: status,
            walletName: walletName, assetName: assetName, symbol: symbol,
            chainName: chainName, amount: amount, address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce.map { Int($0) },
            receiptBlockNumber: receiptBlockNumber.map { Int($0) },
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: receiptNetworkFeeEth,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount.map { Int($0) },
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDoge,
            dogecoinConfirmations: dogecoinConfirmations.map { Int($0) },
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex,
            signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAtUnix: createdAtUnix
        )
    }
}

private extension WalletRustTransactionMergeRequest {
    func toFFI() -> TransactionMergeRequest {
        TransactionMergeRequest(
            existingTransactions: existingTransactions.map { $0.toFFI() },
            incomingTransactions: incomingTransactions.map { $0.toFFI() },
            strategy: strategy.toFFI(),
            chainName: chainName,
            includeSymbolInIdentity: includeSymbolInIdentity,
            preserveCreatedAtSentinelUnix: preserveCreatedAtSentinelUnix
        )
    }
}

private extension WalletRustTransactionMergeStrategy {
    func toFFI() -> TransactionMergeStrategy {
        switch self {
        case .standardUTXO: return .standardUtxo
        case .dogecoin:     return .dogecoin
        case .accountBased: return .accountBased
        case .evm:          return .evm
        }
    }
}
