# Rust FFI Plan

## Goal

Keep the existing Swift derivation surface alive while moving the derivation core to Rust.

## Foundation added in this pass

- `Rust/Cargo.toml`
- `Rust/src/lib.rs`
- `Rust/include/spectra_derivation.h`
- `WalletRustDerivationBridge.swift`
- Swift FFI ids and request-model mapping

## Current implementation scope

- Rust derivation is narrowed to Bitcoin first.
- Ethereum is intentionally unsupported in the Rust core for now.
- Solana is intentionally unsupported in the Rust core for now.
- Swift remains the active derivation implementation.
- Swift now has a frozen FFI-side request model and enum mapping.

## Frozen ABI ids

### Chain

- `0` = Bitcoin
- `1` = Ethereum
- `2` = Solana

### Network

- `0` = mainnet
- `1` = testnet
- `2` = testnet4
- `3` = signet

### Curve

- `0` = secp256k1
- `1` = ed25519

### Requested outputs bitflags

- `1 << 0` = address
- `1 << 1` = public key
- `1 << 2` = private key

### Derivation algorithm

- `0` = auto
- `1` = BIP-32 secp256k1
- `2` = SLIP-0010 ed25519

### Address algorithm

- `0` = auto
- `1` = Bitcoin
- `2` = EVM
- `3` = Solana

### Public key format

- `0` = auto
- `1` = compressed
- `2` = uncompressed
- `3` = x-only
- `4` = raw

### Script type

- `0` = auto
- `1` = P2PKH
- `2` = P2SH-P2WPKH
- `3` = P2WPKH
- `4` = P2TR
- `5` = account-style

## What is intentionally not done yet

- no Swift call site is switched to Rust
- no Xcode linking is configured yet
- no non-Bitcoin chain derivation logic is implemented in Rust yet
- no Swift derivation file is deleted yet

## Next concrete steps

1. Freeze ABI enum values.
2. Add Swift FFI struct wrappers matching the C header.
3. Make the Bitcoin-only Rust path compile cleanly.
4. Add parity tests against the current Swift Bitcoin output.
5. Implement Ethereum in Rust.
6. Implement Solana in Rust.
