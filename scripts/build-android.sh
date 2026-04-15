#!/usr/bin/env bash
# Compile the ffi crate for Android ABIs and copy .so to jniLibs/.
# Requires: cargo-ndk (cargo install cargo-ndk), Android NDK in ANDROID_NDK_HOME.
# Usage: scripts/build-android.sh [--release]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFI_DIR="${REPO_ROOT}/ffi"
CARGO_TARGET_DIR="${REPO_ROOT}/target"
JNILIBS_DIR="${REPO_ROOT}/kotlin/app/src/main/jniLibs"

PROFILE="debug"
PROFILE_FLAG=""
if [[ "${1:-}" == "--release" ]]; then
  PROFILE="release"
  PROFILE_FLAG="--release"
fi

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
if [[ -f "${HOME}/.cargo/env" ]]; then source "${HOME}/.cargo/env"; fi

if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "error: cargo-ndk required — install with: cargo install cargo-ndk"
  exit 1
fi

declare -A TARGETS=(
  ["aarch64-linux-android"]="arm64-v8a"
  ["armv7-linux-androideabi"]="armeabi-v7a"
  ["x86_64-linux-android"]="x86_64"
)

for target in "${!TARGETS[@]}"; do
  abi="${TARGETS[$target]}"
  echo "Building ${target} (${abi})..."
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR}" cargo ndk \
    --target "${target}" \
    ${PROFILE_FLAG} \
    -- build --manifest-path "${FFI_DIR}/Cargo.toml"
  mkdir -p "${JNILIBS_DIR}/${abi}"
  cp "${CARGO_TARGET_DIR}/${target}/${PROFILE}/libspectra_core.so" \
     "${JNILIBS_DIR}/${abi}/libspectra_core.so"
  echo "  → ${JNILIBS_DIR}/${abi}/libspectra_core.so"
done

echo "Android libraries written to ${JNILIBS_DIR}"
