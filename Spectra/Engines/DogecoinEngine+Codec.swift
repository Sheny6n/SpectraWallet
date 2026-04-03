import Foundation
import CryptoKit

extension DogecoinWalletEngine {
    private static let mainnetP2PKHVersion: UInt8 = 0x1e
    private static let testnetP2PKHVersion: UInt8 = 0x71
    private static let mainnetP2SHVersion: UInt8 = 0x16
    private static let testnetP2SHVersion: UInt8 = 0xc4

    static func standardScriptPubKey(for address: String) -> Data? {
        UTXOAddressCodec.legacyScriptPubKey(
            for: address,
            p2pkhVersions: [mainnetP2PKHVersion, testnetP2PKHVersion],
            p2shVersions: [mainnetP2SHVersion, testnetP2SHVersion]
        )
    }

    static func nativeDerivedAddress(
        privateKeyData: Data,
        networkMode: DogecoinNetworkMode
    ) throws -> String {
        do {
            return try UTXOAddressCodec.legacyP2PKHAddress(
                privateKeyData: privateKeyData,
                version: p2pkhVersion(for: networkMode)
            )
        } catch {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
    }

    static func p2pkhVersion(for networkMode: DogecoinNetworkMode) -> UInt8 {
        switch networkMode {
        case .mainnet:
            return mainnetP2PKHVersion
        case .testnet:
            return testnetP2PKHVersion
        }
    }

    static func computeTXID(fromRawHex rawHex: String) -> String {
        guard let rawData = Data(hexEncoded: rawHex) else {
            return ""
        }
        let firstHash = SHA256.hash(data: rawData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Data(secondHash.reversed()).map { String(format: "%02x", $0) }.joined()
    }
}
