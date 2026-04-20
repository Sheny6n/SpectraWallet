import Foundation
import XCTest
@testable import Spectra
@MainActor
private func makeSingleChainDraft(select: (WalletImportDraft) -> Void) -> WalletImportDraft {
    let draft = WalletImportDraft()
    select(draft)
    return draft
}
@MainActor
final class ChainWikiRegistryTests: XCTestCase {
    func testEveryRegisteredChainHasAMatchingWikiEntry() {
        let registryIds = Set(ChainRegistryEntry.all.map(\.id))
        let wikiIds = Set(ChainWikiEntry.all.map(\.id))
        let missing = registryIds.subtracting(wikiIds)
        XCTAssertTrue(missing.isEmpty, "Chains missing wiki entries: \(missing.sorted())")
    }
}
@MainActor
final class NearHistoryParsingTests: XCTestCase {
    func testParsesNearBlocksHistoryPackageWithPredecessorAndReceiptBlock() throws {
        let owner = "alice.near"
        let payload: [String: Any] = [
            "txns": [
                [
                    "transaction_hash": "hash-send-1", "predecessor_account_id": owner, "receiver_account_id": "merchant.near",
                    "receipt_block": [
                        "block_timestamp": "1726000000000000000"
                    ],
                    "actions_agg": [
                        "deposit": "1500000000000000000000000"
                    ],
                ],
                [
                    "transaction_hash": "hash-receive-1", "predecessor_account_id": "payer.near", "receiver_account_id": owner,
                    "receipt_block": [
                        "block_timestamp": "1726000100000000000"
                    ],
                    "actions": [
                        [
                            "args": [
                                "deposit": "2500000000000000000000000"
                            ]
                        ]
                    ],
                ],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let snapshots = try NearBalanceService.parseHistoryResponse(data, ownerAddress: owner)
        XCTAssertEqual(snapshots.count, 2)
        let send = try XCTUnwrap(snapshots.first(where: { $0.transactionHash == "hash-send-1" }))
        XCTAssertEqual(send.kind, "send")
        XCTAssertEqual(send.counterpartyAddress, "merchant.near")
        XCTAssertEqual(send.amountNear, 1.5, accuracy: 0.0000001)
        let receive = try XCTUnwrap(snapshots.first(where: { $0.transactionHash == "hash-receive-1" }))
        XCTAssertEqual(receive.kind, "receive")
        XCTAssertEqual(receive.counterpartyAddress, "payer.near")
        XCTAssertEqual(receive.amountNear, 2.5, accuracy: 0.0000001)
    }
}
@MainActor
final class TronDerivationSupportTests: XCTestCase {
    func testTronDerivationPresetsIncludeLegacyVariants() throws {
        let presets = SeedDerivationChain.tron.presetOptions
        XCTAssertEqual(presets.first?.path, "m/44'/195'/0'/0/0")
        XCTAssertTrue(presets.contains { $0.title == "Simple BIP44" && $0.path == "m/44'/195'/0'" })
        XCTAssertTrue(presets.contains { $0.title == "Legacy" && $0.path == "m/44'/60'/0'/0/0" })
    }
    func testTronLegacyEthereumStylePathResolvesAsLegacyFlavor() {
        let resolution = SeedDerivationChain.tron.resolve(path: "m/44'/60'/0'/0/0")
        XCTAssertEqual(resolution.normalizedPath, "m/44'/60'/0'/0/0")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .legacy)
    }
    func testTronSimpleBIP44PathResolvesAsLegacyFlavor() {
        let resolution = SeedDerivationChain.tron.resolve(path: "m/44'/195'/0'")
        XCTAssertEqual(resolution.normalizedPath, "m/44'/195'/0'")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .legacy)
    }
}
@MainActor
final class BitcoinCashDerivationSupportTests: XCTestCase {
    func testBitcoinCashDerivationPresetsIncludeElectrumLegacyPath() {
        let presets = SeedDerivationChain.bitcoinCash.presetOptions
        XCTAssertTrue(presets.contains { $0.title == "Electrum Legacy" && $0.path == "m/0" })
    }
    func testBitcoinCashElectrumLegacyPathResolvesAsElectrumLegacyFlavor() {
        let resolution = SeedDerivationChain.bitcoinCash.resolve(path: "m/0")
        XCTAssertEqual(resolution.normalizedPath, "m/0")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .electrumLegacy)
    }
}
@MainActor
final class XRPDerivationSupportTests: XCTestCase {
    func testXRPPresetsIncludeSimpleBIP44Path() {
        let presets = SeedDerivationChain.xrp.presetOptions
        XCTAssertTrue(presets.contains { $0.title == "Simple BIP44" && $0.path == "m/44'/144'/0'" })
    }
    func testXRPSimpleBIP44PathResolvesAsLegacyFlavor() {
        let resolution = SeedDerivationChain.xrp.resolve(path: "m/44'/144'/0'")
        XCTAssertEqual(resolution.normalizedPath, "m/44'/144'/0'")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .legacy)
    }
}
@MainActor
final class WalletDerivationLayerTests: XCTestCase {
    private let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    func testBitcoinTestnet4ReturnsOnlyRequestedOutputs() throws {
        let result = try WalletDerivationLayer.derive(
            seedPhrase: mnemonic, chain: .bitcoin, network: .testnet4, derivationPath: "m/84'/1'/0'/0/0",
            requestedOutputs: [.address, .publicKey]
        )
        XCTAssertNotNil(result.address)
        XCTAssertTrue(result.address?.hasPrefix("tb1") == true)
        XCTAssertNotNil(result.publicKeyHex)
        XCTAssertNil(result.privateKeyHex)
    }
    func testSolanaMainnetReturnsRequestedSigningMaterial() throws {
        let result = try WalletDerivationLayer.derive(
            seedPhrase: mnemonic, chain: .solana, network: .mainnet, derivationPath: "m/44'/501'/0'/0'",
            requestedOutputs: [.address, .publicKey, .privateKey]
        )
        XCTAssertFalse(result.address?.isEmpty ?? true)
        XCTAssertFalse(result.publicKeyHex?.isEmpty ?? true)
        XCTAssertFalse(result.privateKeyHex?.isEmpty ?? true)
    }
    func testSolanaCustomPathWithoutAddressRequest() throws {
        let result = try WalletDerivationLayer.derive(
            seedPhrase: mnemonic, chain: .solana, network: .mainnet, derivationPath: "m/44'/501'/9'",
            requestedOutputs: [.publicKey, .privateKey]
        )
        XCTAssertNil(result.address)
        XCTAssertFalse(result.publicKeyHex?.isEmpty ?? true)
        XCTAssertFalse(result.privateKeyHex?.isEmpty ?? true)
    }
    func testBitcoinAPIPresetsIncludeTestnet4NativeSegWit() {
        let hasPath = WalletDerivationPresetCatalog.pathPresets(for: .bitcoin).contains { $0.derivationPath == "m/84'/0'/0'/0/0" }
        let hasNetwork = WalletDerivationPresetCatalog.networkPresets(for: .bitcoin).contains {
            $0.network == WalletDerivationNetwork.testnet4.rawValue
        }
        XCTAssertTrue(hasPath)
        XCTAssertTrue(hasNetwork)
        XCTAssertEqual(WalletDerivationPresetCatalog.curve(for: .bitcoin), .secp256k1)
    }
    func testSolanaAPIPresetsIncludeLegacyCurveAndPath() {
        let hasPath = WalletDerivationPresetCatalog.pathPresets(for: .solana).contains { $0.derivationPath == "m/44'/501'/0'" }
        let hasMainnet = WalletDerivationPresetCatalog.networkPresets(for: .solana).contains {
            $0.network == WalletDerivationNetwork.mainnet.rawValue
        }
        XCTAssertTrue(hasPath)
        XCTAssertTrue(hasMainnet)
        XCTAssertEqual(WalletDerivationPresetCatalog.curve(for: .solana), .ed25519)
    }
}
