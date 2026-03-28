import Foundation

extension WalletStore {
    var wallets: [ImportedWallet] {
        get { portfolioState.wallets }
        set { portfolioState.wallets = newValue }
    }

    var cachedWalletByID: [UUID: ImportedWallet] {
        get { portfolioState.walletByID }
        set { portfolioState.walletByID = newValue }
    }

    var cachedWalletByIDString: [String: ImportedWallet] {
        get { portfolioState.walletByIDString }
        set { portfolioState.walletByIDString = newValue }
    }

    var cachedIncludedPortfolioWallets: [ImportedWallet] {
        get { portfolioState.includedPortfolioWallets }
        set { portfolioState.includedPortfolioWallets = newValue }
    }

    var cachedIncludedPortfolioHoldings: [Coin] {
        get { portfolioState.includedPortfolioHoldings }
        set { portfolioState.includedPortfolioHoldings = newValue }
    }

    var cachedIncludedPortfolioHoldingsBySymbol: [String: [Coin]] {
        get { portfolioState.includedPortfolioHoldingsBySymbol }
        set { portfolioState.includedPortfolioHoldingsBySymbol = newValue }
    }

    var cachedUniqueWalletPriceRequestCoins: [Coin] {
        get { portfolioState.uniqueWalletPriceRequestCoins }
        set { portfolioState.uniqueWalletPriceRequestCoins = newValue }
    }

    var cachedPortfolio: [Coin] {
        get { portfolioState.portfolio }
        set { portfolioState.portfolio = newValue }
    }

    var cachedAvailableSendCoinsByWalletID: [String: [Coin]] {
        get { portfolioState.availableSendCoinsByWalletID }
        set { portfolioState.availableSendCoinsByWalletID = newValue }
    }

    var cachedAvailableReceiveCoinsByWalletID: [String: [Coin]] {
        get { portfolioState.availableReceiveCoinsByWalletID }
        set { portfolioState.availableReceiveCoinsByWalletID = newValue }
    }

    var cachedAvailableReceiveChainsByWalletID: [String: [String]] {
        get { portfolioState.availableReceiveChainsByWalletID }
        set { portfolioState.availableReceiveChainsByWalletID = newValue }
    }

    var cachedSendEnabledWallets: [ImportedWallet] {
        get { portfolioState.sendEnabledWallets }
        set { portfolioState.sendEnabledWallets = newValue }
    }

    var cachedReceiveEnabledWallets: [ImportedWallet] {
        get { portfolioState.receiveEnabledWallets }
        set { portfolioState.receiveEnabledWallets = newValue }
    }

    var cachedRefreshableChainNames: Set<String> {
        get { portfolioState.refreshableChainNames }
        set { portfolioState.refreshableChainNames = newValue }
    }

    var cachedSigningMaterialWalletIDs: Set<UUID> {
        get { portfolioState.signingMaterialWalletIDs }
        set { portfolioState.signingMaterialWalletIDs = newValue }
    }

    var cachedPrivateKeyBackedWalletIDs: Set<UUID> {
        get { portfolioState.privateKeyBackedWalletIDs }
        set { portfolioState.privateKeyBackedWalletIDs = newValue }
    }
}
