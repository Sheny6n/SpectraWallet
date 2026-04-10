import Foundation

struct UTXOSpendPlan<UTXO> {
    let utxos: [UTXO]
    let totalInputValue: UInt64
    let fee: UInt64
    let change: UInt64
    let usesChangeOutput: Bool
    let estimatedTransactionBytes: Int
}
