import Foundation
import SwiftUI
extension WalletStore {
    var sendWalletIDBinding: Binding<String> {
        Binding(get: { self.sendWalletID }, set: { self.sendWalletID = $0 })
    }
    var sendHoldingKeyBinding: Binding<String> {
        Binding(get: { self.sendHoldingKey }, set: { self.sendHoldingKey = $0 })
    }
    var sendAddressBinding: Binding<String> {
        Binding(get: { self.sendAddress }, set: { self.sendAddress = $0 })
    }
    var sendAmountBinding: Binding<String> {
        Binding(get: { self.sendAmount }, set: { self.sendAmount = $0 })
    }
    var isShowingHighRiskSendConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.isShowingHighRiskSendConfirmation }, set: { self.isShowingHighRiskSendConfirmation = $0 }
        )
    }
    var isShowingSendSheetBinding: Binding<Bool> {
        Binding(get: { self.isShowingSendSheet }, set: { self.isShowingSendSheet = $0 })
    }
}
