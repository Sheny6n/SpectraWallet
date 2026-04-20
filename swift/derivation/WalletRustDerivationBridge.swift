import Foundation
enum WalletRustDerivationBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case requestCompilationFailed(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain): return "The Rust derivation core does not support \(chain) yet."
        case .requestCompilationFailed(let message): return message
        }
    }
}
enum WalletRustDerivationBridge {
    nonisolated static var isAvailable: Bool { true }
    nonisolated static func makeRequestModel(
        chain: SeedDerivationChain, network: WalletDerivationNetwork, seedPhrase: String, derivationPath: String?, passphrase: String?,
        iterationCount: Int?, hmacKeyString: String?, requestedOutputs: WalletDerivationRequestedOutputs
    ) throws -> WalletRustDerivationRequestModel {
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let curve = WalletDerivationPresetCatalog.curve(for: chain)
        let trimmedPath = derivationPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDerivationPath =
            (trimmedPath?.isEmpty == false)
            ? trimmedPath
            : WalletDerivationPresetCatalog.defaultPath(for: chain, network: network)
        let compiledScriptType = try compileScriptType(from: requestCompilationPreset, derivationPath: resolvedDerivationPath)
        return WalletRustDerivationRequestModel(
            network: network, curve: curve,
            requestedOutputs: requestedOutputs,
            derivationAlgorithm: requestCompilationPreset.derivationAlgorithm,
            addressAlgorithm: requestCompilationPreset.addressAlgorithm,
            publicKeyFormat: requestCompilationPreset.publicKeyFormat, scriptType: compiledScriptType,
            seedPhrase: seedPhrase, derivationPath: resolvedDerivationPath, passphrase: passphrase, hmacKey: hmacKeyString,
            mnemonicWordlist: "english", iterationCount: UInt32(iterationCount ?? 2048)
        )
    }
    nonisolated static func derive(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustDerivationResponseModel {
        let response = try derivationDerive(
            request: UniFfiDerivationRequest(
                chain: nil, network: requestModel.network.rustWireValue, curve: requestModel.curve.rustWireValue,
                requestedOutputs: requestModel.requestedOutputs.rustWireValue,
                derivationAlgorithm: requestModel.derivationAlgorithm.rustWireValue,
                addressAlgorithm: requestModel.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestModel.publicKeyFormat.rustWireValue,
                scriptType: requestModel.scriptType.rustWireValue, seedPhrase: requestModel.seedPhrase,
                derivationPath: requestModel.derivationPath, passphrase: requestModel.passphrase, hmacKey: requestModel.hmacKey,
                mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount, saltPrefix: nil
            ))
        return WalletRustDerivationResponseModel(
            address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex)
    }
    nonisolated static func deriveFromPrivateKey(
        chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet, privateKeyHex: String
    ) throws -> WalletRustDerivationResponseModel {
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let curve = WalletDerivationPresetCatalog.curve(for: chain)
        let scriptType = try compileScriptType(
            from: requestCompilationPreset, derivationPath: WalletDerivationPresetCatalog.defaultPath(for: chain))
        let response = try derivationDeriveFromPrivateKey(
            request: UniFfiPrivateKeyDerivationRequest(
                chain: nil, network: network.rustWireValue, curve: curve.rustWireValue,
                addressAlgorithm: requestCompilationPreset.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestCompilationPreset.publicKeyFormat.rustWireValue,
                scriptType: scriptType.rustWireValue, privateKeyHex: privateKeyHex
            ))
        return WalletRustDerivationResponseModel(
            address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex)
    }
    nonisolated static func buildSigningMaterial(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustSigningMaterialModel
    {
        guard let derivationPath = requestModel.derivationPath else {
            throw WalletRustDerivationBridgeError.requestCompilationFailed("Signing material requires a derivation path.")
        }
        let response = try derivationBuildMaterial(
            request: UniFfiMaterialRequest(
                chain: nil, network: requestModel.network.rustWireValue, curve: requestModel.curve.rustWireValue,
                derivationAlgorithm: requestModel.derivationAlgorithm.rustWireValue,
                addressAlgorithm: requestModel.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestModel.publicKeyFormat.rustWireValue,
                scriptType: requestModel.scriptType.rustWireValue,
                seedPhrase: requestModel.seedPhrase, derivationPath: derivationPath, passphrase: requestModel.passphrase,
                hmacKey: requestModel.hmacKey, mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount,
                saltPrefix: nil
            ))
        return WalletRustSigningMaterialModel(
            address: response.address, privateKeyHex: response.privateKeyHex, derivationPath: response.derivationPath,
            account: response.account, branch: response.branch, index: response.index)
    }
    nonisolated static func buildSigningMaterialFromPrivateKey(
        chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet, privateKeyHex: String, derivationPath: String
    ) throws -> WalletRustSigningMaterialModel {
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let curve = WalletDerivationPresetCatalog.curve(for: chain)
        let scriptType = try compileScriptType(from: requestCompilationPreset, derivationPath: derivationPath)
        let response = try derivationBuildMaterialFromPrivateKey(
            request: UniFfiPrivateKeyMaterialRequest(
                chain: nil, network: network.rustWireValue, curve: curve.rustWireValue,
                addressAlgorithm: requestCompilationPreset.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestCompilationPreset.publicKeyFormat.rustWireValue,
                scriptType: scriptType.rustWireValue,
                privateKeyHex: privateKeyHex, derivationPath: derivationPath
            ))
        return WalletRustSigningMaterialModel(
            address: response.address, privateKeyHex: response.privateKeyHex, derivationPath: response.derivationPath,
            account: response.account, branch: response.branch, index: response.index)
    }
    nonisolated static func deriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) throws -> [String: String] {
        try derivationDeriveAllAddresses(seedPhrase: seedPhrase, chainPaths: chainPaths)
    }
    nonisolated private static func compileScriptType(from preset: WalletDerivationRequestCompilationPreset, derivationPath: String?) throws
        -> AppCoreScriptType
    {
        do {
            return try coreCompileScriptType(preset: preset, derivationPath: derivationPath)
        } catch {
            throw WalletRustDerivationBridgeError.requestCompilationFailed(error.localizedDescription)
        }
    }
}

extension WalletDerivationNetwork {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .mainnet: return 0
        case .testnet: return 1
        case .testnet4: return 2
        case .signet: return 3
        }
    }
}
extension WalletDerivationCurve {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .secp256k1: return 0
        case .ed25519: return 1
        }
    }
}
extension WalletDerivationRequestedOutputs {
    nonisolated var rustWireValue: UInt32 {
        var value: UInt32 = 0
        if contains(.address) { value |= 1 << 0 }
        if contains(.publicKey) { value |= 1 << 1 }
        if contains(.privateKey) { value |= 1 << 2 }
        return value
    }
}
extension AppCoreDerivationAlgorithm {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .bip32Secp256k1: return 1
        case .slip10Ed25519: return 2
        }
    }
}
extension AppCoreAddressAlgorithm {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .bitcoin: return 1
        case .evm: return 2
        case .solana: return 3
        }
    }
}
extension AppCorePublicKeyFormat {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .compressed: return 1
        case .uncompressed: return 2
        case .xOnly: return 3
        case .raw: return 4
        }
    }
}
extension AppCoreScriptType {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .p2pkh: return 1
        case .p2shP2wpkh: return 2
        case .p2wpkh: return 3
        case .p2tr: return 4
        case .account: return 5
        }
    }
}
struct WalletRustDerivationRequestModel: Sendable {
    let network: WalletDerivationNetwork
    let curve: WalletDerivationCurve
    let requestedOutputs: WalletDerivationRequestedOutputs
    let derivationAlgorithm: AppCoreDerivationAlgorithm
    let addressAlgorithm: AppCoreAddressAlgorithm
    let publicKeyFormat: AppCorePublicKeyFormat
    let scriptType: AppCoreScriptType
    let seedPhrase: String
    let derivationPath: String?
    let passphrase: String?
    let hmacKey: String?
    let mnemonicWordlist: String?
    let iterationCount: UInt32
}
struct WalletRustSigningMaterialModel: Sendable {
    let address: String
    let privateKeyHex: String
    let derivationPath: String
    let account: UInt32
    let branch: UInt32
    let index: UInt32
}
struct WalletRustDerivationResponseModel: Sendable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}
