import Foundation

struct WalletRustImportAddresses {
    let bitcoinAddress: String?
    let bitcoinXpub: String?
    let bitcoinCashAddress: String?
    let bitcoinSVAddress: String?
    let litecoinAddress: String?
    let dogecoinAddress: String?
    let ethereumAddress: String?
    let ethereumClassicAddress: String?
    let tronAddress: String?
    let solanaAddress: String?
    let xrpAddress: String?
    let stellarAddress: String?
    let moneroAddress: String?
    let cardanoAddress: String?
    let suiAddress: String?
    let aptosAddress: String?
    let tonAddress: String?
    let icpAddress: String?
    let nearAddress: String?
    let polkadotAddress: String?
}

struct WalletRustWatchOnlyEntries {
    let bitcoinAddresses: [String]
    let bitcoinXpub: String?
    let bitcoinCashAddresses: [String]
    let bitcoinSVAddresses: [String]
    let litecoinAddresses: [String]
    let dogecoinAddresses: [String]
    let ethereumAddresses: [String]
    let tronAddresses: [String]
    let solanaAddresses: [String]
    let xrpAddresses: [String]
    let stellarAddresses: [String]
    let cardanoAddresses: [String]
    let suiAddresses: [String]
    let aptosAddresses: [String]
    let tonAddresses: [String]
    let icpAddresses: [String]
    let nearAddresses: [String]
    let polkadotAddresses: [String]
}

struct WalletRustImportPlanRequest {
    let walletName: String
    let defaultWalletNameStartIndex: Int
    let primarySelectedChainName: String
    let selectedChainNames: [String]
    let plannedWalletIDs: [String]
    let isWatchOnlyImport: Bool
    let isPrivateKeyImport: Bool
    let hasWalletPassword: Bool
    let resolvedAddresses: WalletRustImportAddresses
    let watchOnlyEntries: WalletRustWatchOnlyEntries
}

struct WalletRustSecretInstruction {
    let walletID: String
    let secretKind: String
    let shouldStoreSeedPhrase: Bool
    let shouldStorePrivateKey: Bool
    let shouldStorePasswordVerifier: Bool
}

struct WalletRustPlannedWallet {
    let walletID: String
    let name: String
    let chainName: String
    let addresses: WalletRustImportAddresses
}

struct WalletRustImportPlan {
    let secretKind: String
    let wallets: [WalletRustPlannedWallet]
    let secretInstructions: [WalletRustSecretInstruction]
}

struct WalletRustSecretObservation: Encodable {
    let walletID: String
    let secretKind: String?
    let hasSeedPhrase: Bool
    let hasPrivateKey: Bool
    let hasPassword: Bool
}

struct WalletRustPersistedSnapshotBuildRequest: Encodable {
    let appStateJSON: String
    let secretObservations: [WalletRustSecretObservation]
}

struct WalletRustSecretMaterialDescriptor: Decodable {
    let walletID: String
    let secretKind: String
    let hasSeedPhrase: Bool
    let hasPrivateKey: Bool
    let hasPassword: Bool
    let hasSigningMaterial: Bool
    let seedPhraseStoreKey: String
    let passwordStoreKey: String
    let privateKeyStoreKey: String
}

struct WalletRustWalletSecretIndex: Decodable {
    let descriptors: [WalletRustSecretMaterialDescriptor]
    let signingMaterialWalletIDs: [String]
    let privateKeyBackedWalletIDs: [String]
    let passwordProtectedWalletIDs: [String]
}

struct WalletRustActiveMaintenancePlanRequest {
    let nowUnix: Double
    let lastPendingTransactionRefreshAtUnix: Double?
    let lastLivePriceRefreshAtUnix: Double?
    let hasPendingTransactionMaintenanceWork: Bool
    let shouldRunScheduledPriceRefresh: Bool
    let pendingRefreshInterval: Double
    let priceRefreshInterval: Double
}

struct WalletRustActiveMaintenancePlan {
    let refreshPendingTransactions: Bool
    let refreshLivePrices: Bool
}

struct WalletRustBackgroundMaintenanceRequest {
    let nowUnix: Double
    let isNetworkReachable: Bool
    let lastBackgroundMaintenanceAtUnix: Double?
    let interval: Double
}

struct WalletRustChainRefreshPlanRequest {
    let chainIDs: [String]
    let nowUnix: Double
    let forceChainRefresh: Bool
    let includeHistoryRefreshes: Bool
    let historyRefreshInterval: Double
    let pendingTransactionMaintenanceChainIDs: [String]
    let degradedChainIDs: [String]
    let lastGoodChainSyncByID: [String: Double]
    let lastHistoryRefreshAtByChainID: [String: Double]
    let automaticChainRefreshStalenessInterval: Double
}

struct WalletRustChainRefreshPlan {
    let chainID: String
    let chainName: String
    let refreshHistory: Bool
}

struct WalletRustHistoryRefreshPlanRequest {
    let chainIDs: [String]
    let nowUnix: Double
    let interval: Double
    let lastHistoryRefreshAtByChainID: [String: Double]
}

struct WalletRustHistoryWallet {
    let walletID: String
    let selectedChain: String
}

struct WalletRustHistoryTransaction {
    let id: String
    let walletID: String?
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let address: String
    let transactionHash: String?
    let transactionHistorySource: String?
    let createdAtUnix: Double
}

struct WalletRustNormalizeHistoryRequest {
    let wallets: [WalletRustHistoryWallet]
    let transactions: [WalletRustHistoryTransaction]
    let unknownLabel: String
}

struct WalletRustBitcoinHistorySnapshotPayload {
    let txid: String
    let amountBTC: Double
    let kind: String
    let status: String
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAtUnix: Double
}

struct WalletRustMergeBitcoinHistorySnapshotsRequest {
    let snapshots: [WalletRustBitcoinHistorySnapshotPayload]
    let ownedAddresses: [String]
    let limit: Int
}

struct WalletRustNormalizedHistoryEntry {
    let id: String
    let transactionID: String
    let dedupeKey: String
    let createdAtUnix: Double
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let address: String
    let transactionHash: String?
    let sourceTag: String
    let providerCount: Int
    let searchIndex: String
}

enum WalletRustTransactionMergeStrategy {
    case standardUTXO
    case dogecoin
    case accountBased
    case evm
}

struct WalletRustTransactionRecord {
    let id: String
    let walletID: String?
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let amount: Double
    let address: String
    let transactionHash: String?
    let ethereumNonce: Int?
    let receiptBlockNumber: Int?
    let receiptGasUsed: String?
    let receiptEffectiveGasPriceGwei: Double?
    let receiptNetworkFeeETH: Double?
    let feePriorityRaw: String?
    let feeRateDescription: String?
    let confirmationCount: Int?
    let dogecoinConfirmedNetworkFeeDOGE: Double?
    let dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?
    let dogecoinEstimatedFeeRateDOGEPerKB: Double?
    let usedChangeOutput: Bool?
    let dogecoinUsedChangeOutput: Bool?
    let sourceDerivationPath: String?
    let changeDerivationPath: String?
    let sourceAddress: String?
    let changeAddress: String?
    let dogecoinRawTransactionHex: String?
    let signedTransactionPayload: String?
    let signedTransactionPayloadFormat: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAtUnix: Double
}

struct WalletRustTransactionMergeRequest {
    let existingTransactions: [WalletRustTransactionRecord]
    let incomingTransactions: [WalletRustTransactionRecord]
    let strategy: WalletRustTransactionMergeStrategy
    let chainName: String
    let includeSymbolInIdentity: Bool
    let preserveCreatedAtSentinelUnix: Double?
}

struct WalletRustEVMRefreshWalletInput {
    let index: Int
    let walletID: String
    let selectedChain: String
    let address: String?
}

struct WalletRustEVMRefreshTargetsRequest {
    let chainName: String
    let wallets: [WalletRustEVMRefreshWalletInput]
    let allowedWalletIDs: [String]?
    let groupByNormalizedAddress: Bool
}

struct WalletRustEVMRefreshWalletTarget {
    let index: Int
    let walletID: String
    let address: String
    let normalizedAddress: String
}

struct WalletRustEVMGroupedTarget {
    let walletIDs: [String]
    let address: String
    let normalizedAddress: String
}

struct WalletRustEVMRefreshPlan {
    let walletTargets: [WalletRustEVMRefreshWalletTarget]
    let groupedTargets: [WalletRustEVMGroupedTarget]
}

struct WalletRustDogecoinRefreshWalletInput {
    let index: Int
    let walletID: String
    let selectedChain: String
    let addresses: [String]
}

struct WalletRustDogecoinRefreshTargetsRequest {
    let wallets: [WalletRustDogecoinRefreshWalletInput]
    let allowedWalletIDs: [String]?
}

struct WalletRustDogecoinRefreshWalletTarget {
    let index: Int
    let walletID: String
    let addresses: [String]
}

struct WalletRustSendAssetRoutingInput {
    let chainName: String
    let symbol: String
    let isEVMChain: Bool
    let supportsSolanaSendCoin: Bool
    var supportsNearTokenSend: Bool = false
}

struct WalletRustSendPreviewRoutingRequest {
    let asset: WalletRustSendAssetRoutingInput?
}

struct WalletRustSendPreviewRoutingPlan {
    let activePreviewKind: String?
}

struct WalletRustSendSubmitPreflightRequest {
    let walletFound: Bool
    let assetFound: Bool
    let destinationAddress: String
    let amountInput: String
    let availableBalance: Double
    let asset: WalletRustSendAssetRoutingInput?
}

struct WalletRustSendSubmitPreflightPlan {
    let submitKind: String
    let previewKind: String?
    let normalizedDestinationAddress: String
    let amount: Double
    let chainName: String
    let symbol: String
    let nativeEVMSymbol: String?
    let isNativeEVMAsset: Bool
    let allowsZeroAmount: Bool
}

struct WalletRustTransferHoldingInput {
    let index: Int
    let chainName: String
    let symbol: String
    let supportsSend: Bool
    let supportsReceiveAddress: Bool
    let isLiveChain: Bool
    let supportsEVMToken: Bool
    let supportsSolanaSendCoin: Bool
}

struct WalletRustTransferWalletInput {
    let walletID: String
    let hasSigningMaterial: Bool
    let holdings: [WalletRustTransferHoldingInput]
}

struct WalletRustTransferAvailabilityRequest {
    let wallets: [WalletRustTransferWalletInput]
}

struct WalletRustWalletTransferAvailability {
    let walletID: String
    let sendHoldingIndices: [Int]
    let receiveHoldingIndices: [Int]
    let receiveChains: [String]
}

struct WalletRustTransferAvailabilityPlan {
    let wallets: [WalletRustWalletTransferAvailability]
    let sendEnabledWalletIDs: [String]
    let receiveEnabledWalletIDs: [String]
}

struct WalletRustStoreDerivedHoldingInput {
    let holdingIndex: Int
    let assetIdentityKey: String
    let symbolUpper: String
    let amount: String
    let isPricedAsset: Bool
}

struct WalletRustStoreDerivedWalletInput {
    let walletID: String
    let includeInPortfolioTotal: Bool
    let hasSigningMaterial: Bool
    let isPrivateKeyBacked: Bool
    let holdings: [WalletRustStoreDerivedHoldingInput]
}

struct WalletRustStoreDerivedStateRequest {
    let wallets: [WalletRustStoreDerivedWalletInput]
}

struct WalletRustWalletHoldingRef {
    let walletID: String
    let holdingIndex: Int
}

struct WalletRustGroupedPortfolioHolding {
    let assetIdentityKey: String
    let walletID: String
    let holdingIndex: Int
    let totalAmount: String
}

struct WalletRustStoreDerivedStatePlan {
    let includedPortfolioHoldingRefs: [WalletRustWalletHoldingRef]
    let uniquePriceRequestHoldingRefs: [WalletRustWalletHoldingRef]
    let groupedPortfolio: [WalletRustGroupedPortfolioHolding]
    let signingMaterialWalletIDs: [String]
    let privateKeyBackedWalletIDs: [String]
}

struct WalletRustOwnedAddressAggregationRequest {
    let candidateAddresses: [String]
}

struct WalletRustReceiveSelectionHoldingInput {
    let holdingIndex: Int
    let chainName: String
    let hasContractAddress: Bool
}

struct WalletRustReceiveSelectionRequest {
    let receiveChainName: String
    let availableReceiveChains: [String]
    let availableReceiveHoldings: [WalletRustReceiveSelectionHoldingInput]
}

struct WalletRustReceiveSelectionPlan {
    let resolvedChainName: String
    let selectedReceiveHoldingIndex: Int?
}

struct WalletRustPendingSelfSendConfirmationInput {
    let walletID: String
    let chainName: String
    let symbol: String
    let destinationAddressLowercased: String
    let amount: Double
    let createdAtUnix: Double
}

struct WalletRustSelfSendConfirmationRequest {
    let pendingConfirmation: WalletRustPendingSelfSendConfirmationInput?
    let walletID: String
    let chainName: String
    let symbol: String
    let destinationAddress: String
    let amount: Double
    let nowUnix: Double
    let windowSeconds: Double
    let ownedAddresses: [String]
}

struct WalletRustSelfSendConfirmationPlan {
    let requiresConfirmation: Bool
    let consumeExistingConfirmation: Bool
    let clearPendingConfirmation: Bool
}

struct WalletRustResolvedDerivationPath {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}
