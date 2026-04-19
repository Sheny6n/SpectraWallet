import Foundation
enum WalletRustEndpointCatalogBridgeError: LocalizedError {
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case invalidPayload(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreReturnedNullResponse: return "The Rust endpoint catalog returned an empty response."
        case .rustCoreFailed(let message): return message
        case .invalidPayload(let message): return message
        }}
}
typealias AppEndpointGroupedSettingsEntry = AppCoreGroupedSettingsEntry
typealias AppEndpointDiagnosticsCheck = AppCoreDiagnosticsCheck
typealias AppEndpointExplorerEntry = AppCoreExplorerEntry
typealias AppEndpointRecord = AppCoreEndpointRecord
enum WalletRustEndpointCatalogBridge {
    nonisolated static func endpoint(_ id: String) throws -> String { try appCoreEndpointForId(id: id) }
    nonisolated static func endpoints(for ids: [String]) throws -> [String] { try appCoreEndpointsForIds(ids: ids) }
    nonisolated static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>, settingsVisibleOnly: Bool) throws -> [AppEndpointRecord] {
        try appCoreEndpointRecordsForChain(
            chainName: chainName, roleMask: roleMask(for: roles), settingsVisibleOnly: settingsVisibleOnly
        )
    }
    nonisolated static func groupedSettingsEntries(for chainName: String) throws -> [AppEndpointGroupedSettingsEntry] {
        try appCoreGroupedSettingsEntries(chainName: chainName)
    }
    nonisolated static func diagnosticsChecks(for chainName: String) throws -> [AppEndpointDiagnosticsCheck] {
        try appCoreDiagnosticsChecks(chainName: chainName)
    }
    nonisolated static func transactionExplorerEntry(for chainName: String) throws -> AppEndpointExplorerEntry? {
        try appCoreTransactionExplorerEntry(chainName: chainName)
    }
    nonisolated static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] { try appCoreBitcoinEsploraBaseUrls(network: networkMode.rawValue) }
    nonisolated static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] { try appCoreBitcoinWalletStoreDefaultBaseUrls(network: networkMode.rawValue) }
    nonisolated static func evmRPCEndpoints(for chainName: String) throws -> [String] { try appCoreEvmRpcEndpoints(chainName: chainName) }
    nonisolated static func explorerSupplementalEndpoints(for chainName: String) throws -> [String] { try appCoreExplorerSupplementalEndpoints(chainName: chainName) }
    nonisolated static func broadcastProviderOptions(for chainName: String) -> [ChainBroadcastProviderOption] {
        appCoreBroadcastProviderOptions(chainName: chainName).map {
            ChainBroadcastProviderOption(id: $0.id, title: $0.title)
        }
    }
    nonisolated static func chainBackends() throws -> [ChainBackendRecord] {
        try appCoreChainBackends().map {
            guard let state = ChainIntegrationState(rawValue: $0.integrationState) else {
                throw WalletRustEndpointCatalogBridgeError.invalidPayload("Unknown integration state: \($0.integrationState)")
            }
            return ChainBackendRecord(chainName: $0.chainName, supportedSymbols: $0.supportedSymbols, integrationState: state, supportsSeedImport: $0.supportsSeedImport, supportsBalanceRefresh: $0.supportsBalanceRefresh, supportsReceiveAddress: $0.supportsReceiveAddress, supportsSend: $0.supportsSend)
        }
    }
    nonisolated static func liveChainNames() -> [String] { appCoreLiveChainNames() }
    nonisolated static func appChainDescriptors() -> [AppChainDescriptor] {
        appCoreAppChainDescriptors().compactMap {
            guard let chainID = AppChainID(rawValue: $0.id) else { return nil }
            return AppChainDescriptor(id: chainID, chainName: $0.chainName, shortLabel: $0.shortLabel, nativeSymbol: $0.nativeSymbol, searchKeywords: $0.searchKeywords, supportsDiagnostics: $0.supportsDiagnostics, supportsEndpointCatalog: $0.supportsEndpointCatalog, isEVM: $0.isEvm)
        }
    }
    nonisolated private static func roleMask(for roles: Set<AppEndpointRole>) -> UInt32 {
        coreEndpointRoleMask(roles: roles.map(\.rawValue))
    }
}
enum AppEndpointRole: String, Hashable, CaseIterable, Decodable {
    case read
    case balance
    case history
    case utxo
    case fee
    case broadcast
    case verification
    case rpc
    case explorer
    case backend
}
nonisolated enum AppEndpointDirectory {
    static func endpoint(_ id: String) -> String {
        do {
            return try WalletRustEndpointCatalogBridge.endpoint(id)
        } catch {
            preconditionFailure("Rust endpoint lookup failed for id \(id): \(error.localizedDescription)")
        }}
    static func endpoints(for ids: [String]) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.endpoints(for: ids)
        } catch {
            preconditionFailure("Rust endpoint lookup failed for ids \(ids): \(error.localizedDescription)")
        }}
    static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>? = nil, settingsVisibleOnly: Bool = false) -> [AppEndpointRecord] {
        do {
            return try WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: roles ?? [], settingsVisibleOnly: settingsVisibleOnly
            )
        } catch {
            preconditionFailure("Rust endpoint records failed for \(chainName): \(error.localizedDescription)")
        }}
    static func groupedSettingsEntries(for chainName: String) -> [(title: String, endpoints: [String])] {
        do {
            return try WalletRustEndpointCatalogBridge.groupedSettingsEntries(for: chainName).map { (title: $0.title, endpoints: $0.endpoints) }
        } catch {
            preconditionFailure("Rust grouped settings entries failed for \(chainName): \(error.localizedDescription)")
        }}
    static func settingsEndpoints(for chainName: String) -> [String] { groupedSettingsEntries(for: chainName).flatMap(\.endpoints) }
    static func diagnosticsChecks(for chainName: String) -> [(endpoint: String, probeURL: String)] {
        do {
            return try WalletRustEndpointCatalogBridge.diagnosticsChecks(for: chainName).map { (endpoint: $0.endpoint, probeURL: $0.probeUrl) }
        } catch {
            preconditionFailure("Rust diagnostics checks failed for \(chainName): \(error.localizedDescription)")
        }}
    static func evmRPCEndpoints(for chainName: String) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName)
        } catch {
            preconditionFailure("Rust EVM RPC lookup failed for \(chainName): \(error.localizedDescription)")
        }}
    static func explorerSupplementalEndpoints(for chainName: String) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName)
        } catch {
            preconditionFailure("Rust explorer endpoint lookup failed for \(chainName): \(error.localizedDescription)")
        }}
    static func transactionExplorerBaseURL(for chainName: String) -> String? {
        do {
            return try WalletRustEndpointCatalogBridge.transactionExplorerEntry(for: chainName)?.endpoint
        } catch {
            preconditionFailure("Rust transaction explorer lookup failed for \(chainName): \(error.localizedDescription)")
        }}
    static func transactionExplorerLabel(for chainName: String) -> String? {
        do {
            return try WalletRustEndpointCatalogBridge.transactionExplorerEntry(for: chainName)?.label
        } catch {
            preconditionFailure("Rust transaction explorer label lookup failed for \(chainName): \(error.localizedDescription)")
        }}
    static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.bitcoinEsploraBaseURLs(for: networkMode)
        } catch {
            preconditionFailure("Rust Bitcoin Esplora lookup failed for \(networkMode.rawValue): \(error.localizedDescription)")
        }}
    static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.bitcoinWalletStoreDefaultBaseURLs(for: networkMode)
        } catch {
            preconditionFailure("Rust Bitcoin wallet-store lookup failed for \(networkMode.rawValue): \(error.localizedDescription)")
        }}
    static func transactionExplorerURL(for chainName: String, transactionHash: String) -> URL? {
        guard let baseURL = transactionExplorerBaseURL(for: chainName) else { return nil }
        if chainName == "Aptos" { return URL(string: "\(baseURL)\(transactionHash)?network=mainnet") }
        return URL(string: baseURL + transactionHash)
    }
    static let liveChainNames = WalletRustEndpointCatalogBridge.liveChainNames()
    static let allBackends: [ChainBackendRecord] = loadChainBackends()
    static let appChains: [AppChainDescriptor] = loadAppChains()
    static func backend(for chainName: String) -> ChainBackendRecord? { allBackends.first { $0.chainName == chainName } }
    static func supportsBalanceRefresh(for chainName: String) -> Bool { backend(for: chainName)?.supportsBalanceRefresh ?? false }
    static func supportsReceiveAddress(for chainName: String) -> Bool { backend(for: chainName)?.supportsReceiveAddress ?? false }
    static func supportsSend(for chainName: String) -> Bool { backend(for: chainName)?.supportsSend ?? false }
    static func appChain(for chainName: String) -> AppChainDescriptor? { appChains.first { $0.chainName == chainName } }
    static func appChain(for id: AppChainID) -> AppChainDescriptor { appChains.first(where: { $0.id == id })! }
    static var diagnosticsChains: [AppChainDescriptor] { appChains.filter(\.supportsDiagnostics) }
    static var endpointCatalogChains: [AppChainDescriptor] { appChains.filter(\.supportsEndpointCatalog) }
    private static func loadChainBackends() -> [ChainBackendRecord] {
        do { return try WalletRustEndpointCatalogBridge.chainBackends() }
        catch { preconditionFailure("Rust chain backend catalog failed to load: \(error.localizedDescription)") }}
    private static func loadAppChains() -> [AppChainDescriptor] {
        WalletRustEndpointCatalogBridge.appChainDescriptors()
    }
}
