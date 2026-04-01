import Foundation

#if canImport(XCTest)
import SwiftUI
import XCTest
@testable import Spectra

@MainActor
final class WalletStorePlatformBridgeTests: XCTestCase {
    func testEditingWalletNamePreservesExistingHoldings() async {
        let store = WalletStore()
        let existingHolding = Coin(
            name: "Ethereum",
            symbol: "ETH",
            marketDataID: "1027",
            coinGeckoID: "ethereum",
            chainName: "Ethereum",
            tokenStandard: "Native",
            contractAddress: nil,
            amount: 2,
            priceUSD: 3000,
            mark: "E",
            color: .blue
        )
        let wallet = ImportedWallet(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Primary ETH",
            ethereumAddress: "0xabc123",
            selectedChain: "Ethereum",
            holdings: [existingHolding],
            includeInPortfolioTotal: false
        )

        store.wallets = [wallet]
        store.editingWalletID = wallet.id
        store.importDraft.configureForEditing(wallet: wallet)
        store.importDraft.walletName = "Renamed ETH"
        store.importDraft.selectedChainNamesStorage = []

        await store.importWallet()

        XCTAssertEqual(store.wallets.count, 1)
        XCTAssertEqual(store.wallets[0].name, "Renamed ETH")
        XCTAssertEqual(store.wallets[0].holdings.count, 1)
        XCTAssertEqual(store.wallets[0].holdings[0].amount, existingHolding.amount)
        XCTAssertEqual(store.wallets[0].holdings[0].priceUSD, existingHolding.priceUSD)
        XCTAssertFalse(store.wallets[0].includeInPortfolioTotal)
        XCTAssertNil(store.editingWalletID)
        XCTAssertFalse(store.isShowingWalletImporter)
        XCTAssertNil(store.importError)
    }

    func testExportsPlatformSnapshotEnvelopeWithStableFoundationModels() throws {
        let store = WalletStore()
        let wallet = ImportedWallet(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Primary ETH",
            ethereumAddress: "0xabc123",
            selectedChain: "Ethereum",
            holdings: [
                Coin(
                    name: "Ethereum",
                    symbol: "ETH",
                    marketDataID: "1027",
                    coinGeckoID: "ethereum",
                    chainName: "Ethereum",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: 2,
                    priceUSD: 3000,
                    mark: "E",
                    color: .blue
                )
            ]
        )

        store.wallets = [wallet]
        store.addressBook = [
            AddressBookEntry(name: "Cold Wallet", chainName: "Ethereum", address: "0xdef456", note: "vault")
        ]
        store.transactions = [
            TransactionRecord(
                walletID: wallet.id,
                kind: .send,
                status: .pending,
                walletName: wallet.name,
                assetName: "Ethereum",
                symbol: "ETH",
                chainName: "Ethereum",
                amount: 0.5,
                address: "0xfeedbeef",
                transactionHash: "0xdeadbeef"
            )
        ]
        store.livePrices = ["Ethereum|ETH": 3000]

        let snapshot = store.makePlatformSnapshotEnvelope(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(snapshot.schemaVersion, PlatformSnapshotEnvelope.currentSchemaVersion)
        XCTAssertEqual(snapshot.app.walletCount, 1)
        XCTAssertEqual(snapshot.app.transactionCount, 1)
        XCTAssertEqual(snapshot.app.addressBookCount, 1)
        XCTAssertEqual(snapshot.app.wallets.first?.selectedChainID, "ethereum")
        XCTAssertEqual(snapshot.app.wallets.first?.addresses.first?.chainID, "ethereum")
        XCTAssertEqual(snapshot.app.wallets.first?.holdings.first?.valueUSD, 6000)
        XCTAssertEqual(snapshot.app.transactions.first?.chainID, "ethereum")
        XCTAssertEqual(snapshot.app.addressBook.first?.chainID, "ethereum")

        let data = try store.exportPlatformSnapshotJSON(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlatformSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded.app.wallets.first?.name, "Primary ETH")
    }
}
#endif
