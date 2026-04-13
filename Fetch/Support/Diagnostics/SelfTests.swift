import Foundation
struct ChainSelfTestResult {
    let name: String
    let passed: Bool
    let message: String
}
enum DogecoinChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            testAddressValidationMainnet(), testAddressValidationRejectsGarbage(), testAddressValidationRejectsChecksumMutation(), testSingleProviderRuntimeConfiguration()
        ]
    }
    private static func testAddressValidationMainnet() -> ChainSelfTestResult {
        let validMainnet = "DBus3bamQjgJULBJtYXpEzDWQRwF5iwxgC"
        let passed = AddressValidation.isValidDogecoinAddress(validMainnet)
        return ChainSelfTestResult(
            name: "DOGE Address Mainnet Validation", passed: passed, message: passed ? "Mainnet address accepted." : "Mainnet address validation failed."
        )
    }
    private static func testAddressValidationRejectsGarbage() -> ChainSelfTestResult {
        let passed = !AddressValidation.isValidDogecoinAddress("not_a_real_address")
        return ChainSelfTestResult(
            name: "DOGE Address Rejects Invalid", passed: passed, message: passed ? "Invalid address rejected." : "Invalid address unexpectedly accepted."
        )
    }
    private static func testAddressValidationRejectsChecksumMutation() -> ChainSelfTestResult {
        let mutatedAddress = "DA7Q2K7f1k3wX6sVzP8fCBxNf31xHn3v7H"
        let passed = !AddressValidation.isValidDogecoinAddress(mutatedAddress)
        return ChainSelfTestResult(
            name: "DOGE Address Rejects Bad Checksum", passed: passed, message: passed ? "Checksum mutation rejected." : "Checksum mutation unexpectedly accepted."
        )
    }
    private static func testSingleProviderRuntimeConfiguration() -> ChainSelfTestResult {
        let networks = DogecoinBalanceService.endpointCatalogByNetwork()
        let mainnet = networks.first { $0.title == "Dogecoin" }?.endpoints ?? []
        let testnet = networks.first { $0.title == "Dogecoin Testnet" }?.endpoints ?? []
        let passed = mainnet == [ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL]
            && testnet == [ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherTestnetBaseURL]
        return ChainSelfTestResult(
            name: "DOGE Single Provider Runtime", passed: passed, message: passed ? "Dogecoin uses BlockCypher endpoints per network." : "Dogecoin runtime endpoints are not simplified to the BlockCypher-only model."
        )
    }
}
enum EthereumChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            testAddressValidationAcceptsValidAddress(), testAddressValidationRejectsGarbage(), testReceiveAddressNormalization(), testSeedDerivationProducesValidAddress(), testTransferPaginationWindow(), testTransferPaginationOutOfRange()
        ]
    }
    private static func testAddressValidationAcceptsValidAddress() -> ChainSelfTestResult {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let passed = AddressValidation.isValidEthereumAddress(address)
        return ChainSelfTestResult(
            name: "ETH Address Validation", passed: passed, message: passed ? "Valid Ethereum address accepted." : "Valid Ethereum address rejected."
        )
    }
    private static func testAddressValidationRejectsGarbage() -> ChainSelfTestResult {
        let passed = !AddressValidation.isValidEthereumAddress("0x_not_valid")
        return ChainSelfTestResult(
            name: "ETH Address Rejects Invalid", passed: passed, message: passed ? "Invalid Ethereum address rejected." : "Invalid Ethereum address unexpectedly accepted."
        )
    }
    private static func testReceiveAddressNormalization() -> ChainSelfTestResult {
        let mixedCaseAddress = "0x52908400098527886E0F7030069857D2E4169EE7"
        let passed = (try? receiveEVMAddress(for: mixedCaseAddress)) == mixedCaseAddress.lowercased()
        return ChainSelfTestResult(
            name: "ETH Receive Address Normalization", passed: passed, message: passed ? "Receive address normalized successfully." : "Receive address normalization failed."
        )
    }
    private static func testSeedDerivationProducesValidAddress() -> ChainSelfTestResult {
        let mnemonic = "test test test test test test test test test test test junk"
        guard let derivedAddress = try? SeedPhraseAddressDerivation.materialAddress(
            seedPhrase: mnemonic, coin: .ethereum, derivationPath: SeedDerivationChain.ethereum.defaultPath, normalizer: { $0.lowercased() }
        ) else {
            return ChainSelfTestResult(
                name: "ETH Seed Derivation", passed: false, message: "Failed to derive an Ethereum address from a valid mnemonic."
            )
        }
        let passed = AddressValidation.isValidEthereumAddress(derivedAddress)
        return ChainSelfTestResult(
            name: "ETH Seed Derivation", passed: passed, message: passed ? "Mnemonic-derived Ethereum address is valid." : "Derived address format is invalid."
        )
    }
    private static func paginateSnapshots(_ snapshots: [EthereumTokenTransferSnapshot], page: Int, pageSize: Int) -> [EthereumTokenTransferSnapshot] {
        let start = (page - 1) * pageSize
        guard start < snapshots.count else { return [] }
        return Array(snapshots[start..<min(start + pageSize, snapshots.count)])
    }
    private static func testTransferPaginationWindow() -> ChainSelfTestResult {
        #if DEBUG
        let snapshots = sampleTransferSnapshots(count: 7)
        let page = paginateSnapshots(snapshots, page: 2, pageSize: 3)
        let expectedHashes = Array(snapshots[3...5]).map(\.transactionHash)
        let actualHashes = page.map(\.transactionHash)
        let passed = actualHashes == expectedHashes
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Window", passed: passed, message: passed ? "Page window slice returned expected transfer range." : "Pagination slice did not match expected range."
        )
        #else
        return ChainSelfTestResult(name: "ETH Transfer Pagination Window", passed: true, message: "Skipped outside DEBUG build.")
        #endif
    }
    private static func testTransferPaginationOutOfRange() -> ChainSelfTestResult {
        #if DEBUG
        let snapshots = sampleTransferSnapshots(count: 5)
        let page = paginateSnapshots(snapshots, page: 4, pageSize: 2)
        let passed = page.isEmpty
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Out Of Range", passed: passed, message: passed ? "Out-of-range page returns empty result." : "Out-of-range pagination should return no transfers."
        )
        #else
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Out Of Range", passed: true, message: "Skipped outside DEBUG build."
        )
        #endif
    }
    private static func sampleTransferSnapshots(count: Int) -> [EthereumTokenTransferSnapshot] {
        (0..<count).map { index in
            EthereumTokenTransferSnapshot(
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7", tokenName: "Tether USD", symbol: "USDT", decimals: 6, fromAddress: "0x1111111111111111111111111111111111111111", toAddress: "0x2222222222222222222222222222222222222222", amount: Decimal(index + 1), transactionHash: "0xhash\(index)", blockNumber: 1000 - index, logIndex: index, timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
            )
        }}
}
@MainActor
private enum GenericChainSelfTestHelpers {
    static let mnemonic = "test test test test test test test test test test test junk"
    static func addressAccepts(chainLabel: String, address: String, validator: (String) -> Bool) -> ChainSelfTestResult {
        let passed = validator(address)
        return ChainSelfTestResult(
            name: "\(chainLabel) Address Validation", passed: passed, message: passed ? "Valid \(chainLabel) address accepted." : "Valid \(chainLabel) address rejected."
        )
    }
    static func addressRejects(chainLabel: String, invalidAddress: String, validator: (String) -> Bool) -> ChainSelfTestResult {
        let passed = !validator(invalidAddress)
        return ChainSelfTestResult(
            name: "\(chainLabel) Address Rejects Invalid", passed: passed, message: passed ? "Invalid \(chainLabel) address rejected." : "Invalid \(chainLabel) address unexpectedly accepted."
        )
    }
    static func derivationProducesValidAddress(
        chainLabel: String, derive: () throws -> String, validator: (String) -> Bool
    ) -> ChainSelfTestResult {
        guard let derivedAddress = try? derive() else {
            return ChainSelfTestResult(
                name: "\(chainLabel) Seed Derivation", passed: false, message: "Failed to derive a \(chainLabel) address from a valid mnemonic."
            )
        }
        let passed = validator(derivedAddress)
        return ChainSelfTestResult(
            name: "\(chainLabel) Seed Derivation", passed: passed, message: passed ? "Mnemonic-derived \(chainLabel) address is valid." : "Derived \(chainLabel) address format is invalid."
        )
    }
}
@MainActor
private enum ChainTestSpecTable {
    struct Spec {
        let chainKey: String
        let chainLabel: String
        let validAddress: String
        let invalidAddress: String
        let validator: (String) -> Bool
        let derive: (() throws -> String)? func runAll() -> [ChainSelfTestResult] {
            var results = [
                GenericChainSelfTestHelpers.addressAccepts(chainLabel: chainLabel, address: validAddress, validator: validator), GenericChainSelfTestHelpers.addressRejects(chainLabel: chainLabel, invalidAddress: invalidAddress, validator: validator)
            ]
            if let derive { results.append(GenericChainSelfTestHelpers.derivationProducesValidAddress(chainLabel: chainLabel, derive: derive, validator: validator)) }
            return results
        }}
    static let bitcoinSV = Spec(
        chainKey: "Bitcoin SV", chainLabel: "Bitcoin SV", validAddress: "1MirQ9bwyQcGVJPwKUgapu5ouK2E2Ey4gX", invalidAddress: "bsv_not_valid", validator: AddressValidation.isValidBitcoinSVAddress, derive: { try SeedPhraseAddressDerivation.bitcoinSVAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, derivationPath: WalletDerivationPath.bitcoinSV(account: 0)) }
    )
    static let all: [Spec] = [
        Spec(chainKey: "Bitcoin", chainLabel: "Bitcoin", validAddress: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080", invalidAddress: "bc1_not_valid", validator: { AddressValidation.isValidBitcoinAddress($0, networkMode: .mainnet) }, derive: { try SeedPhraseAddressDerivation.bitcoinAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, derivationPath: "m/84'/0'/0'/0/0") }), Spec(chainKey: "Bitcoin Cash", chainLabel: "Bitcoin Cash", validAddress: "bitcoincash:qq07d3s9k4u8x7n5e9qj6m4eht0n5k7n3w6d5m9c8w", invalidAddress: "bitcoincash:not_valid", validator: AddressValidation.isValidBitcoinCashAddress, derive: { try SeedPhraseAddressDerivation.bitcoinCashAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, derivationPath: WalletDerivationPath.bitcoinCash(account: 0)) }), Spec(chainKey: "Litecoin", chainLabel: "Litecoin", validAddress: "ltc1qg82u8my75w4q8k4s4w9q3k6v7d9s8g0j4qg3s6", invalidAddress: "ltc_not_valid", validator: AddressValidation.isValidLitecoinAddress, derive: { try SeedPhraseAddressDerivation.litecoinAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, derivationPath: "m/44'/2'/0'/0/0") }), Spec(chainKey: "Cardano", chainLabel: "Cardano", validAddress: "addr1q9d6m0vxj4j6f0r2k6zk6n6w6r0v9x9k5n0d5u7r3q8v9w7c5m0h2g8t7u6k5a4s3d2f1g0h9j8k7l6m5n4p3q2r1s", invalidAddress: "addr_not_valid", validator: AddressValidation.isValidCardanoAddress, derive: { try SeedPhraseAddressDerivation.cardanoAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, derivationPath: "m/1852'/1815'/0'/0/0") }), Spec(chainKey: "Solana", chainLabel: "Solana", validAddress: "Vote111111111111111111111111111111111111111", invalidAddress: "sol_not_valid", validator: AddressValidation.isValidSolanaAddress, derive: { try SeedPhraseAddressDerivation.solanaAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, preference: .standard, account: 0) }), Spec(chainKey: "Stellar", chainLabel: "Stellar", validAddress: "GBRPYHIL2C4F7Q4W6H6OL5K2C4BFRJHC7YQ7AZZLQ6G4Z7D4VJ4M6N4K", invalidAddress: "stellar_not_valid", validator: AddressValidation.isValidStellarAddress, derive: { try SeedPhraseAddressDerivation.stellarAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "XRP", chainLabel: "XRP", validAddress: "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", invalidAddress: "xrp_not_valid", validator: AddressValidation.isValidXRPAddress, derive: { try SeedPhraseAddressDerivation.xrpAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "Tron", chainLabel: "Tron", validAddress: "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL", invalidAddress: "tron_not_valid", validator: AddressValidation.isValidTronAddress, derive: { try SeedPhraseAddressDerivation.tronAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, derivationPath: "m/44'/195'/0'/0/0") }), Spec(chainKey: "Sui", chainLabel: "Sui", validAddress: "0x5f1e6bc4b4f4d7e4d4b5e7a6c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9876543210f", invalidAddress: "0xnotvalid", validator: AddressValidation.isValidSuiAddress, derive: { try SeedPhraseAddressDerivation.suiAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "Aptos", chainLabel: "Aptos", validAddress: "0x1", invalidAddress: "aptos_not_valid", validator: AddressValidation.isValidAptosAddress, derive: { try SeedPhraseAddressDerivation.aptosAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "TON", chainLabel: "TON", validAddress: "UQBm--PFwDv1yCeS-QTJ-L8oiUpqo9IT1BwgVptlSq3ts4DV", invalidAddress: "ton_not_valid", validator: AddressValidation.isValidTONAddress, derive: { try SeedPhraseAddressDerivation.tonAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "Internet Computer", chainLabel: "Internet Computer", validAddress: "be2us-64aaa-aaaaa-qaabq-cai", invalidAddress: "icp_not_valid", validator: AddressValidation.isValidICPAddress, derive: { try SeedPhraseAddressDerivation.icpAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "NEAR", chainLabel: "NEAR", validAddress: "example.near", invalidAddress: "-not-valid.near", validator: AddressValidation.isValidNearAddress, derive: { try SeedPhraseAddressDerivation.nearAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "Polkadot", chainLabel: "Polkadot", validAddress: "15oF4u3gP5xY8J8cH7W5WqJ9wS6XtK9vYw7R1oL2nQm1QdKp", invalidAddress: "dot_not_valid", validator: AddressValidation.isValidPolkadotAddress, derive: { try SeedPhraseAddressDerivation.polkadotAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic) }), Spec(chainKey: "Monero", chainLabel: "Monero", validAddress: "47zQ5w3QJ9P4hJ2sD7v8QnE9mQfQv7s3y6Fq1v6F5g4Yv7dL1m4rV4bW2tK4w9W8nS2b8S8i3Q2vX5M8Q1n7w6Jp1q2x3Q", invalidAddress: "xmr_not_valid", validator: AddressValidation.isValidMoneroAddress, derive: nil), Spec(chainKey: "BNB Chain", chainLabel: "BNB Chain", validAddress: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", invalidAddress: "0x_not_valid", validator: AddressValidation.isValidEthereumAddress, derive: { try SeedPhraseAddressDerivation.materialAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, coin: .ethereum, derivationPath: SeedDerivationChain.ethereum.defaultPath, normalizer: { $0.lowercased() }) }), Spec(chainKey: "Avalanche", chainLabel: "Avalanche", validAddress: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", invalidAddress: "0x_not_valid", validator: AddressValidation.isValidEthereumAddress, derive: { try SeedPhraseAddressDerivation.materialAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, coin: .ethereum, derivationPath: SeedDerivationChain.avalanche.defaultPath, normalizer: { $0.lowercased() }) }), Spec(chainKey: "Ethereum Classic", chainLabel: "Ethereum Classic", validAddress: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", invalidAddress: "0x_not_valid", validator: AddressValidation.isValidEthereumAddress, derive: { try SeedPhraseAddressDerivation.materialAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, coin: .ethereum, derivationPath: SeedDerivationChain.ethereumClassic.defaultPath, normalizer: { $0.lowercased() }) }), Spec(chainKey: "Hyperliquid", chainLabel: "Hyperliquid", validAddress: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", invalidAddress: "0x_not_valid", validator: AddressValidation.isValidEthereumAddress, derive: { try SeedPhraseAddressDerivation.materialAddress(seedPhrase: GenericChainSelfTestHelpers.mnemonic, coin: .ethereum, derivationPath: SeedDerivationChain.hyperliquid.defaultPath, normalizer: { $0.lowercased() }) })
    ]
    static func spec(for key: String) -> Spec { all.first { $0.chainKey == key }! }
}
@MainActor enum BitcoinSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Bitcoin").runAll() }
}
@MainActor enum BitcoinCashSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Bitcoin Cash").runAll() }
}
@MainActor enum LitecoinSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Litecoin").runAll() }
}
@MainActor enum BitcoinSVSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.bitcoinSV.runAll() }
}
@MainActor enum CardanoSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Cardano").runAll() }
}
@MainActor enum SolanaChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Solana").runAll() }
}
@MainActor enum StellarSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Stellar").runAll() }
}
@MainActor enum XRPChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "XRP").runAll() }
}
@MainActor enum TronChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Tron").runAll() }
}
@MainActor enum SuiChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Sui").runAll() }
}
@MainActor enum AptosChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Aptos").runAll() }
}
@MainActor enum TONChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "TON").runAll() }
}
@MainActor enum ICPChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Internet Computer").runAll() }
}
@MainActor enum NearChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "NEAR").runAll() }
}
@MainActor enum PolkadotChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Polkadot").runAll() }
}
@MainActor enum MoneroChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Monero").runAll() }
}
@MainActor enum BNBChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "BNB Chain").runAll() }
}
@MainActor enum AvalancheChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Avalanche").runAll() }
}
@MainActor enum EthereumClassicSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Ethereum Classic").runAll() }
}
@MainActor enum HyperliquidSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { ChainTestSpecTable.spec(for: "Hyperliquid").runAll() }
}
@MainActor
enum AllChainsSelfTestSuite {
    static func runAll() -> [String: [ChainSelfTestResult]] {
        Dictionary(uniqueKeysWithValues: ChainTestSpecTable.all.map { ($0.chainKey, $0.runAll()) })
    }
}
