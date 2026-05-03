import Foundation

// MARK: - Private pure helpers (no store state)

private func decodedUTXOFeePreview(chainId: UInt32, address: String, satPerCoin: Double, feeRateSvb: UInt64 = 0) async throws
    -> BitcoinSendPreview
{
    guard
        let preview = try await WalletServiceBridge.shared.fetchUtxoFeePreviewTyped(
            chainId: chainId, address: address, feeRateSvb: feeRateSvb)
    else {
        throw NSError(domain: "UTXOFeePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient funds"])
    }
    return preview
}

private func evmCustomFeeDTO(_ customFees: EthereumCustomFeeConfiguration?) -> EvmCustomFeeConfiguration? {
    customFees.map {
        EvmCustomFeeConfiguration(maxFeePerGasGwei: $0.maxFeePerGasGwei, maxPriorityFeePerGasGwei: $0.maxPriorityFeePerGasGwei)
    }
}

// MARK: - AppState send preview methods

extension AppState {
    func refreshEthereumSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, isEVMChain(selectedSendCoin.chainName),
            let fromAddress = resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName), let amount = Double(sendAmount),
            ((selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB")
                ? amount >= 0 : amount > 0)
        else {
            ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
            return
        }
        if let customEthereumNonceValidationError = customEthereumNonceValidationError {
            sendError = customEthereumNonceValidationError
            ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDestination: String
        if trimmedDestination.isEmpty {
            previewDestination = fromAddress
        } else {
            if AddressValidation.isValid(trimmedDestination, kind: "evm") {
                previewDestination = normalizeEVMAddress(trimmedDestination)
            } else if selectedSendCoin.chainName == "Ethereum", isENSNameCandidate(trimmedDestination) {
                do {
                    guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmedDestination) else {
                        ethereumSendPreview = nil
                        preparingChains.remove("Ethereum")
                        return
                    }
                    previewDestination = resolved
                    sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    ethereumSendPreview = nil
                    preparingChains.remove("Ethereum")
                    return
                }
            } else {
                ethereumSendPreview = nil
                preparingChains.remove("Ethereum")
                return
            }
        }
        guard !preparingChains.contains("Ethereum") else {
            pendingEthereumSendPreviewRefresh = true
            return
        }
        preparingChains.insert("Ethereum")
        defer {
            preparingChains.remove("Ethereum")
            if pendingEthereumSendPreviewRefresh {
                pendingEthereumSendPreviewRefresh = false
                Task { @MainActor in
                    await self.refreshEthereumSendPreview()
                }
            }
        }
        guard let chainId = SpectraChainID.id(for: selectedSendCoin.chainName) else {
            ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
            return
        }
        do {
            let assemblyToken: EvmSupportedToken? = supportedEVMToken(for: selectedSendCoin).map {
                EvmSupportedToken(symbol: $0.symbol, contractAddress: $0.contractAddress, decimals: UInt32($0.decimals))
            }
            let assembly: EvmSendAssembly
            do {
                assembly = try prepareEvmSendAssembly(
                    input: EvmSendAssemblyInput(
                        chainName: selectedSendCoin.chainName, symbol: selectedSendCoin.symbol,
                        fromAddress: fromAddress, resolvedDestination: previewDestination, amount: amount,
                        token: assemblyToken
                    ))
            } catch {
                ethereumSendPreview = nil
                preparingChains.remove("Ethereum")
                return
            }
            let valueWei = assembly.valueWei
            let toAddress = assembly.toAddress
            let dataHex = assembly.dataHex
            ethereumSendPreview = try await WalletServiceBridge.shared.fetchEvmSendPreviewTyped(
                chainId: chainId, from: fromAddress, to: toAddress, valueWei: valueWei, dataHex: dataHex,
                explicitNonce: explicitEthereumNonce().map(Int64.init),
                customFees: evmCustomFeeDTO(customEthereumFeeConfiguration())
            )
            if ethereumSendPreview != nil {
                sendError = nil
                clearSendVerificationNotice()
            }
        } catch {
            if isCancelledRequest(error) { return }
            ethereumSendPreview = nil
            sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }
    }
    func refreshDogecoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Dogecoin",
            selectedSendCoin.symbol == "DOGE", let amount = parseDogecoinAmountInput(sendAmount), amount > 0
        else {
            dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty, !isValidDogecoinAddressForPolicy(trimmedDestination, networkMode: dogecoinNetworkMode(for: wallet))
        {
            dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        guard !preparingChains.contains("Dogecoin") else {
            pendingDogecoinSendPreviewRefresh = true
            return
        }
        preparingChains.insert("Dogecoin")
        defer {
            preparingChains.remove("Dogecoin")
            if pendingDogecoinSendPreviewRefresh {
                pendingDogecoinSendPreviewRefresh = false
                Task { @MainActor in
                    await self.refreshDogecoinSendPreview()
                }
            }
        }
        guard let address = resolvedDogecoinAddress(for: wallet) else {
            dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        do {
            guard
                let preview = try await WalletServiceBridge.shared.fetchDogecoinSendPreviewTyped(
                    address: address, requestedAmount: amount, feePriority: dogecoinFeePriority.rawValue)
            else {
                dogecoinSendPreview = nil
                sendError = "Insufficient DOGE funds."
                return
            }
            dogecoinSendPreview = preview
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            dogecoinSendPreview = nil
            sendError = "Unable to estimate DOGE fee right now. Check provider health and retry."
        }
    }
    func refreshBitcoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Bitcoin",
            selectedSendCoin.symbol == "BTC", let amount = Double(sendAmount), amount > 0
        else {
            bitcoinSendPreview = nil
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            bitcoinSendPreview = nil
            return
        }
        do {
            if let xpub = wallet.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines), !xpub.isEmpty {
                bitcoinSendPreview = try await WalletServiceBridge.shared.fetchBitcoinHdSendPreviewTyped(xpub: xpub)
            } else if let address = resolvedBitcoinAddress(for: wallet) {
                bitcoinSendPreview = try await decodedUTXOFeePreview(
                    chainId: SpectraChainID.bitcoin, address: address, satPerCoin: 100_000_000
                )
            } else {
                bitcoinSendPreview = nil
            }
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            bitcoinSendPreview = nil
            sendError = "Unable to estimate BTC fee right now. Check provider health and retry."
        }
    }
    private func refreshUTXOSatChainPreview(
        chainName: String, symbol: String, chainId: UInt32, resolveAddress: (ImportedWallet) -> String?,
        setPreview: (BitcoinSendPreview?) -> Void
    ) async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == chainName,
            selectedSendCoin.symbol == symbol, let amount = Double(sendAmount), amount > 0
        else { setPreview(nil); return }
        guard storedSeedPhrase(for: wallet.id) != nil, let sourceAddress = resolveAddress(wallet) else { setPreview(nil); return }
        do {
            setPreview(try await decodedUTXOFeePreview(chainId: chainId, address: sourceAddress, satPerCoin: 100_000_000))
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            setPreview(nil)
            sendError = "Unable to estimate \(symbol) fee right now. Check provider health and retry."
        }
    }
    func refreshBitcoinCashSendPreview() async {
        await refreshUTXOSatChainPreview(
            chainName: "Bitcoin Cash", symbol: "BCH", chainId: SpectraChainID.bitcoinCash,
            resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, setPreview: { self.bitcoinCashSendPreview = $0 })
    }
    func refreshBitcoinSVSendPreview() async {
        await refreshUTXOSatChainPreview(
            chainName: "Bitcoin SV", symbol: "BSV", chainId: SpectraChainID.bitcoinSv,
            resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, setPreview: { self.bitcoinSVSendPreview = $0 })
    }
    func refreshLitecoinSendPreview() async {
        await refreshUTXOSatChainPreview(
            chainName: "Litecoin", symbol: "LTC", chainId: SpectraChainID.litecoin,
            resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, setPreview: { self.litecoinSendPreview = $0 })
    }
    func refreshTronSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Tron",
            (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"), let amount = Double(sendAmount), amount > 0
        else {
            tronSendPreview = nil
            preparingChains.remove("Tron")
            return
        }
        guard let sourceAddress = resolvedTronAddress(for: wallet) else {
            tronSendPreview = nil
            preparingChains.remove("Tron")
            return
        }
        guard !preparingChains.contains("Tron") else { return }
        preparingChains.insert("Tron")
        defer { preparingChains.remove("Tron") }
        do {
            tronSendPreview = try await WalletServiceBridge.shared.fetchTronSendPreviewTyped(
                address: sourceAddress, symbol: selectedSendCoin.symbol, contractAddress: selectedSendCoin.contractAddress ?? ""
            )
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            tronSendPreview = nil
            sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
        }
    }
    // Simple-chain dispatch: Rust owns per-chain defaults (fee raw parsing, priorityLabel,
    // gasBudgetMist, feeStroops, etc.). Swift just resolves address, fetches JSON, and
    // applies the tagged-enum result to the right AppState field.
    private struct SimpleChainConfig {
        let chainId: UInt32
        let rustChain: SimpleChain
        let chainName: String
        let coinCheck: (AppState, Coin) -> Bool
        let resolveAddress: (AppState, ImportedWallet) -> String?
        let applyPreview: (AppState, SimpleChainPreview?) -> Void
        let errorMessage: String
    }
    @MainActor private func refreshSimpleChain(_ cfg: SimpleChainConfig) async {
        guard let wallet = wallet(for: sendWalletID),
            let coin = selectedSendCoin, cfg.coinCheck(self, coin),
            let amount = Double(sendAmount), amount > 0
        else { cfg.applyPreview(self, nil); preparingChains.remove(cfg.chainName); return }
        guard let src = cfg.resolveAddress(self, wallet)
        else { cfg.applyPreview(self, nil); preparingChains.remove(cfg.chainName); return }
        guard !preparingChains.contains(cfg.chainName) else { return }
        preparingChains.insert(cfg.chainName); defer { preparingChains.remove(cfg.chainName) }
        do {
            let preview = try await WalletServiceBridge.shared.fetchSimpleChainSendPreviewTyped(
                chainId: cfg.chainId, address: src, chain: cfg.rustChain)
            cfg.applyPreview(self, preview)
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            cfg.applyPreview(self, nil)
            sendError = cfg.errorMessage
        }
    }
    func refreshSolanaSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.solana, rustChain: .solana,
                coinCheck: { s, c in s.isSupportedSolanaSendCoin(c) },
                resolveAddress: { s, w in s.resolvedSolanaAddress(for: w) },
                chainName: "Solana",
                applyPreview: { s, p in if case .solana(let pv)? = p { s.solanaSendPreview = pv } else { s.solanaSendPreview = nil } },
                errorMessage: "Unable to estimate Solana fee right now. Check provider health and retry."))
    }
    func refreshXrpSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.xrp, rustChain: .xrp,
                coinCheck: { _, c in c.chainName == "XRP Ledger" && c.symbol == "XRP" },
                resolveAddress: { s, w in s.resolvedXRPAddress(for: w) },
                chainName: "XRP Ledger",
                applyPreview: { s, p in if case .xrp(let pv)? = p { s.xrpSendPreview = pv } else { s.xrpSendPreview = nil } },
                errorMessage: "Unable to estimate XRP fee right now. Check provider health and retry."))
    }
    func refreshStellarSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.stellar, rustChain: .stellar,
                coinCheck: { _, c in c.chainName == "Stellar" && c.symbol == "XLM" },
                resolveAddress: { s, w in s.resolvedStellarAddress(for: w) },
                chainName: "Stellar",
                applyPreview: { s, p in if case .stellar(let pv)? = p { s.stellarSendPreview = pv } else { s.stellarSendPreview = nil } },
                errorMessage: "Unable to estimate Stellar fee right now. Check provider health and retry."))
    }
    func refreshMoneroSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.monero, rustChain: .monero,
                coinCheck: { _, c in c.chainName == "Monero" && c.symbol == "XMR" },
                resolveAddress: { s, w in s.resolvedMoneroAddress(for: w) },
                chainName: "Monero",
                applyPreview: { s, p in if case .monero(let pv)? = p { s.moneroSendPreview = pv } else { s.moneroSendPreview = nil } },
                errorMessage: "Unable to estimate Monero fee right now. Check provider health and retry."))
    }
    func refreshCardanoSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.cardano, rustChain: .cardano,
                coinCheck: { _, c in c.chainName == "Cardano" && c.symbol == "ADA" },
                resolveAddress: { s, w in s.resolvedCardanoAddress(for: w) },
                chainName: "Cardano",
                applyPreview: { s, p in if case .cardano(let pv)? = p { s.cardanoSendPreview = pv } else { s.cardanoSendPreview = nil } },
                errorMessage: "Unable to estimate Cardano fee right now. Check provider health and retry."))
    }
    func refreshSuiSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.sui, rustChain: .sui,
                coinCheck: { _, c in c.chainName == "Sui" && c.symbol == "SUI" },
                resolveAddress: { s, w in s.resolvedSuiAddress(for: w) },
                chainName: "Sui",
                applyPreview: { s, p in if case .sui(let pv)? = p { s.suiSendPreview = pv } else { s.suiSendPreview = nil } },
                errorMessage: "Unable to estimate Sui fee right now. Check provider health and retry."))
    }
    func refreshAptosSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.aptos, rustChain: .aptos,
                coinCheck: { _, c in c.chainName == "Aptos" && c.symbol == "APT" },
                resolveAddress: { s, w in s.resolvedAptosAddress(for: w) },
                chainName: "Aptos",
                applyPreview: { s, p in if case .aptos(let pv)? = p { s.aptosSendPreview = pv } else { s.aptosSendPreview = nil } },
                errorMessage: "Unable to estimate Aptos fee right now. Check provider health and retry."))
    }
    func refreshTonSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.ton, rustChain: .ton,
                coinCheck: { _, c in c.chainName == "TON" && c.symbol == "TON" },
                resolveAddress: { s, w in s.resolvedTONAddress(for: w) },
                chainName: "TON",
                applyPreview: { s, p in if case .ton(let pv)? = p { s.tonSendPreview = pv } else { s.tonSendPreview = nil } },
                errorMessage: "Unable to estimate TON fee right now. Check provider health and retry."))
    }
    func refreshIcpSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.icp, rustChain: .icp,
                coinCheck: { _, c in c.chainName == "Internet Computer" && c.symbol == "ICP" },
                resolveAddress: { s, w in s.resolvedICPAddress(for: w) },
                chainName: "Internet Computer",
                applyPreview: { s, p in if case .icp(let pv)? = p { s.icpSendPreview = pv } else { s.icpSendPreview = nil } },
                errorMessage: "Unable to estimate ICP fee right now. Check provider health and retry."))
    }
    func refreshNearSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.near, rustChain: .near,
                coinCheck: { _, c in c.chainName == "NEAR" && c.symbol == "NEAR" },
                resolveAddress: { s, w in s.resolvedNearAddress(for: w) },
                chainName: "NEAR",
                applyPreview: { s, p in if case .near(let pv)? = p { s.nearSendPreview = pv } else { s.nearSendPreview = nil } },
                errorMessage: "Unable to estimate NEAR fee right now. Check provider health and retry."))
    }
    func refreshPolkadotSendPreview() async {
        await refreshSimpleChain(
            .init(
                chainId: SpectraChainID.polkadot, rustChain: .polkadot,
                coinCheck: { _, c in c.chainName == "Polkadot" && c.symbol == "DOT" },
                resolveAddress: { s, w in s.storedSeedPhrase(for: w.id) != nil ? s.resolvedPolkadotAddress(for: w) : nil },
                chainName: "Polkadot",
                applyPreview: { s, p in if case .polkadot(let pv)? = p { s.polkadotSendPreview = pv } else { s.polkadotSendPreview = nil }
                },
                errorMessage: "Unable to estimate Polkadot fee right now. Check provider health and retry."))
    }
}
