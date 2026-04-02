import Foundation
import CryptoKit

extension DogecoinWalletEngine {
    static func standardScriptPubKey(for address: String) -> Data? {
        guard let decoded = base58CheckDecode(address), !decoded.isEmpty else {
            return nil
        }

        let prefix = decoded[0]
        let hash160 = decoded.dropFirst()
        guard hash160.count == 20 else { return nil }

        switch prefix {
        case 0x1e:
            return Data([0x76, 0xa9, 0x14]) + hash160 + Data([0x88, 0xac])
        case 0x16:
            return Data([0xa9, 0x14]) + hash160 + Data([0x87])
        default:
            return nil
        }
    }

    static func base58CheckDecode(_ string: String) -> Data? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var indexes: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() {
            indexes[character] = index
        }

        var bytes: [UInt8] = [0]
        for character in string {
            guard let value = indexes[character] else { return nil }
            var carry = value
            for idx in bytes.indices {
                let x = Int(bytes[idx]) * 58 + carry
                bytes[idx] = UInt8(x & 0xff)
                carry = x >> 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        var leadingZeroCount = 0
        for character in string where character == "1" {
            leadingZeroCount += 1
        }

        let decoded = Data(repeating: 0, count: leadingZeroCount) + Data(bytes.reversed())
        guard decoded.count >= 5 else { return nil }

        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let firstHash = SHA256.hash(data: payload)
        let secondHash = SHA256.hash(data: Data(firstHash))
        let computedChecksum = Data(secondHash.prefix(4))
        guard checksum.elementsEqual(computedChecksum) else { return nil }

        return Data(payload)
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
