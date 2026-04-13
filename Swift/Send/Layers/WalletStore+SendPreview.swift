import Foundation

// MARK: - Private pure helpers (no store state)

private func decodedUTXOFeePreview(chainId: UInt32, address: String, satPerCoin: Double, feeRateSvb: UInt64 = 0) async throws -> BitcoinSendPreview {
    let json = try await WalletServiceBridge.shared.fetchUTXOFeePreviewJSON(
        chainId: chainId, address: address, feeRateSvb: feeRateSvb
    )
    let rate = UInt64(rustField("fee_rate_svb", from: json)) ?? 1
    let feeSat = UInt64(rustField("estimated_fee_sat", from: json)) ?? 0
    let txBytes = Int(rustField("estimated_tx_bytes", from: json)) ?? 0
    let inputCount = Int(rustField("selected_input_count", from: json)) ?? 0
    let spendableSat = UInt64(rustField("spendable_balance_sat", from: json)) ?? 0
    let maxSendableSat = UInt64(rustField("max_sendable_sat", from: json)) ?? 0
    guard spendableSat > 0 else { throw NSError(domain: "UTXOFeePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient funds"]) }
    return BitcoinSendPreview(
        estimatedFeeRateSatVb: rate, estimatedNetworkFeeBTC: Double(feeSat) / satPerCoin, feeRateDescription: "\(rate) sat/vB", spendableBalance: Double(spendableSat) / satPerCoin, estimatedTransactionBytes: txBytes, selectedInputCount: inputCount, usesChangeOutput: nil, maxSendable: Double(maxSendableSat) / satPerCoin
    )
}

private func decodeEVMSendPreview(json: String, explicitNonce: Int?, customFees: EthereumCustomFeeConfiguration?) -> EthereumSendPreview? {
    guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let nonce         = explicitNonce ?? (obj["nonce"] as? Int ?? 0)
    let gasLimit      = obj["gas_limit"] as? Int ?? 21_000
    let liveFeeGwei   = obj["max_fee_per_gas_gwei"] as? Double ?? 0
    let livePrioGwei  = obj["max_priority_fee_per_gas_gwei"] as? Double ?? 0
    let maxFeeGwei    = customFees?.maxFeePerGasGwei    ?? liveFeeGwei
    let prioFeeGwei   = customFees?.maxPriorityFeePerGasGwei ?? livePrioGwei
    let feeETH: Double
    if customFees != nil {
        let feeWei = Double(gasLimit) * maxFeeGwei * 1_000_000_000
        feeETH = feeWei / 1_000_000_000_000_000_000
    } else { feeETH = obj["estimated_fee_eth"] as? Double ?? 0 }
    let spendableETH  = obj["spendable_eth"] as? Double
    let feeDesc       = customFees != nil ? "Max \(String(format: "%.2f", maxFeeGwei)) gwei / Priority \(String(format: "%.2f", prioFeeGwei)) gwei (custom)" : obj["fee_rate_description"] as? String
    return EthereumSendPreview(
        nonce: nonce, gasLimit: gasLimit, maxFeePerGasGwei: maxFeeGwei, maxPriorityFeePerGasGwei: prioFeeGwei, estimatedNetworkFeeETH: feeETH, spendableBalance: spendableETH, feeRateDescription: feeDesc, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: spendableETH
    )
}

private func decodeBitcoinHDSendPreview(balanceJSON: String, feeJSON: String) -> BitcoinSendPreview? {
    guard let balData = balanceJSON.data(using: .utf8), let balObj = try? JSONSerialization.jsonObject(with: balData) as? [String: Any] else { return nil }
    let confirmedSats = (balObj["confirmed_sats"] as? UInt64) ?? 0
    let feeRateRaw    = rustField("sats_per_vbyte", from: feeJSON)
    let feeRateCeil   = max(1, (Double(feeRateRaw) ?? 1.0).rounded(.up))
    let rateU64       = UInt64(feeRateCeil)
    let estimatedBytes: UInt64 = 250
    let feeSat        = rateU64 * estimatedBytes
    let spendableSat  = confirmedSats > feeSat ? confirmedSats - feeSat : 0
    let satPerBTC     = 100_000_000.0
    return BitcoinSendPreview(
        estimatedFeeRateSatVb: rateU64, estimatedNetworkFeeBTC: Double(feeSat) / satPerBTC, feeRateDescription: "\(rateU64) sat/vB", spendableBalance: Double(confirmedSats) / satPerBTC, estimatedTransactionBytes: Int(estimatedBytes), selectedInputCount: nil, usesChangeOutput: nil, maxSendable: Double(spendableSat) / satPerBTC
    )
}

private func decodeTronSendPreview(json: String) -> TronSendPreview? {
    guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let feeTRX        = obj["estimated_fee_trx"]  as? Double ?? 0
    let feeLimitSun   = (obj["fee_limit_sun"] as? Int64) ?? Int64(obj["fee_limit_sun"] as? Int ?? 0)
    let spendable     = obj["spendable_balance"]  as? Double ?? 0
    let maxSendable   = obj["max_sendable"]       as? Double ?? spendable
    let feeDesc       = obj["fee_rate_description"] as? String
    return TronSendPreview(
        estimatedNetworkFeeTRX: feeTRX, feeLimitSun: feeLimitSun, simulationUsed: false, spendableBalance: spendable, feeRateDescription: feeDesc, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: maxSendable
    )
}

private struct SimplePreviewFields {
    let feeDisplay: Double
    let feeRaw: String
    let feeRateDescription: String
    let balanceDisplay: Double
    let maxSendable: Double
}

private func decodeSimplePreviewFields(from json: String) -> SimplePreviewFields {
    guard let data = json.data(using: .utf8),
          let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return SimplePreviewFields(feeDisplay: 0, feeRaw: "", feeRateDescription: "", balanceDisplay: 0, maxSendable: 0)
    }
    let feeDisplay   = obj["fee_display"]          as? Double ?? Double(obj["fee_display"]          as? String ?? "") ?? 0
    let feeRaw       = obj["fee_raw"]              as? String ?? String(describing: obj["fee_raw"] ?? "")
    let feeRateDesc  = obj["fee_rate_description"] as? String ?? ""
    let balance      = obj["balance_display"]      as? Double ?? Double(obj["balance_display"]      as? String ?? "") ?? 0
    let maxSendable  = obj["max_sendable"]         as? Double ?? max(0, balance - feeDisplay)
    return SimplePreviewFields(feeDisplay: feeDisplay, feeRaw: feeRaw, feeRateDescription: feeRateDesc, balanceDisplay: balance, maxSendable: maxSendable)
}

// MARK: - WalletStore send preview methods

extension WalletStore {
    func refreshEthereumSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, isEVMChain(selectedSendCoin.chainName), let fromAddress = resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName), let amount = Double(sendAmount), ((selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB") ? amount >= 0 : amount > 0) else {
            ethereumSendPreview = nil
            isPreparingEthereumSend = false
            return
        }
        if let customEthereumNonceValidationError = customEthereumNonceValidationError {
            sendError = customEthereumNonceValidationError
            ethereumSendPreview = nil
            isPreparingEthereumSend = false
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDestination: String
        if trimmedDestination.isEmpty { previewDestination = fromAddress } else {
            if AddressValidation.isValidEthereumAddress(trimmedDestination) { previewDestination = normalizeEVMAddress(trimmedDestination) } else if selectedSendCoin.chainName == "Ethereum", isENSNameCandidate(trimmedDestination) {
                do {
                    guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmedDestination) else {
                        ethereumSendPreview = nil
                        isPreparingEthereumSend = false
                        return
                    }
                    previewDestination = resolved
                    sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    ethereumSendPreview = nil
                    isPreparingEthereumSend = false
                    return
                }
            } else {
                ethereumSendPreview = nil
                isPreparingEthereumSend = false
                return
            }}
        guard !isPreparingEthereumSend else {
            pendingEthereumSendPreviewRefresh = true
            return
        }
        isPreparingEthereumSend = true
        defer {
            isPreparingEthereumSend = false
            if pendingEthereumSendPreviewRefresh {
                pendingEthereumSendPreviewRefresh = false
                Task { @MainActor in
                    await self.refreshEthereumSendPreview()
                }}}
        guard let chainId = SpectraChainID.id(for: selectedSendCoin.chainName) else {
            ethereumSendPreview = nil
            isPreparingEthereumSend = false
            return
        }
        do {
            let valueWei: String
            let toAddress: String
            let dataHex: String
            if selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC"
                || selectedSendCoin.symbol == "BNB" || selectedSendCoin.symbol == "AVAX"
                || selectedSendCoin.symbol == "ARB" || selectedSendCoin.symbol == "OP"
                || selectedSendCoin.symbol == "BASE" {
                let amountWei = NSDecimalNumber(decimal: Decimal(amount) * pow(Decimal(10), 18))
                valueWei = amountWei.stringValue
                toAddress = previewDestination
                dataHex = "0x"
            } else if let token = supportedEVMToken(for: selectedSendCoin) {
                valueWei = "0"
                toAddress = token.contractAddress
                let toParam = String(repeating: "0", count: 24)
                    + String(previewDestination.dropFirst(2)).lowercased()
                let dataStub = String(repeating: "0", count: 64)
                dataHex = "0xa9059cbb\(toParam)\(dataStub)"
            } else {
                ethereumSendPreview = nil
                isPreparingEthereumSend = false
                return
            }
            let previewJSON = try await WalletServiceBridge.shared.fetchEVMSendPreviewJSON(
                chainId: chainId, from: fromAddress, to: toAddress, valueWei: valueWei, dataHex: dataHex
            )
            ethereumSendPreview = decodeEVMSendPreview(
                json: previewJSON, explicitNonce: explicitEthereumNonce(), customFees: customEthereumFeeConfiguration()
            )
            if ethereumSendPreview != nil {
                sendError = nil
                clearSendVerificationNotice()
            }
        } catch {
            if isCancelledRequest(error) { return }
            ethereumSendPreview = nil
            sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }}
    func refreshDogecoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Dogecoin", selectedSendCoin.symbol == "DOGE", let amount = parseDogecoinAmountInput(sendAmount), amount > 0 else {
            dogecoinSendPreview = nil
            isPreparingDogecoinSend = false
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty, !isValidDogecoinAddressForPolicy(trimmedDestination, networkMode: dogecoinNetworkMode(for: wallet)) {
            dogecoinSendPreview = nil
            isPreparingDogecoinSend = false
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            dogecoinSendPreview = nil
            isPreparingDogecoinSend = false
            return
        }
        guard !isPreparingDogecoinSend else {
            pendingDogecoinSendPreviewRefresh = true
            return
        }
        isPreparingDogecoinSend = true
        defer {
            isPreparingDogecoinSend = false
            if pendingDogecoinSendPreviewRefresh {
                pendingDogecoinSendPreviewRefresh = false
                Task { @MainActor in
                    await self.refreshDogecoinSendPreview()
                }}}
        guard let address = resolvedDogecoinAddress(for: wallet) else {
            dogecoinSendPreview = nil
            isPreparingDogecoinSend = false
            return
        }
        do {
            let json = try await WalletServiceBridge.shared.fetchUTXOFeePreviewJSON(
                chainId: SpectraChainID.dogecoin, address: address, feeRateSvb: 0
            )
            let rate       = UInt64(rustField("fee_rate_svb", from: json)) ?? 1
            let feeSat     = UInt64(rustField("estimated_fee_sat", from: json)) ?? 0
            let txBytes    = Int(rustField("estimated_tx_bytes", from: json)) ?? 0
            let inputCount = Int(rustField("selected_input_count", from: json)) ?? 0
            let spendSat   = UInt64(rustField("spendable_balance_sat", from: json)) ?? 0
            let maxSat     = UInt64(rustField("max_sendable_sat", from: json)) ?? 0
            let satPerCoin: Double = 100_000_000
            guard spendSat > 0 else {
                dogecoinSendPreview = nil
                sendError = "Insufficient DOGE funds."
                return
            }
            let feeDOGE = Double(feeSat) / satPerCoin
            dogecoinSendPreview = DogecoinSendPreview(
                spendableBalanceDOGE: Double(spendSat) / satPerCoin, requestedAmountDOGE: amount, estimatedNetworkFeeDOGE: feeDOGE, estimatedFeeRateDOGEPerKB: Double(rate) * 1000 / satPerCoin, estimatedTransactionBytes: txBytes, selectedInputCount: inputCount, usesChangeOutput: spendSat > UInt64(amount * satPerCoin) + feeSat, feePriority: dogecoinFeePriority, maxSendableDOGE: Double(maxSat) / satPerCoin, spendableBalance: Double(spendSat) / satPerCoin, feeRateDescription: "\(rate) sat/vB", maxSendable: Double(maxSat) / satPerCoin
            )
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            dogecoinSendPreview = nil
            sendError = "Unable to estimate DOGE fee right now. Check provider health and retry."
        }}
    func refreshBitcoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Bitcoin", selectedSendCoin.symbol == "BTC", let amount = Double(sendAmount), amount > 0 else {
            bitcoinSendPreview = nil
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            bitcoinSendPreview = nil
            return
        }
        do {
            if let xpub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines), !xpub.isEmpty {
                async let balanceJSONTask = WalletServiceBridge.shared.fetchBitcoinXpubBalanceJSON(xpub: xpub)
                async let feeJSONTask    = WalletServiceBridge.shared.fetchFeeEstimateJSON(chainId: SpectraChainID.bitcoin)
                let (balanceJSON, feeJSON) = try await (balanceJSONTask, feeJSONTask)
                bitcoinSendPreview = decodeBitcoinHDSendPreview(balanceJSON: balanceJSON, feeJSON: feeJSON)
            } else if let address = resolvedBitcoinAddress(for: wallet) {
                bitcoinSendPreview = try await decodedUTXOFeePreview(
                    chainId: SpectraChainID.bitcoin, address: address, satPerCoin: 100_000_000
                )
            } else { bitcoinSendPreview = nil }
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            bitcoinSendPreview = nil
            sendError = "Unable to estimate BTC fee right now. Check provider health and retry."
        }}
    private func refreshUTXOSatChainPreview(
        chainName: String, symbol: String, chainId: UInt32, resolveAddress: (ImportedWallet) -> String?, setPreview: (BitcoinSendPreview?) -> Void
    ) async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == chainName, selectedSendCoin.symbol == symbol, let amount = Double(sendAmount), amount > 0 else { setPreview(nil); return }
        guard storedSeedPhrase(for: wallet.id) != nil, let sourceAddress = resolveAddress(wallet) else { setPreview(nil); return }
        do {
            setPreview(try await decodedUTXOFeePreview(chainId: chainId, address: sourceAddress, satPerCoin: 100_000_000))
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            setPreview(nil)
            sendError = "Unable to estimate \(symbol) fee right now. Check provider health and retry."
        }}
    func refreshBitcoinCashSendPreview() async {
        await refreshUTXOSatChainPreview(chainName: "Bitcoin Cash", symbol: "BCH", chainId: SpectraChainID.bitcoinCash, resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, setPreview: { self.bitcoinCashSendPreview = $0 })
    }
    func refreshBitcoinSVSendPreview() async {
        await refreshUTXOSatChainPreview(chainName: "Bitcoin SV", symbol: "BSV", chainId: SpectraChainID.bitcoinSv, resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, setPreview: { self.bitcoinSVSendPreview = $0 })
    }
    func refreshLitecoinSendPreview() async {
        await refreshUTXOSatChainPreview(chainName: "Litecoin", symbol: "LTC", chainId: SpectraChainID.litecoin, resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, setPreview: { self.litecoinSendPreview = $0 })
    }
    func refreshTronSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Tron", (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"), let amount = Double(sendAmount), amount > 0 else {
            tronSendPreview = nil
            isPreparingTronSend = false
            return
        }
        guard let sourceAddress = resolvedTronAddress(for: wallet) else {
            tronSendPreview = nil
            isPreparingTronSend = false
            return
        }
        guard !isPreparingTronSend else { return }
        isPreparingTronSend = true
        defer { isPreparingTronSend = false }
        do {
            let previewJSON = try await WalletServiceBridge.shared.fetchTronSendPreviewJSON(
                address: sourceAddress, symbol: selectedSendCoin.symbol, contractAddress: selectedSendCoin.contractAddress ?? ""
            )
            tronSendPreview = decodeTronSendPreview(json: previewJSON)
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            tronSendPreview = nil
            sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
        }}
    @MainActor private func refreshSimpleChainSendPreview<Preview>(
        coinCheck: (Coin) -> Bool,
        chainId: UInt32,
        resolveAddress: (ImportedWallet) -> String?,
        preparingKP: ReferenceWritableKeyPath<WalletStore, Bool>,
        previewKP: ReferenceWritableKeyPath<WalletStore, Preview?>,
        build: (SimplePreviewFields) -> Preview,
        onError: ((Error) -> Void)? = nil
    ) async {
        guard let wallet = wallet(for: sendWalletID),
              let selectedSendCoin = selectedSendCoin,
              coinCheck(selectedSendCoin),
              let amount = Double(sendAmount), amount > 0
        else { self[keyPath: previewKP] = nil; self[keyPath: preparingKP] = false; return }
        guard let src = resolveAddress(wallet) else { self[keyPath: previewKP] = nil; self[keyPath: preparingKP] = false; return }
        guard !self[keyPath: preparingKP] else { return }
        self[keyPath: preparingKP] = true; defer { self[keyPath: preparingKP] = false }
        do {
            let p = decodeSimplePreviewFields(from: try await WalletServiceBridge.shared.fetchSimpleChainSendPreviewJSON(chainId: chainId, address: src))
            self[keyPath: previewKP] = build(p); sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            if let onError { onError(error) } else { self[keyPath: previewKP] = nil; sendError = error.localizedDescription }
        }
    }
    func refreshSolanaSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { self.isSupportedSolanaSendCoin($0) }, chainId: SpectraChainID.solana,
            resolveAddress: { self.resolvedSolanaAddress(for: $0) },
            preparingKP: \.isPreparingSolanaSend, previewKP: \.solanaSendPreview,
            build: { SolanaSendPreview(estimatedNetworkFeeSOL: $0.feeDisplay, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] _ in self?.solanaSendPreview = nil; self?.sendError = "Unable to estimate Solana fee right now. Check provider health and retry." })
    }
    func refreshXRPSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "XRP Ledger" && $0.symbol == "XRP" }, chainId: SpectraChainID.xrp,
            resolveAddress: { self.resolvedXRPAddress(for: $0) },
            preparingKP: \.isPreparingXRPSend, previewKP: \.xrpSendPreview,
            build: { XRPSendPreview(estimatedNetworkFeeXRP: $0.feeDisplay, feeDrops: Int64($0.feeRaw) ?? 12, sequence: 0, lastLedgerSequence: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] _ in self?.xrpSendPreview = nil; self?.sendError = "Unable to estimate XRP fee right now. Check provider health and retry." })
    }
    func refreshStellarSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Stellar" && $0.symbol == "XLM" }, chainId: SpectraChainID.stellar,
            resolveAddress: { self.resolvedStellarAddress(for: $0) },
            preparingKP: \.isPreparingStellarSend, previewKP: \.stellarSendPreview,
            build: { StellarSendPreview(estimatedNetworkFeeXLM: $0.feeDisplay, feeStroops: Int64($0.feeRaw) ?? 100, sequence: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] _ in self?.stellarSendPreview = nil; self?.sendError = "Unable to estimate Stellar fee right now. Check provider health and retry." })
    }
    func refreshMoneroSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Monero" && $0.symbol == "XMR" }, chainId: SpectraChainID.monero,
            resolveAddress: { self.resolvedMoneroAddress(for: $0) },
            preparingKP: \.isPreparingMoneroSend, previewKP: \.moneroSendPreview,
            build: { MoneroSendPreview(estimatedNetworkFeeXMR: $0.feeDisplay, priorityLabel: "normal", spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] e in self?.moneroSendPreview = MoneroSendPreview(estimatedNetworkFeeXMR: 0.0002, priorityLabel: "normal", spendableBalance: 0, feeRateDescription: "normal", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); self?.sendError = e.localizedDescription })
    }
    func refreshCardanoSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Cardano" && $0.symbol == "ADA" }, chainId: SpectraChainID.cardano,
            resolveAddress: { self.resolvedCardanoAddress(for: $0) },
            preparingKP: \.isPreparingCardanoSend, previewKP: \.cardanoSendPreview,
            build: { CardanoSendPreview(estimatedNetworkFeeADA: $0.feeDisplay, ttlSlot: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] e in self?.cardanoSendPreview = CardanoSendPreview(estimatedNetworkFeeADA: 0.2, ttlSlot: 0, spendableBalance: 0, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); self?.sendError = e.localizedDescription })
    }
    func refreshSuiSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Sui" && $0.symbol == "SUI" }, chainId: SpectraChainID.sui,
            resolveAddress: { self.resolvedSuiAddress(for: $0) },
            preparingKP: \.isPreparingSuiSend, previewKP: \.suiSendPreview,
            build: { SuiSendPreview(estimatedNetworkFeeSUI: $0.feeDisplay, gasBudgetMist: UInt64($0.feeRaw) ?? 3_000_000, referenceGasPrice: 1_000, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] e in self?.suiSendPreview = SuiSendPreview(estimatedNetworkFeeSUI: 0.001, gasBudgetMist: 3_000_000, referenceGasPrice: 1_000, spendableBalance: 0, feeRateDescription: "Reference gas price: 1000", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); self?.sendError = e.localizedDescription })
    }
    func refreshAptosSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Aptos" && $0.symbol == "APT" }, chainId: SpectraChainID.aptos,
            resolveAddress: { self.resolvedAptosAddress(for: $0) },
            preparingKP: \.isPreparingAptosSend, previewKP: \.aptosSendPreview,
            build: { p in let g = UInt64(p.feeRaw) ?? 100; return AptosSendPreview(estimatedNetworkFeeAPT: p.feeDisplay, maxGasAmount: 10_000, gasUnitPriceOctas: g, spendableBalance: p.balanceDisplay, feeRateDescription: "\(g) octas/unit", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: p.maxSendable) },
            onError: { [weak self] e in self?.aptosSendPreview = AptosSendPreview(estimatedNetworkFeeAPT: 0.0002, maxGasAmount: 2_000, gasUnitPriceOctas: 100, spendableBalance: 0, feeRateDescription: "100 octas/unit", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); self?.sendError = e.localizedDescription })
    }
    func refreshTONSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "TON" && $0.symbol == "TON" }, chainId: SpectraChainID.ton,
            resolveAddress: { self.resolvedTONAddress(for: $0) },
            preparingKP: \.isPreparingTONSend, previewKP: \.tonSendPreview,
            build: { TONSendPreview(estimatedNetworkFeeTON: $0.feeDisplay, sequenceNumber: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] e in self?.tonSendPreview = TONSendPreview(estimatedNetworkFeeTON: 0.005, sequenceNumber: 0, spendableBalance: 0, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); self?.sendError = e.localizedDescription })
    }
    func refreshICPSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Internet Computer" && $0.symbol == "ICP" }, chainId: SpectraChainID.icp,
            resolveAddress: { self.resolvedICPAddress(for: $0) },
            preparingKP: \.isPreparingICPSend, previewKP: \.icpSendPreview,
            build: { ICPSendPreview(estimatedNetworkFeeICP: $0.feeDisplay, feeE8s: UInt64($0.feeRaw) ?? 10_000, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) })
    }
    func refreshNearSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "NEAR" && $0.symbol == "NEAR" }, chainId: SpectraChainID.near,
            resolveAddress: { self.resolvedNearAddress(for: $0) },
            preparingKP: \.isPreparingNearSend, previewKP: \.nearSendPreview,
            build: { NearSendPreview(estimatedNetworkFeeNEAR: $0.feeDisplay, gasPriceYoctoNear: $0.feeRaw, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRaw, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { [weak self] e in self?.nearSendPreview = NearSendPreview(estimatedNetworkFeeNEAR: 0.00005, gasPriceYoctoNear: "100000000", spendableBalance: 0, feeRateDescription: "100000000", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); self?.sendError = e.localizedDescription })
    }
    func refreshPolkadotSendPreview() async {
        await refreshSimpleChainSendPreview(
            coinCheck: { $0.chainName == "Polkadot" && $0.symbol == "DOT" }, chainId: SpectraChainID.polkadot,
            resolveAddress: { guard self.storedSeedPhrase(for: $0.id) != nil else { return nil }; return self.resolvedPolkadotAddress(for: $0) },
            preparingKP: \.isPreparingPolkadotSend, previewKP: \.polkadotSendPreview,
            build: { PolkadotSendPreview(estimatedNetworkFeeDOT: $0.feeDisplay, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) })
    }
}
