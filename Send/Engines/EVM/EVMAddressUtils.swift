import Foundation
enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcFailure(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid EVM address."
        case .invalidResponse: return "Unexpected response from EVM provider."
        case .rpcFailure(let detail): return detail
        }}
}
func normalizeEVMAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
func isValidEVMAddress(_ address: String) -> Bool {
    let normalized = normalizeEVMAddress(address)
    guard normalized.count == 42, normalized.hasPrefix("0x") else { return false }
    return normalized.dropFirst(2).allSatisfy(\.isHexDigit)
}
func validateEVMAddress(_ address: String) throws -> String {
    let normalized = normalizeEVMAddress(address)
    guard isValidEVMAddress(normalized) else { throw EthereumWalletEngineError.invalidAddress }
    return normalized
}
func receiveEVMAddress(for address: String) throws -> String {
    try validateEVMAddress(address)
}
