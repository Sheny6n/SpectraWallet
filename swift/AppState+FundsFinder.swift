import Foundation
import SwiftUI

// MARK: - Funds Finder state types

struct FundsFinderHit: Identifiable {
    let id = UUID()
    let candidate: FundsFinderCandidate
    let balanceDisplay: String
    let smallestUnit: String
}

// MARK: - AppState funds-finder properties and methods

@MainActor
extension AppState {
    // ── Published state (observed by FundsFinderView) ──────────────────────

    var isFundsFinderScanning: Bool {
        get { _isFundsFinderScanning }
        set { _isFundsFinderScanning = newValue }
    }
    var fundsFinderProgress: Double {
        get { _fundsFinderProgress }
        set { _fundsFinderProgress = newValue }
    }
    var fundsFinderHits: [FundsFinderHit] {
        get { _fundsFinderHits }
        set { _fundsFinderHits = newValue }
    }
    var fundsFinderScanError: String? {
        get { _fundsFinderScanError }
        set { _fundsFinderScanError = newValue }
    }
    var fundsFinderCheckedCount: Int {
        get { _fundsFinderCheckedCount }
        set { _fundsFinderCheckedCount = newValue }
    }
    var fundsFinderTotalCount: Int {
        get { _fundsFinderTotalCount }
        set { _fundsFinderTotalCount = newValue }
    }

    // ── Scan ───────────────────────────────────────────────────────────────

    func startFundsFinderScan(seedPhrase: String, passphrase: String?) {
        guard !isFundsFinderScanning else { return }
        isFundsFinderScanning = true
        fundsFinderProgress = 0
        fundsFinderHits = []
        fundsFinderCheckedCount = 0
        fundsFinderTotalCount = 0
        fundsFinderScanError = nil

        _fundsFinderScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let request = FundsFinderRequest(
                    seedPhrase: seedPhrase,
                    passphrase: passphrase?.nonEmpty
                )
                let candidates = try coreGenerateFundsFinderCandidates(request: request)
                self.fundsFinderTotalCount = candidates.count
                await self.checkCandidates(candidates)
            } catch {
                if !Task.isCancelled {
                    self.fundsFinderScanError = error.localizedDescription
                }
            }
            self.isFundsFinderScanning = false
        }
    }

    func cancelFundsFinderScan() {
        _fundsFinderScanTask?.cancel()
        _fundsFinderScanTask = nil
        isFundsFinderScanning = false
    }

    func resetFundsFinder() {
        cancelFundsFinderScan()
        fundsFinderProgress = 0
        fundsFinderHits = []
        fundsFinderCheckedCount = 0
        fundsFinderTotalCount = 0
        fundsFinderScanError = nil
    }

    // ── Private scan logic ─────────────────────────────────────────────────

    private func checkCandidates(_ candidates: [FundsFinderCandidate]) async {
        // Process up to 4 candidates concurrently for speed without hammering endpoints.
        let batchSize = 4
        var index = 0
        let total = candidates.count

        while index < total {
            guard !Task.isCancelled else { return }

            let batch = Array(candidates[index..<min(index + batchSize, total)])
            index += batch.count

            await withTaskGroup(of: FundsFinderHit?.self) { group in
                for candidate in batch {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return await self.checkSingleCandidate(candidate)
                    }
                }
                for await hit in group {
                    fundsFinderCheckedCount += 1
                    if total > 0 {
                        fundsFinderProgress = Double(fundsFinderCheckedCount) / Double(total)
                    }
                    if let hit { fundsFinderHits.append(hit) }
                }
            }
        }
    }

    private func checkSingleCandidate(_ candidate: FundsFinderCandidate) async -> FundsFinderHit? {
        do {
            let summary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                chainId: candidate.chainId,
                address: candidate.address
            )
            // Consider a hit if the smallest-unit balance is non-zero.
            guard summary.smallestUnit != "0", !summary.smallestUnit.isEmpty else { return nil }
            return FundsFinderHit(
                candidate: candidate,
                balanceDisplay: summary.amountDisplay,
                smallestUnit: summary.smallestUnit
            )
        } catch {
            // Network / RPC errors are silently skipped — the user can
            // re-scan or check manually. We don't abort the whole scan.
            return nil
        }
    }
}

// MARK: - Backing storage (AppState must declare these vars)

// These @ObservationIgnored-backed vars live in AppState+FundsFinder because
// they drive the FundsFinder UI exclusively. Each is a plain stored property
// synthesised as a computed pair (get/set to the backing var) in the extension
// above, keeping the main AppState.swift clean.
//
// NOTE: Swift @Observable requires that the backing vars are declared on the
// main AppState class, not in an extension. They are declared in AppState.swift
// (see the "Funds Finder backing vars" section). This extension only exposes
// the API surface and scan logic.

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
