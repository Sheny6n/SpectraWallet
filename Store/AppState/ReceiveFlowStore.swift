import Foundation
import SwiftUI
extension WalletStore {
    var receiveWalletIDBinding: Binding<String> {
        Binding(get: { self.receiveWalletID }, set: { self.receiveWalletID = $0 })
    }
    var isShowingReceiveSheetBinding: Binding<Bool> {
        Binding(get: { self.isShowingReceiveSheet }, set: { self.isShowingReceiveSheet = $0 })
    }
}
