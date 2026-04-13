import Foundation
func evmHasContractCode(_ code: String) -> Bool {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized != "0x" && normalized != "0x0"
}
