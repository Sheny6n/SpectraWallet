import Foundation
import XCTest
@testable import Spectra
@MainActor
final class DiagnosticsBundleTests: XCTestCase {
    func testExportsAndImportsDiagnosticsBundleJSON() async throws {
        let store = AppState()
        let fileURL = try store.exportDiagnosticsBundle()
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        XCTAssertEqual(imported.schemaVersion, 1)
        XCTAssertFalse(imported.environment.osVersion.isEmpty)
        XCTAssertFalse(imported.bitcoinDiagnosticsJson.isEmpty)
        XCTAssertFalse(imported.litecoinDiagnosticsJson.isEmpty)
        XCTAssertFalse(imported.ethereumDiagnosticsJson.isEmpty)
    }
}
