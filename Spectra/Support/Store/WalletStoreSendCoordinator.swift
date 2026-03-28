import Foundation

extension WalletStore {
    var lastSentTransaction: TransactionRecord? {
        get { sendState.lastSentTransaction }
        set { sendState.lastSentTransaction = newValue }
    }

    var lastPendingTransactionRefreshAt: Date? {
        get { sendState.lastPendingTransactionRefreshAt }
        set { sendState.lastPendingTransactionRefreshAt = newValue }
    }

    var ethereumSendPreview: EthereumSendPreview? {
        get { sendState.ethereumSendPreview }
        set { sendState.ethereumSendPreview = newValue }
    }

    var bitcoinSendPreview: BitcoinSendPreview? {
        get { sendState.bitcoinSendPreview }
        set { sendState.bitcoinSendPreview = newValue }
    }

    var bitcoinCashSendPreview: BitcoinSendPreview? {
        get { sendState.bitcoinCashSendPreview }
        set { sendState.bitcoinCashSendPreview = newValue }
    }

    var bitcoinSVSendPreview: BitcoinSendPreview? {
        get { sendState.bitcoinSVSendPreview }
        set { sendState.bitcoinSVSendPreview = newValue }
    }

    var litecoinSendPreview: BitcoinSendPreview? {
        get { sendState.litecoinSendPreview }
        set { sendState.litecoinSendPreview = newValue }
    }

    var dogecoinSendPreview: DogecoinWalletEngine.DogecoinSendPreview? {
        get { sendState.dogecoinSendPreview }
        set { sendState.dogecoinSendPreview = newValue }
    }

    var tronSendPreview: TronSendPreview? {
        get { sendState.tronSendPreview }
        set { sendState.tronSendPreview = newValue }
    }

    var solanaSendPreview: SolanaSendPreview? {
        get { sendState.solanaSendPreview }
        set { sendState.solanaSendPreview = newValue }
    }

    var xrpSendPreview: XRPSendPreview? {
        get { sendState.xrpSendPreview }
        set { sendState.xrpSendPreview = newValue }
    }

    var stellarSendPreview: StellarSendPreview? {
        get { sendState.stellarSendPreview }
        set { sendState.stellarSendPreview = newValue }
    }

    var moneroSendPreview: MoneroSendPreview? {
        get { sendState.moneroSendPreview }
        set { sendState.moneroSendPreview = newValue }
    }

    var cardanoSendPreview: CardanoSendPreview? {
        get { sendState.cardanoSendPreview }
        set { sendState.cardanoSendPreview = newValue }
    }

    var suiSendPreview: SuiSendPreview? {
        get { sendState.suiSendPreview }
        set { sendState.suiSendPreview = newValue }
    }

    var aptosSendPreview: AptosSendPreview? {
        get { sendState.aptosSendPreview }
        set { sendState.aptosSendPreview = newValue }
    }

    var tonSendPreview: TONSendPreview? {
        get { sendState.tonSendPreview }
        set { sendState.tonSendPreview = newValue }
    }

    var icpSendPreview: ICPSendPreview? {
        get { sendState.icpSendPreview }
        set { sendState.icpSendPreview = newValue }
    }

    var nearSendPreview: NearSendPreview? {
        get { sendState.nearSendPreview }
        set { sendState.nearSendPreview = newValue }
    }

    var polkadotSendPreview: PolkadotSendPreview? {
        get { sendState.polkadotSendPreview }
        set { sendState.polkadotSendPreview = newValue }
    }

    var isSendingBitcoin: Bool {
        get { sendState.isSendingBitcoin }
        set { sendState.isSendingBitcoin = newValue }
    }

    var isSendingBitcoinCash: Bool {
        get { sendState.isSendingBitcoinCash }
        set { sendState.isSendingBitcoinCash = newValue }
    }

    var isSendingBitcoinSV: Bool {
        get { sendState.isSendingBitcoinSV }
        set { sendState.isSendingBitcoinSV = newValue }
    }

    var isSendingLitecoin: Bool {
        get { sendState.isSendingLitecoin }
        set { sendState.isSendingLitecoin = newValue }
    }

    var isSendingDogecoin: Bool {
        get { sendState.isSendingDogecoin }
        set { sendState.isSendingDogecoin = newValue }
    }

    var isSendingEthereum: Bool {
        get { sendState.isSendingEthereum }
        set { sendState.isSendingEthereum = newValue }
    }

    var isSendingTron: Bool {
        get { sendState.isSendingTron }
        set { sendState.isSendingTron = newValue }
    }

    var isSendingSolana: Bool {
        get { sendState.isSendingSolana }
        set { sendState.isSendingSolana = newValue }
    }

    var isSendingXRP: Bool {
        get { sendState.isSendingXRP }
        set { sendState.isSendingXRP = newValue }
    }

    var isSendingStellar: Bool {
        get { sendState.isSendingStellar }
        set { sendState.isSendingStellar = newValue }
    }

    var isSendingMonero: Bool {
        get { sendState.isSendingMonero }
        set { sendState.isSendingMonero = newValue }
    }

    var isSendingCardano: Bool {
        get { sendState.isSendingCardano }
        set { sendState.isSendingCardano = newValue }
    }

    var isSendingSui: Bool {
        get { sendState.isSendingSui }
        set { sendState.isSendingSui = newValue }
    }

    var isSendingAptos: Bool {
        get { sendState.isSendingAptos }
        set { sendState.isSendingAptos = newValue }
    }

    var isSendingTON: Bool {
        get { sendState.isSendingTON }
        set { sendState.isSendingTON = newValue }
    }

    var isSendingICP: Bool {
        get { sendState.isSendingICP }
        set { sendState.isSendingICP = newValue }
    }

    var isSendingNear: Bool {
        get { sendState.isSendingNear }
        set { sendState.isSendingNear = newValue }
    }

    var isSendingPolkadot: Bool {
        get { sendState.isSendingPolkadot }
        set { sendState.isSendingPolkadot = newValue }
    }

    var tronLastSendErrorDetails: String? {
        get { sendState.tronLastSendErrorDetails }
        set { sendState.tronLastSendErrorDetails = newValue }
    }

    var tronLastSendErrorAt: Date? {
        get { sendState.tronLastSendErrorAt }
        set { sendState.tronLastSendErrorAt = newValue }
    }
}
