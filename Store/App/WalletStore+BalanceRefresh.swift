import Foundation
import SwiftUI
@MainActor
extension WalletStore {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }
    func initialNativeHolding(chainId: UInt32, amount: Double) -> Coin? {
        switch chainId {
        case SpectraChainID.bitcoin: return Coin(name: "Bitcoin", symbol: "BTC", marketDataID: "1", coinGeckoID: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "B", color: .orange)
        case SpectraChainID.bitcoinCash: return Coin(name: "Bitcoin Cash", symbol: "BCH", marketDataID: "1831", coinGeckoID: "bitcoin-cash", chainName: "Bitcoin Cash", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "BC", color: .orange)
        case SpectraChainID.bitcoinSv: return Coin(name: "Bitcoin SV", symbol: "BSV", marketDataID: "3602", coinGeckoID: "bitcoin-cash-sv", chainName: "Bitcoin SV", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "BS", color: .orange)
        case SpectraChainID.litecoin: return Coin(name: "Litecoin", symbol: "LTC", marketDataID: "2", coinGeckoID: "litecoin", chainName: "Litecoin", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "L", color: .gray)
        case SpectraChainID.dogecoin: return Coin(name: "Dogecoin", symbol: "DOGE", marketDataID: "74", coinGeckoID: "dogecoin", chainName: "Dogecoin", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "D", color: .brown)
        case SpectraChainID.ethereum: return Coin(name: "Ethereum", symbol: "ETH", marketDataID: "1027", coinGeckoID: "ethereum", chainName: "Ethereum", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "E", color: .blue)
        case SpectraChainID.arbitrum: return Coin(name: "Ethereum", symbol: "ETH", marketDataID: "1027", coinGeckoID: "ethereum", chainName: "Arbitrum", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "A", color: .blue)
        case SpectraChainID.optimism: return Coin(name: "Ethereum", symbol: "ETH", marketDataID: "1027", coinGeckoID: "ethereum", chainName: "Optimism", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "O", color: .red)
        case SpectraChainID.base: return Coin(name: "Ethereum", symbol: "ETH", marketDataID: "1027", coinGeckoID: "ethereum", chainName: "Base", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "Ba", color: .blue)
        case SpectraChainID.ethereumClassic: return Coin(name: "Ethereum Classic", symbol: "ETC", marketDataID: "1321", coinGeckoID: "ethereum-classic", chainName: "Ethereum Classic", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "EC", color: .green)
        case SpectraChainID.bsc: return Coin(name: "BNB", symbol: "BNB", marketDataID: "1839", coinGeckoID: "binancecoin", chainName: "BNB Chain", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "BN", color: .yellow)
        case SpectraChainID.hyperliquid: return Coin(name: "Hyperliquid", symbol: "HYPE", marketDataID: "32196", coinGeckoID: "hyperliquid", chainName: "Hyperliquid", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "H", color: .cyan)
        case SpectraChainID.tron: return Coin(name: "Tron", symbol: "TRX", marketDataID: "1958", coinGeckoID: "tron", chainName: "Tron", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "T", color: .red)
        case SpectraChainID.solana: return Coin(name: "Solana", symbol: "SOL", marketDataID: "5426", coinGeckoID: "solana", chainName: "Solana", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "S", color: .purple)
        case SpectraChainID.cardano: return Coin(name: "Cardano", symbol: "ADA", marketDataID: "2010", coinGeckoID: "cardano", chainName: "Cardano", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "C", color: .blue)
        case SpectraChainID.xrp: return Coin(name: "XRP", symbol: "XRP", marketDataID: "52", coinGeckoID: "ripple", chainName: "XRP Ledger", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "X", color: .blue)
        case SpectraChainID.stellar: return Coin(name: "Stellar", symbol: "XLM", marketDataID: "512", coinGeckoID: "stellar", chainName: "Stellar", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "XL", color: .black)
        case SpectraChainID.monero: return Coin(name: "Monero", symbol: "XMR", marketDataID: "328", coinGeckoID: "monero", chainName: "Monero", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "XM", color: .orange)
        case SpectraChainID.sui: return Coin(name: "Sui", symbol: "SUI", marketDataID: "20947", coinGeckoID: "sui", chainName: "Sui", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "Su", color: .blue)
        case SpectraChainID.aptos: return Coin(name: "Aptos", symbol: "APT", marketDataID: "21794", coinGeckoID: "aptos", chainName: "Aptos", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "Ap", color: .blue)
        case SpectraChainID.ton: return Coin(name: "TON", symbol: "TON", marketDataID: "11419", coinGeckoID: "the-open-network", chainName: "TON", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "To", color: .blue)
        case SpectraChainID.icp: return Coin(name: "Internet Computer", symbol: "ICP", marketDataID: "8916", coinGeckoID: "internet-computer", chainName: "ICP", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "IC", color: .purple)
        case SpectraChainID.near: return Coin(name: "NEAR", symbol: "NEAR", marketDataID: "6535", coinGeckoID: "near", chainName: "NEAR", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "N", color: .black)
        case SpectraChainID.polkadot: return Coin(name: "Polkadot", symbol: "DOT", marketDataID: "6636", coinGeckoID: "polkadot", chainName: "Polkadot", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "P", color: .pink)
        case SpectraChainID.avalanche: return Coin(name: "Avalanche", symbol: "AVAX", marketDataID: "5805", coinGeckoID: "avalanche-2", chainName: "Avalanche", tokenStandard: "Native", contractAddress: nil, amount: amount, priceUSD: 0, mark: "Av", color: .red)
        default: return nil
        }}
    func mergeNativeHolding(_ coin: Coin, into holdings: [Coin]) -> [Coin] {
        if let idx = holdings.firstIndex(where: { $0.symbol == coin.symbol && $0.chainName == coin.chainName }) {
            var updated = holdings
            let old = updated[idx]
            updated[idx] = Coin(name: old.name, symbol: old.symbol, marketDataID: old.marketDataID, coinGeckoID: old.coinGeckoID, chainName: old.chainName, tokenStandard: old.tokenStandard, contractAddress: old.contractAddress, amount: coin.amount, priceUSD: old.priceUSD, mark: old.mark, color: old.color)
            return updated
        }
        return holdings + [coin]
    }
    func applyEVMTokenHoldings(_ snapshots: [EthereumTokenBalanceSnapshot], chainName: String, trackedTokens: [EthereumSupportedToken], to holdings: [Coin]) -> [Coin] {
        var result = holdings
        let tokenByContract = Dictionary(uniqueKeysWithValues: trackedTokens.map { ($0.contractAddress.lowercased(), $0) })
        for snap in snapshots {
            let amount = (snap.balance as NSDecimalNumber).doubleValue
            guard amount > 0 else { continue }
            let meta = tokenByContract[snap.contractAddress.lowercased()]
            let coin = Coin(
                name: meta?.name ?? snap.symbol, symbol: snap.symbol, marketDataID: meta?.marketDataID ?? "", coinGeckoID: meta?.coinGeckoID ?? "", chainName: chainName, tokenStandard: "ERC-20", contractAddress: snap.contractAddress, amount: amount, priceUSD: result.first(where: { $0.symbol == snap.symbol && $0.chainName == chainName })?.priceUSD ?? 0, mark: String(snap.symbol.prefix(1)).uppercased(), color: .blue
            )
            result = result.filter { !($0.symbol == snap.symbol && $0.chainName == chainName) }
            result.append(coin)
        }
        return result
    }
    func applySolanaPortfolio(nativeBalance: Double, tokenBalances: [SolanaSPLTokenBalanceSnapshot], to holdings: [Coin]) -> [Coin] {
        var result = holdings
        if let coin = initialNativeHolding(chainId: SpectraChainID.solana, amount: nativeBalance) { result = mergeNativeHolding(coin, into: result) }
        for token in tokenBalances where token.balance > 0 {
            let existing = result.first { $0.chainName == "Solana" && $0.contractAddress == token.mintAddress }
            let coin = Coin(
                name: token.name, symbol: token.symbol, marketDataID: token.marketDataID, coinGeckoID: token.coinGeckoID, chainName: "Solana", tokenStandard: token.tokenStandard, contractAddress: token.mintAddress, amount: token.balance, priceUSD: existing?.priceUSD ?? 0, mark: String(token.symbol.prefix(1)).uppercased(), color: .mint
            )
            result = result.filter { !($0.chainName == "Solana" && $0.contractAddress == token.mintAddress) }
            result.append(coin)
        }
        return result
    }
    func applyTronPortfolio(nativeBalance: Double, tokenBalances: [TronTokenBalanceSnapshot], to holdings: [Coin]) -> [Coin] {
        var result = holdings
        if let coin = initialNativeHolding(chainId: SpectraChainID.tron, amount: nativeBalance) { result = mergeNativeHolding(coin, into: result) }
        for token in tokenBalances where token.balance > 0 {
            let existing = result.first { $0.symbol == token.symbol && $0.chainName == "Tron" }
            let coin = Coin(
                name: token.symbol, symbol: token.symbol, marketDataID: "", coinGeckoID: "", chainName: "Tron", tokenStandard: "TRC-20", contractAddress: token.contractAddress, amount: token.balance, priceUSD: existing?.priceUSD ?? 0, mark: String(token.symbol.prefix(1)).uppercased(), color: .red
            )
            result = result.filter { !($0.symbol == token.symbol && $0.chainName == "Tron") }
            result.append(coin)
        }
        return result
    }
    func configuredEthereumRPCEndpointURL() -> URL? {
        guard ethereumRPCEndpointValidationError == nil else { return nil }
        let trimmedEndpoint = ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return nil }
        return URL(string: trimmedEndpoint)
    }
    func normalizedEtherscanAPIKey() -> String? {
        let trimmed = etherscanAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        let ethereumContext = evmChainContext(for: "Ethereum") ?? .ethereum
        let balanceJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.ethereum, address: address)
        let nativeBalance = RustBalanceDecoder.evmNativeBalance(from: balanceJSON) ?? 0
        let tokenBalances = ethereumContext.isEthereumMainnet
            ? ((try? await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch( chainId: SpectraChainID.ethereum, address: address, tokens: enabledEthereumTrackedTokens().map { ($0.contractAddress, $0.symbol, $0.decimals) }
            )) ?? [])
            : []
        return (nativeBalance, tokenBalances)
    }
    func fetchEVMNativePortfolio(for address: String, chainName: String) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        guard let chain = evmChainContext(for: chainName), let chainId = SpectraChainID.id(for: chainName) else { throw EthereumWalletEngineError.invalidResponse }
        let balanceJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: chainId, address: address)
        let nativeBalance = RustBalanceDecoder.evmNativeBalance(from: balanceJSON) ?? 0
        let tokenBalances: [EthereumTokenBalanceSnapshot]
        let trackedForChain: [EthereumSupportedToken]
        if chain.isEthereumMainnet { trackedForChain = enabledEthereumTrackedTokens() } else if chain == .arbitrum { trackedForChain = enabledArbitrumTrackedTokens() } else if chain == .optimism { trackedForChain = enabledOptimismTrackedTokens() } else if chain == .bnb { trackedForChain = enabledBNBTrackedTokens() } else if chain == .avalanche { trackedForChain = enabledAvalancheTrackedTokens() } else if chain == .hyperliquid { trackedForChain = enabledHyperliquidTrackedTokens() } else { trackedForChain = [] }
        if !trackedForChain.isEmpty {
            tokenBalances = (try? await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch( chainId: chainId, address: address, tokens: trackedForChain.map { ($0.contractAddress, $0.symbol, $0.decimals) }
            )) ?? []
        } else { tokenBalances = [] }
        return (nativeBalance, tokenBalances)
    }
    func applyRustBalance(chainId: UInt32, walletId: String, json: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let walletIdx = wallets.firstIndex(where: { $0.id.uuidString == walletId }), let walletJson = try? await WalletServiceBridge.shared.updateNativeBalance(
                      walletId: walletId, chainId: chainId, balanceJson: json)
            else { return }
            if let merged = mergeRustHoldingAmounts(walletJson, into: wallets[walletIdx]) { wallets[walletIdx] = merged }}}
    private func mergeRustHoldingAmounts(_ walletJson: String, into existing: ImportedWallet) -> ImportedWallet? {
        guard let data = walletJson.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let holdingsArr = obj["holdings"] as? [[String: Any]] else { return nil }
        var holdings = existing.holdings
        for h in holdingsArr {
            guard let symbol = h["symbol"] as? String, let chainName = h["chainName"] as? String, let amount = h["amount"] as? Double, let idx = holdings.firstIndex(where: { $0.symbol == symbol && $0.chainName == chainName })
            else { continue }
            let old = holdings[idx]
            holdings[idx] = Coin(name: old.name, symbol: old.symbol, marketDataID: old.marketDataID, coinGeckoID: old.coinGeckoID, chainName: old.chainName, tokenStandard: old.tokenStandard, contractAddress: old.contractAddress, amount: amount, priceUSD: old.priceUSD, mark: old.mark, color: old.color)
        }
        return walletByReplacingHoldings(existing, with: holdings)
    }
    func updateRefreshEngineEntries() {
        let entries: [[String: Any]] = wallets.compactMap { wallet -> [String: Any]? in
            guard let chainId = SpectraChainID.id(for: wallet.selectedChain), let address = resolvedRefreshAddress(for: wallet) else { return nil }
            return ["chain_id": chainId, "wallet_id": wallet.id.uuidString, "address": address]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries), let json = String(data: data, encoding: .utf8) else { return }
        Task { try? await WalletServiceBridge.shared.setRefreshEntries(json) }}
    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver()
        observer.store = self
        Task {
            try? await WalletServiceBridge.shared.setBalanceObserver(observer)
            try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: 30)
        }
        updateRefreshEngineEntries()
    }
    private func resolvedRefreshAddress(for wallet: ImportedWallet) -> String? {
        switch wallet.selectedChain {
        case "Bitcoin": if let xpub = wallet.bitcoinXPub, !xpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return xpub }
            return resolvedBitcoinAddress(for: wallet)
        case "Ethereum", "Arbitrum", "Optimism", "Avalanche", "BNB Chain", "Hyperliquid", "Ethereum Classic", "Base": return resolvedEVMAddress(for: wallet, chainName: wallet.selectedChain)
        case "Solana":    return resolvedSolanaAddress(for: wallet)
        case "Tron":      return resolvedTronAddress(for: wallet)
        case "Sui":       return resolvedSuiAddress(for: wallet)
        case "Aptos":     return resolvedAptosAddress(for: wallet)
        case "TON":       return resolvedTONAddress(for: wallet)
        case "ICP":       return resolvedICPAddress(for: wallet)
        case "NEAR":      return resolvedNearAddress(for: wallet)
        case "XRP Ledger":   return resolvedXRPAddress(for: wallet)
        case "Stellar":      return resolvedStellarAddress(for: wallet)
        case "Cardano":      return resolvedCardanoAddress(for: wallet)
        case "Polkadot":     return resolvedPolkadotAddress(for: wallet)
        case "Monero":       return resolvedMoneroAddress(for: wallet)
        case "Bitcoin Cash": return resolvedBitcoinCashAddress(for: wallet)
        case "Bitcoin SV":   return resolvedBitcoinSVAddress(for: wallet)
        case "Litecoin":     return resolvedLitecoinAddress(for: wallet)
        case "Dogecoin":     return resolvedDogecoinAddress(for: wallet)
        default:             return nil
        }}
}
