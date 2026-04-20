import Foundation
nonisolated struct WalletDerivationRequestedOutputs: OptionSet, Sendable {
    let rawValue: Int
    static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
}
enum WalletDerivationCurve: String, Codable {
    case secp256k1
    case ed25519
}
enum WalletDerivationNetwork: String, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet
}
enum WalletDerivationError: LocalizedError {
    case emptyRequestedOutputs
    var errorDescription: String? {
        switch self {
        case .emptyRequestedOutputs: return "At least one derivation output must be requested."
        }
    }
}
enum WalletDerivationLayer {
    static func derive(
        seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet,
        derivationPath: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all
    ) throws -> WalletRustDerivationResponseModel {
        guard !requestedOutputs.isEmpty else { throw WalletDerivationError.emptyRequestedOutputs }
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, network: network, seedPhrase: seedPhrase, derivationPath: derivationPath,
            passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: requestedOutputs
        )
        return try WalletRustDerivationBridge.derive(request)
    }
    static func deriveAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String)
        throws -> String
    {
        let result = try derive(
            seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath, requestedOutputs: .address)
        guard let address = result.address else { throw WalletDerivationError.emptyRequestedOutputs }
        return address
    }
    static func evmSeedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        coreEvmSeedDerivationChainName(chainName: chainName).flatMap(SeedDerivationChain.init(rawValue:))
    }
}
