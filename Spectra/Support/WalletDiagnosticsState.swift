import Foundation
import Combine

final class WalletDiagnosticsState: ObservableObject {
    private static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    private static let operationalLogsDefaultsKey = "operational.logs.v1"
    private static let persistenceEncoder = JSONEncoder()
    private static let persistenceDecoder = JSONDecoder()
    private static let operationalLogTimestampFormatter = ISO8601DateFormatter()

    @Published var chainDegradedMessages: [String: String] = [:] {
        didSet {
            persistChainSyncState()
        }
    }

    @Published var lastGoodChainSyncByName: [String: Date] = [:] {
        didSet {
            persistChainSyncState()
        }
    }

    @Published var operationalLogs: [WalletStore.OperationalLogEvent] = [] {
        didSet {
            persistOperationalLogs()
        }
    }

    init() {
        operationalLogs = loadOperationalLogs()
        let persistedChainSync = loadChainSyncState()
        chainDegradedMessages = persistedChainSync.degradedMessages
        lastGoodChainSyncByName = persistedChainSync.lastGoodSyncByName
    }

    var chainDegradedBanners: [WalletStore.ChainDegradedBanner] {
        chainDegradedMessages
            .keys
            .sorted()
            .map { chainName in
                WalletStore.ChainDegradedBanner(
                    chainName: chainName,
                    message: chainDegradedMessages[chainName] ?? "",
                    lastGoodSyncAt: lastGoodChainSyncByName[chainName]
                )
            }
    }

    func clearOperationalLogs() {
        operationalLogs = []
    }

    func exportOperationalLogsText(
        networkSyncStatusText: String,
        events: [WalletStore.OperationalLogEvent]? = nil
    ) -> String {
        let entries = events ?? operationalLogs
        let header = [
            localizedStoreString("Spectra Operational Logs"),
            localizedStoreFormat("Generated: %@", Self.operationalLogTimestampFormatter.string(from: Date())),
            localizedStoreFormat("Entries: %d", entries.count),
            networkSyncStatusText,
            ""
        ]
        let lines = entries.map { event in
            var parts: [String] = [
                Self.operationalLogTimestampFormatter.string(from: event.timestamp),
                "[\(event.level.rawValue.uppercased())]",
                "[\(event.category)]",
                event.message
            ]
            if let source = event.source, !source.isEmpty {
                parts.append("source=\(source)")
            }
            if let chainName = event.chainName, !chainName.isEmpty {
                parts.append("chain=\(chainName)")
            }
            if let walletID = event.walletID {
                parts.append("wallet=\(walletID.uuidString)")
            }
            if let transactionHash = event.transactionHash, !transactionHash.isEmpty {
                parts.append("tx=\(transactionHash)")
            }
            if let metadata = event.metadata, !metadata.isEmpty {
                parts.append("meta=\(metadata)")
            }
            return parts.joined(separator: " | ")
        }
        return (header + lines).joined(separator: "\n")
    }

    func appendOperationalLog(
        _ level: WalletStore.OperationalLogEvent.Level,
        category: String,
        message: String,
        chainName: String? = nil,
        walletID: UUID? = nil,
        transactionHash: String? = nil,
        source: String? = nil,
        metadata: String? = nil
    ) {
        let event = WalletStore.OperationalLogEvent(
            id: UUID(),
            timestamp: Date(),
            level: level,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            chainName: chainName?.trimmingCharacters(in: .whitespacesAndNewlines),
            walletID: walletID,
            transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source?.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: metadata?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        operationalLogs.insert(event, at: 0)
        if operationalLogs.count > 800 {
            operationalLogs = Array(operationalLogs.prefix(800))
        }
    }

    func markChainHealthy(_ chainName: String) {
        let wasDegraded = chainDegradedMessages[chainName] != nil
        chainDegradedMessages.removeValue(forKey: chainName)
        lastGoodChainSyncByName[chainName] = Date()
        if wasDegraded {
            appendOperationalLog(
                .info,
                category: "Chain Sync",
                message: localizedStoreString("Chain recovered"),
                chainName: chainName,
                source: "network"
            )
        }
    }

    func markChainDegraded(_ chainName: String, detail: String) {
        let suffix: String
        if let lastGood = lastGoodChainSyncByName[chainName] {
            suffix = localizedStoreFormat(" Last good sync: %@.", lastGood.formatted(date: .abbreviated, time: .shortened))
        } else {
            suffix = localizedStoreString(" No prior successful sync yet.")
        }
        chainDegradedMessages[chainName] = "\(detail)\(suffix)"
        appendOperationalLog(
            .warning,
            category: "Chain Sync",
            message: detail,
            chainName: chainName,
            source: "network",
            metadata: suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func loadOperationalLogs() -> [WalletStore.OperationalLogEvent] {
        guard let data = UserDefaults.standard.data(forKey: Self.operationalLogsDefaultsKey),
              let decoded = try? JSONDecoder().decode([WalletStore.OperationalLogEvent].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private func persistOperationalLogs() {
        guard let data = try? JSONEncoder().encode(operationalLogs) else { return }
        UserDefaults.standard.set(data, forKey: Self.operationalLogsDefaultsKey)
    }

    private func persistChainSyncState() {
        let payload = WalletStore.PersistedChainSyncState(
            version: WalletStore.PersistedChainSyncState.currentVersion,
            degradedMessages: chainDegradedMessages,
            lastGoodSyncUnix: Dictionary(
                uniqueKeysWithValues: lastGoodChainSyncByName.map { key, value in
                    (key, value.timeIntervalSince1970)
                }
            )
        )
        guard let data = try? Self.persistenceEncoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.chainSyncStateDefaultsKey)
    }

    private func loadChainSyncState() -> (degradedMessages: [String: String], lastGoodSyncByName: [String: Date]) {
        guard let data = UserDefaults.standard.data(forKey: Self.chainSyncStateDefaultsKey),
              let payload = try? Self.persistenceDecoder.decode(WalletStore.PersistedChainSyncState.self, from: data),
              payload.version == WalletStore.PersistedChainSyncState.currentVersion else {
            return ([:], [:])
        }
        let dates = Dictionary(uniqueKeysWithValues: payload.lastGoodSyncUnix.map { key, value in
            (key, Date(timeIntervalSince1970: value))
        })
        return (payload.degradedMessages, dates)
    }
}
