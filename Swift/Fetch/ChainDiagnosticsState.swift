import Foundation
import Combine

// Phase B: The 24 per-wallet diagnostic dictionaries that previously lived as
// stored `@Published` properties on this class now live in the Rust registry
// (`core/src/diagnostics/registry.rs`). Swift presents the same `[String: T]`
// dict-shaped API via writable computed vars that delegate to UniFFI, so
// every existing call site and `ReferenceWritableKeyPath` continues to work.
//
// SwiftUI reactivity: mutations bump `diagnosticsRevision`, and since this is
// `@Published`, any view observing the whole `WalletChainDiagnosticsState`
// (or observing `AppState` which forwards `objectWillChange` from this
// object) refreshes as before.
final class WalletChainDiagnosticsState: ObservableObject {
    // Bump this on every registry mutation so SwiftUI observers re-render.
    @Published var diagnosticsRevision: Int = 0

    private func bump() { diagnosticsRevision &+= 1 }

    // MARK: Non-dict state (unchanged)
    @Published var dogecoinSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningDogecoinSelfTests: Bool = false
    @Published var dogecoinSelfTestsLastRunAt: Date?
    @Published var bitcoinSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningBitcoinSelfTests: Bool = false
    @Published var bitcoinSelfTestsLastRunAt: Date?
    @Published var bitcoinCashSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningBitcoinCashSelfTests: Bool = false
    @Published var bitcoinCashSelfTestsLastRunAt: Date?
    @Published var bitcoinSVSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningBitcoinSVSelfTests: Bool = false
    @Published var bitcoinSVSelfTestsLastRunAt: Date?
    @Published var litecoinSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningLitecoinSelfTests: Bool = false
    @Published var litecoinSelfTestsLastRunAt: Date?
    @Published var dogecoinHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningDogecoinHistoryDiagnostics: Bool = false
    @Published var dogecoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var dogecoinEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingDogecoinEndpointHealth: Bool = false
    @Published var ethereumSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningEthereumSelfTests: Bool = false
    @Published var ethereumSelfTestsLastRunAt: Date?
    @Published var ethereumHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningEthereumHistoryDiagnostics: Bool = false
    @Published var ethereumEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var ethereumEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingEthereumEndpointHealth: Bool = false
    @Published var etcHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningETCHistoryDiagnostics: Bool = false
    @Published var etcEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var etcEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingETCEndpointHealth: Bool = false
    @Published var arbitrumHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningArbitrumHistoryDiagnostics: Bool = false
    @Published var arbitrumEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var arbitrumEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingArbitrumEndpointHealth: Bool = false
    @Published var optimismHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningOptimismHistoryDiagnostics: Bool = false
    @Published var optimismEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var optimismEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingOptimismEndpointHealth: Bool = false
    @Published var bnbHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBNBHistoryDiagnostics: Bool = false
    @Published var bnbEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var bnbEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBNBEndpointHealth: Bool = false
    @Published var avalancheHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningAvalancheHistoryDiagnostics: Bool = false
    @Published var avalancheEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var avalancheEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingAvalancheEndpointHealth: Bool = false
    @Published var hyperliquidHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningHyperliquidHistoryDiagnostics: Bool = false
    @Published var hyperliquidEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var hyperliquidEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingHyperliquidEndpointHealth: Bool = false
    @Published var tronHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningTronHistoryDiagnostics: Bool = false
    @Published var tronEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var tronEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingTronEndpointHealth: Bool = false
    @Published var solanaHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningSolanaHistoryDiagnostics: Bool = false
    @Published var solanaEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var solanaEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingSolanaEndpointHealth: Bool = false
    @Published var xrpHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningXRPHistoryDiagnostics: Bool = false
    @Published var xrpEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var xrpEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingXRPEndpointHealth: Bool = false
    @Published var stellarHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningStellarHistoryDiagnostics: Bool = false
    @Published var stellarEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var stellarEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingStellarEndpointHealth: Bool = false
    @Published var moneroHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningMoneroHistoryDiagnostics: Bool = false
    @Published var moneroEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var moneroEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingMoneroEndpointHealth: Bool = false
    @Published var suiHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningSuiHistoryDiagnostics: Bool = false
    @Published var suiEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var suiEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingSuiEndpointHealth: Bool = false
    @Published var aptosHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningAptosHistoryDiagnostics: Bool = false
    @Published var aptosEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var aptosEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingAptosEndpointHealth: Bool = false
    @Published var tonHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningTONHistoryDiagnostics: Bool = false
    @Published var tonEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var tonEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingTONEndpointHealth: Bool = false
    @Published var icpHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningICPHistoryDiagnostics: Bool = false
    @Published var icpEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var icpEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingICPEndpointHealth: Bool = false
    @Published var nearHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningNearHistoryDiagnostics: Bool = false
    @Published var nearEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var nearEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingNearEndpointHealth: Bool = false
    @Published var polkadotHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningPolkadotHistoryDiagnostics: Bool = false
    @Published var polkadotEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var polkadotEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingPolkadotEndpointHealth: Bool = false
    @Published var cardanoHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningCardanoHistoryDiagnostics: Bool = false
    @Published var cardanoEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var cardanoEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingCardanoEndpointHealth: Bool = false
    @Published var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload?
    @Published var bitcoinHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBitcoinHistoryDiagnostics: Bool = false
    @Published var bitcoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var bitcoinEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBitcoinEndpointHealth: Bool = false
    @Published var bitcoinCashHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBitcoinCashHistoryDiagnostics: Bool = false
    @Published var bitcoinCashEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var bitcoinCashEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBitcoinCashEndpointHealth: Bool = false
    @Published var bitcoinSVHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBitcoinSVHistoryDiagnostics: Bool = false
    @Published var bitcoinSVEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var bitcoinSVEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBitcoinSVEndpointHealth: Bool = false
    @Published var litecoinHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningLitecoinHistoryDiagnostics: Bool = false
    @Published var litecoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var litecoinEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingLitecoinEndpointHealth: Bool = false

    // MARK: Per-wallet diagnostic dicts (Rust-owned; computed delegates)

    var dogecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllDogecoin() }
        set { objectWillChange.send(); diagnosticsReplaceDogecoin(entries: newValue); bump() }
    }
    var ethereumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEthereum() }
        set { objectWillChange.send(); diagnosticsReplaceEthereum(entries: newValue); bump() }
    }
    var etcHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEtc() }
        set { objectWillChange.send(); diagnosticsReplaceEtc(entries: newValue); bump() }
    }
    var arbitrumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllArbitrum() }
        set { objectWillChange.send(); diagnosticsReplaceArbitrum(entries: newValue); bump() }
    }
    var optimismHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllOptimism() }
        set { objectWillChange.send(); diagnosticsReplaceOptimism(entries: newValue); bump() }
    }
    var bnbHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllBnb() }
        set { objectWillChange.send(); diagnosticsReplaceBnb(entries: newValue); bump() }
    }
    var avalancheHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllAvalanche() }
        set { objectWillChange.send(); diagnosticsReplaceAvalanche(entries: newValue); bump() }
    }
    var hyperliquidHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllHyperliquid() }
        set { objectWillChange.send(); diagnosticsReplaceHyperliquid(entries: newValue); bump() }
    }
    var tronHistoryDiagnosticsByWallet: [String: TronHistoryDiagnostics] {
        get { diagnosticsAllTron() }
        set { objectWillChange.send(); diagnosticsReplaceTron(entries: newValue); bump() }
    }
    var solanaHistoryDiagnosticsByWallet: [String: SolanaHistoryDiagnostics] {
        get { diagnosticsAllSolana() }
        set { objectWillChange.send(); diagnosticsReplaceSolana(entries: newValue); bump() }
    }
    var xrpHistoryDiagnosticsByWallet: [String: XRPHistoryDiagnostics] {
        get { diagnosticsAllXrp() }
        set { objectWillChange.send(); diagnosticsReplaceXrp(entries: newValue); bump() }
    }
    var stellarHistoryDiagnosticsByWallet: [String: StellarHistoryDiagnostics] {
        get { diagnosticsAllStellar() }
        set { objectWillChange.send(); diagnosticsReplaceStellar(entries: newValue); bump() }
    }
    var moneroHistoryDiagnosticsByWallet: [String: MoneroHistoryDiagnostics] {
        get { diagnosticsAllMonero() }
        set { objectWillChange.send(); diagnosticsReplaceMonero(entries: newValue); bump() }
    }
    var suiHistoryDiagnosticsByWallet: [String: SuiHistoryDiagnostics] {
        get { diagnosticsAllSui() }
        set { objectWillChange.send(); diagnosticsReplaceSui(entries: newValue); bump() }
    }
    var aptosHistoryDiagnosticsByWallet: [String: AptosHistoryDiagnostics] {
        get { diagnosticsAllAptos() }
        set { objectWillChange.send(); diagnosticsReplaceAptos(entries: newValue); bump() }
    }
    var tonHistoryDiagnosticsByWallet: [String: TONHistoryDiagnostics] {
        get { diagnosticsAllTon() }
        set { objectWillChange.send(); diagnosticsReplaceTon(entries: newValue); bump() }
    }
    var icpHistoryDiagnosticsByWallet: [String: ICPHistoryDiagnostics] {
        get { diagnosticsAllIcp() }
        set { objectWillChange.send(); diagnosticsReplaceIcp(entries: newValue); bump() }
    }
    var nearHistoryDiagnosticsByWallet: [String: NearHistoryDiagnostics] {
        get { diagnosticsAllNear() }
        set { objectWillChange.send(); diagnosticsReplaceNear(entries: newValue); bump() }
    }
    var polkadotHistoryDiagnosticsByWallet: [String: PolkadotHistoryDiagnostics] {
        get { diagnosticsAllPolkadot() }
        set { objectWillChange.send(); diagnosticsReplacePolkadot(entries: newValue); bump() }
    }
    var cardanoHistoryDiagnosticsByWallet: [String: CardanoHistoryDiagnostics] {
        get { diagnosticsAllCardano() }
        set { objectWillChange.send(); diagnosticsReplaceCardano(entries: newValue); bump() }
    }
    var bitcoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllBitcoin() }
        set { objectWillChange.send(); diagnosticsReplaceBitcoin(entries: newValue); bump() }
    }
    var bitcoinCashHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllBitcoinCash() }
        set { objectWillChange.send(); diagnosticsReplaceBitcoinCash(entries: newValue); bump() }
    }
    var bitcoinSVHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllBitcoinSv() }
        set { objectWillChange.send(); diagnosticsReplaceBitcoinSv(entries: newValue); bump() }
    }
    var litecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllLitecoin() }
        set { objectWillChange.send(); diagnosticsReplaceLitecoin(entries: newValue); bump() }
    }
}
