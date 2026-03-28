import Foundation

extension WalletStore {
    var chainDegradedMessages: [String: String] {
        get { diagnostics.chainDegradedMessages }
        set { diagnostics.chainDegradedMessages = newValue }
    }

    var chainDegradedMessagesByChainID: [WalletChainID: String] {
        get { diagnostics.chainDegradedMessagesByChainID }
        set { diagnostics.chainDegradedMessagesByChainID = newValue }
    }

    var lastGoodChainSyncByName: [String: Date] {
        get { diagnostics.lastGoodChainSyncByName }
        set { diagnostics.lastGoodChainSyncByName = newValue }
    }

    var lastGoodChainSyncByChainID: [WalletChainID: Date] {
        get { diagnostics.lastGoodChainSyncByChainID }
        set { diagnostics.lastGoodChainSyncByChainID = newValue }
    }

    var operationalLogs: [OperationalLogEvent] {
        get { diagnostics.operationalLogs }
        set { diagnostics.operationalLogs = newValue }
    }

    var chainDegradedBanners: [ChainDegradedBanner] {
        diagnostics.chainDegradedBanners
    }

    func markChainDegraded(_ chainName: String, detail: String) {
        diagnostics.markChainDegraded(chainName, detail: detail)
    }
}
