import Foundation

struct ChainSelfTestResult: Codable {
    let name: String
    let passed: Bool
    let message: String
}

private struct RustChainSelfTestResult: Decodable {
    let name: String
    let passed: Bool
    let message: String
    func toResult() -> ChainSelfTestResult {
        ChainSelfTestResult(name: name, passed: passed, message: message)
    }
}

private enum SelfTestsRustBridge {
    static func run(chainKey: String) -> [ChainSelfTestResult] {
        do {
            let json = try selfTestsRunChainJson(chainKey: chainKey)
            let decoded = try JSONDecoder().decode([RustChainSelfTestResult].self, from: Data(json.utf8))
            return decoded.map { $0.toResult() }
        } catch {
            return [
                ChainSelfTestResult(
                    name: "\(chainKey) Self Test Bridge",
                    passed: false,
                    message: "Failed to invoke Rust self-test runner: \(error)"
                )
            ]
        }
    }

    static func runAll() -> [String: [ChainSelfTestResult]] {
        do {
            let json = try selfTestsRunAllJson()
            let decoded = try JSONDecoder().decode([String: [RustChainSelfTestResult]].self, from: Data(json.utf8))
            return decoded.mapValues { $0.map { $0.toResult() } }
        } catch {
            return [:]
        }
    }
}

enum DogecoinChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Dogecoin") }
}

enum EthereumChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Ethereum") }
}

@MainActor enum BitcoinSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Bitcoin") } }
@MainActor enum BitcoinCashSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Bitcoin Cash") } }
@MainActor enum LitecoinSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Litecoin") } }
@MainActor enum BitcoinSVSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Bitcoin SV") } }
@MainActor enum CardanoSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Cardano") } }
@MainActor enum SolanaChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Solana") } }
@MainActor enum StellarSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Stellar") } }
@MainActor enum XRPChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "XRP") } }
@MainActor enum TronChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Tron") } }
@MainActor enum SuiChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Sui") } }
@MainActor enum AptosChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Aptos") } }
@MainActor enum TONChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "TON") } }
@MainActor enum ICPChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Internet Computer") } }
@MainActor enum NearChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "NEAR") } }
@MainActor enum PolkadotChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Polkadot") } }
@MainActor enum MoneroChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Monero") } }
@MainActor enum BNBChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "BNB Chain") } }
@MainActor enum AvalancheChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Avalanche") } }
@MainActor enum EthereumClassicSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Ethereum Classic") } }
@MainActor enum HyperliquidSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Hyperliquid") } }

@MainActor
enum AllChainsSelfTestSuite {
    static func runAll() -> [String: [ChainSelfTestResult]] { SelfTestsRustBridge.runAll() }
}
