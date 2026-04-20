import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct ReportProblemView: View {
    private var copy: SettingsContentCopy { .current }
    private var reportProblemURL: URL { URL(string: copy.reportProblemURL) ?? URL(string: "https://example.com/spectra/report-problem")! }
    var body: some View {
        Form {
            Section {
                Text(copy.reportProblemDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Support Link")) {
                Link(destination: reportProblemURL) {
                    Label(copy.reportProblemActionTitle, systemImage: "arrow.up.right.square")
                }
                Text(reportProblemURL.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.navigationTitle(AppLocalization.string("Report a Problem"))
    }
}
