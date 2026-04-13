import Foundation
struct MoneroHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}
enum MoneroBalanceService {
    typealias TrustedBackend = MoneroProvider.TrustedBackend
    static let backendBaseURLDefaultsKey = MoneroProvider.backendBaseURLDefaultsKey
    static let backendAPIKeyDefaultsKey = MoneroProvider.backendAPIKeyDefaultsKey
    static let defaultBackendID = MoneroProvider.defaultBackendID
    static let defaultPublicBackend = MoneroProvider.defaultPublicBackend
    static let trustedBackends = MoneroProvider.trustedBackends
}
