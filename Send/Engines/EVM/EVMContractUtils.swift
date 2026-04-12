import Foundation

/// Standalone EVM contract-detection utilities.
///
/// Pure-string functions with no SDK dependency. They interpret the raw hex
/// bytecode string returned by `eth_getCode` (via Rust `fetch_evm_code`).

/// Return true iff the `code` string represents non-empty contract bytecode.
/// "0x" and "0x0" both mean the address is an EOA (no deployed code).
func evmHasContractCode(_ code: String) -> Bool {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized != "0x" && normalized != "0x0"
}
