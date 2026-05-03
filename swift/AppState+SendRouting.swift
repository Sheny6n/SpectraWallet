import Foundation
extension AppState {
    private enum SendPreviewKind: String {
        case bitcoin
        case bitcoinCash
        case bitcoinSV
        case litecoin
        case ethereum
        case dogecoin
        case tron
        case solana
        case xrp
        case stellar
        case monero
        case cardano
        case sui
        case aptos
        case ton
        case icp
        case near
        case polkadot
    }
    func refreshSendPreview() async {
        guard let selectedSendCoin = selectedSendCoin else {
            resetAllSendPreviews()
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        await refreshSendDestinationRiskWarning(for: selectedSendCoin)
        let activePreview = plannedPreviewKind(for: selectedSendCoin)
        resetInactiveSendPreviews(except: activePreview)
        switch activePreview {
        case .bitcoin: await refreshBitcoinSendPreview()
        case .bitcoinCash: await refreshBitcoinCashSendPreview()
        case .bitcoinSV: await refreshBitcoinSVSendPreview()
        case .litecoin: await refreshLitecoinSendPreview()
        case .ethereum: await refreshEthereumSendPreview()
        case .dogecoin: await refreshDogecoinSendPreview()
        case .tron: await refreshTronSendPreview()
        case .solana: await refreshSolanaSendPreview()
        case .xrp: await refreshXrpSendPreview()
        case .stellar: await refreshStellarSendPreview()
        case .monero: await refreshMoneroSendPreview()
        case .cardano: await refreshCardanoSendPreview()
        case .sui: await refreshSuiSendPreview()
        case .aptos: await refreshAptosSendPreview()
        case .ton: await refreshTonSendPreview()
        case .icp: await refreshIcpSendPreview()
        case .near: await refreshNearSendPreview()
        case .polkadot: await refreshPolkadotSendPreview()
        case nil: break
        }
    }
    private func plannedPreviewKind(for coin: Coin) -> SendPreviewKind? {
        let request = SendPreviewRoutingRequest(
            asset: rustSendAssetRoutingInput(for: coin)
        )
        let plan = corePlanSendPreviewRouting(request: request)
        guard let activePreviewKind = plan.activePreviewKind else { return nil }
        return SendPreviewKind(rawValue: activePreviewKind)
    }
    private func rustSendAssetRoutingInput(for coin: Coin) -> SendAssetRoutingInput {
        SendAssetRoutingInput(
            chainName: coin.chainName, symbol: coin.symbol, isEvmChain: isEVMChain(coin.chainName),
            supportsSolanaSendCoin: isSupportedSolanaSendCoin(coin), supportsNearTokenSend: isSupportedNearTokenSend(coin)
        )
    }
    private func resetAllSendPreviews() {
        bitcoinSendPreview = nil
        bitcoinCashSendPreview = nil
        bitcoinSVSendPreview = nil
        litecoinSendPreview = nil
        ethereumSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        stellarSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        aptosSendPreview = nil
        tonSendPreview = nil
        icpSendPreview = nil
        nearSendPreview = nil
        polkadotSendPreview = nil
        preparingChains = []
    }
    private func resetInactiveSendPreviews(except activePreview: SendPreviewKind?) {
        if activePreview != .bitcoin { bitcoinSendPreview = nil }
        if activePreview != .bitcoinCash { bitcoinCashSendPreview = nil }
        if activePreview != .bitcoinSV { bitcoinSVSendPreview = nil }
        if activePreview != .litecoin { litecoinSendPreview = nil }
        if activePreview != .ethereum {
            ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
        }
        if activePreview != .dogecoin {
            dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
        }
        if activePreview != .tron {
            tronSendPreview = nil
            preparingChains.remove("Tron")
        }
        if activePreview != .solana {
            solanaSendPreview = nil
            preparingChains.remove("Solana")
        }
        if activePreview != .xrp {
            xrpSendPreview = nil
            preparingChains.remove("XRP Ledger")
        }
        if activePreview != .stellar {
            stellarSendPreview = nil
            preparingChains.remove("Stellar")
        }
        if activePreview != .monero {
            moneroSendPreview = nil
            preparingChains.remove("Monero")
        }
        if activePreview != .cardano {
            cardanoSendPreview = nil
            preparingChains.remove("Cardano")
        }
        if activePreview != .sui {
            suiSendPreview = nil
            preparingChains.remove("Sui")
        }
        if activePreview != .aptos {
            aptosSendPreview = nil
            preparingChains.remove("Aptos")
        }
        if activePreview != .ton {
            tonSendPreview = nil
            preparingChains.remove("TON")
        }
        if activePreview != .icp {
            icpSendPreview = nil
            preparingChains.remove("Internet Computer")
        }
        if activePreview != .near {
            nearSendPreview = nil
            preparingChains.remove("NEAR")
        }
        if activePreview != .polkadot {
            polkadotSendPreview = nil
            preparingChains.remove("Polkadot")
        }
    }
}
