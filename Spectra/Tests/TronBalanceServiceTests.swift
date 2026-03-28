import XCTest
@testable import Spectra

@MainActor
final class TronBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "T" + String(repeating: "A", count: 33)

    func testFetchBalancesParsesTronScanNativeAndTokenBalances() async throws {
        let url = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "balance": 2_000_000,
                "tokens": [[
                    "tokenAbbr": "USDT",
                    "tokenId": TronBalanceService.usdtTronContract,
                    "tokenDecimal": 6,
                    "balance": "1230000",
                    "tokenType": "trc20"
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 2.0, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance, 1.23, accuracy: 0.0000001)
    }

    func testFetchBalancesFallsBackToTronGridWhenTronScanFails() async throws {
        let tronscan1 = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let tronscan2 = "https://apilist.tronscan.org/api/accountv2?address=\(validAddress)"
        let tronscan3 = "https://apilist.tronscan.io/api/accountv2?address=\(validAddress)"
        let tronGrid = "https://api.trongrid.io/v1/accounts/\(validAddress)"

        await testNetworkClient.enqueueFailure(url: tronscan1, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan2, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan3, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            url: tronGrid,
            object: [
                "data": [[
                    "balance": 3_500_000,
                    "trc20": [[TronBalanceService.usdtTronContract: "2500000"]]
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 3.5, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance, 2.5, accuracy: 0.0000001)
    }
}
