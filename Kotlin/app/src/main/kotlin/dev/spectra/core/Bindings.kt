package dev.spectra.core

// Thin wrapper over the UniFFI-generated Kotlin bindings.
// The generated file (uniffi/spectra_core.kt) is placed here by scripts/bindgen-android.sh.
// This file re-exports types and provides Android-specific conveniences.
object Bindings {
    init {
        System.loadLibrary("spectra_core")
    }
}
