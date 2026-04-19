import Foundation

@MainActor
@Observable
final class SendPreviewStore {
    var ethereumSendPreview: EthereumSendPreview?
    var bitcoinSendPreview: BitcoinSendPreview?
    var bitcoinCashSendPreview: BitcoinSendPreview?
    var bitcoinSVSendPreview: BitcoinSendPreview?
    var litecoinSendPreview: BitcoinSendPreview?
    var dogecoinSendPreview: DogecoinSendPreview?
    var tronSendPreview: TronSendPreview?
    var solanaSendPreview: SolanaSendPreview?
    var xrpSendPreview: XrpSendPreview?
    var stellarSendPreview: StellarSendPreview?
    var moneroSendPreview: MoneroSendPreview?
    var cardanoSendPreview: CardanoSendPreview?
    var suiSendPreview: SuiSendPreview?
    var aptosSendPreview: AptosSendPreview?
    var tonSendPreview: TonSendPreview?
    var icpSendPreview: IcpSendPreview?
    var nearSendPreview: NearSendPreview?
    var polkadotSendPreview: PolkadotSendPreview?
}
