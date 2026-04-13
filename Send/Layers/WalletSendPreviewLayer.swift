import Foundation
extension WalletSendLayer {
    private static func decodedUTXOFeePreview(chainId: UInt32, address: String, satPerCoin: Double, feeRateSvb: UInt64 = 0) async throws -> BitcoinSendPreview {
        let json = try await WalletServiceBridge.shared.fetchUTXOFeePreviewJSON(
            chainId: chainId, address: address, feeRateSvb: feeRateSvb
        )
        let rate = UInt64(WalletSendLayer.rustField("fee_rate_svb", from: json)) ?? 1
        let feeSat = UInt64(WalletSendLayer.rustField("estimated_fee_sat", from: json)) ?? 0
        let txBytes = Int(WalletSendLayer.rustField("estimated_tx_bytes", from: json)) ?? 0
        let inputCount = Int(WalletSendLayer.rustField("selected_input_count", from: json)) ?? 0
        let spendableSat = UInt64(WalletSendLayer.rustField("spendable_balance_sat", from: json)) ?? 0
        let maxSendableSat = UInt64(WalletSendLayer.rustField("max_sendable_sat", from: json)) ?? 0
        guard spendableSat > 0 else { throw NSError(domain: "UTXOFeePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient funds"]) }
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: rate, estimatedNetworkFeeBTC: Double(feeSat) / satPerCoin, feeRateDescription: "\(rate) sat/vB", spendableBalance: Double(spendableSat) / satPerCoin, estimatedTransactionBytes: txBytes, selectedInputCount: inputCount, usesChangeOutput: nil, maxSendable: Double(maxSendableSat) / satPerCoin
        )
    }
    private static func decodeEVMSendPreview(json: String, explicitNonce: Int?, customFees: EthereumCustomFeeConfiguration?) -> EthereumSendPreview? {
        guard let data = json.data(using: .utf8), let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
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
    private static func decodeBitcoinHDSendPreview(balanceJSON: String, feeJSON: String) -> BitcoinSendPreview? {
        guard let balData = balanceJSON.data(using: .utf8), let balObj  = try? JSONSerialization.jsonObject(with: balData) as? [String: Any] else { return nil }
        let confirmedSats = (balObj["confirmed_sats"] as? UInt64) ?? 0
        let feeRateRaw    = WalletSendLayer.rustField("sats_per_vbyte", from: feeJSON)
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
    private static func decodeTronSendPreview(json: String) -> TronSendPreview? {
        guard let data = json.data(using: .utf8), let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let feeTRX        = obj["estimated_fee_trx"]  as? Double ?? 0
        let feeLimitSun   = (obj["fee_limit_sun"] as? Int64) ?? Int64(obj["fee_limit_sun"] as? Int ?? 0)
        let spendable     = obj["spendable_balance"]  as? Double ?? 0
        let maxSendable   = obj["max_sendable"]       as? Double ?? spendable
        let feeDesc       = obj["fee_rate_description"] as? String
        return TronSendPreview(
            estimatedNetworkFeeTRX: feeTRX, feeLimitSun: feeLimitSun, simulationUsed: false, spendableBalance: spendable, feeRateDescription: feeDesc, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: maxSendable
        )
    }
    static func refreshEthereumSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID), let selectedSendCoin = store.selectedSendCoin, store.isEVMChain(selectedSendCoin.chainName), let fromAddress = store.resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName), let amount = Double(store.sendAmount), ((selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB") ? amount >= 0 : amount > 0) else {
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }
        if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
            store.sendError = customEthereumNonceValidationError
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }
        let trimmedDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDestination: String
        if trimmedDestination.isEmpty { previewDestination = fromAddress } else {
            if AddressValidation.isValidEthereumAddress(trimmedDestination) { previewDestination = normalizeEVMAddress(trimmedDestination) } else if selectedSendCoin.chainName == "Ethereum", store.isENSNameCandidate(trimmedDestination) {
                do {
                    guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmedDestination) else {
                        store.ethereumSendPreview = nil
                        store.isPreparingEthereumSend = false
                        return
                    }
                    previewDestination = resolved
                    store.sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    store.ethereumSendPreview = nil
                    store.isPreparingEthereumSend = false
                    return
                }
            } else {
                store.ethereumSendPreview = nil
                store.isPreparingEthereumSend = false
                return
            }}
        guard !store.isPreparingEthereumSend else {
            store.pendingEthereumSendPreviewRefresh = true
            return
        }
        store.isPreparingEthereumSend = true
        defer {
            store.isPreparingEthereumSend = false
            if store.pendingEthereumSendPreviewRefresh {
                store.pendingEthereumSendPreviewRefresh = false
                Task { @MainActor in
                    await refreshEthereumSendPreview(using: store)
                }}}
        guard let chainId = SpectraChainID.id(for: selectedSendCoin.chainName) else {
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
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
            } else if let token = store.supportedEVMToken(for: selectedSendCoin) {
                valueWei = "0"
                toAddress = token.contractAddress
                let toParam = String(repeating: "0", count: 24)
                    + String(previewDestination.dropFirst(2)).lowercased()
                let dataStub = String(repeating: "0", count: 64)
                dataHex = "0xa9059cbb\(toParam)\(dataStub)"
            } else {
                store.ethereumSendPreview = nil
                store.isPreparingEthereumSend = false
                return
            }
            let previewJSON = try await WalletServiceBridge.shared.fetchEVMSendPreviewJSON(
                chainId: chainId, from: fromAddress, to: toAddress, valueWei: valueWei, dataHex: dataHex
            )
            store.ethereumSendPreview = decodeEVMSendPreview(
                json: previewJSON, explicitNonce: store.explicitEthereumNonce(), customFees: store.customEthereumFeeConfiguration()
            )
            if store.ethereumSendPreview != nil {
                store.sendError = nil
                store.clearSendVerificationNotice()
            }
        } catch {
            if store.isCancelledRequest(error) { return }
            store.ethereumSendPreview = nil
            store.sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }}
    static func refreshDogecoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID), let selectedSendCoin = store.selectedSendCoin, selectedSendCoin.chainName == "Dogecoin", selectedSendCoin.symbol == "DOGE", let amount = store.parseDogecoinAmountInput(store.sendAmount), amount > 0 else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }
        let trimmedDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty, !store.isValidDogecoinAddressForPolicy(trimmedDestination, networkMode: store.dogecoinNetworkMode(for: wallet)) {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }
        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }
        guard !store.isPreparingDogecoinSend else {
            store.pendingDogecoinSendPreviewRefresh = true
            return
        }
        store.isPreparingDogecoinSend = true
        defer {
            store.isPreparingDogecoinSend = false
            if store.pendingDogecoinSendPreviewRefresh {
                store.pendingDogecoinSendPreviewRefresh = false
                Task { @MainActor in
                    await refreshDogecoinSendPreview(using: store)
                }}}
        guard let address = store.resolvedDogecoinAddress(for: wallet) else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }
        do {
            let json = try await WalletServiceBridge.shared.fetchUTXOFeePreviewJSON(
                chainId: SpectraChainID.dogecoin, address: address, feeRateSvb: 0
            )
            let rate       = UInt64(WalletSendLayer.rustField("fee_rate_svb", from: json)) ?? 1
            let feeSat     = UInt64(WalletSendLayer.rustField("estimated_fee_sat", from: json)) ?? 0
            let txBytes    = Int(WalletSendLayer.rustField("estimated_tx_bytes", from: json)) ?? 0
            let inputCount = Int(WalletSendLayer.rustField("selected_input_count", from: json)) ?? 0
            let spendSat   = UInt64(WalletSendLayer.rustField("spendable_balance_sat", from: json)) ?? 0
            let maxSat     = UInt64(WalletSendLayer.rustField("max_sendable_sat", from: json)) ?? 0
            let satPerCoin: Double = 100_000_000
            guard spendSat > 0 else {
                store.dogecoinSendPreview = nil
                store.sendError = "Insufficient DOGE funds."
                return
            }
            let feeDOGE = Double(feeSat) / satPerCoin
            store.dogecoinSendPreview = DogecoinSendPreview(
                spendableBalanceDOGE: Double(spendSat) / satPerCoin, requestedAmountDOGE:  amount, estimatedNetworkFeeDOGE: feeDOGE, estimatedFeeRateDOGEPerKB: Double(rate) * 1000 / satPerCoin, estimatedTransactionBytes: txBytes, selectedInputCount: inputCount, usesChangeOutput: spendSat > UInt64(amount * satPerCoin) + feeSat, feePriority: store.dogecoinFeePriority, maxSendableDOGE: Double(maxSat) / satPerCoin, spendableBalance: Double(spendSat) / satPerCoin, feeRateDescription: "\(rate) sat/vB", maxSendable: Double(maxSat) / satPerCoin
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.dogecoinSendPreview = nil
            store.sendError = "Unable to estimate DOGE fee right now. Check provider health and retry."
        }}
    static func refreshBitcoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID), let selectedSendCoin = store.selectedSendCoin, selectedSendCoin.chainName == "Bitcoin", selectedSendCoin.symbol == "BTC", let amount = Double(store.sendAmount), amount > 0 else {
            store.bitcoinSendPreview = nil
            return
        }
        guard store.storedSeedPhrase(for: wallet.id) != nil else {
            store.bitcoinSendPreview = nil
            return
        }
        do {
            if let xpub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines), !xpub.isEmpty {
                async let balanceJSONTask = WalletServiceBridge.shared.fetchBitcoinXpubBalanceJSON(xpub: xpub)
                async let feeJSONTask    = WalletServiceBridge.shared.fetchFeeEstimateJSON(chainId: SpectraChainID.bitcoin)
                let (balanceJSON, feeJSON) = try await (balanceJSONTask, feeJSONTask)
                store.bitcoinSendPreview = decodeBitcoinHDSendPreview(balanceJSON: balanceJSON, feeJSON: feeJSON)
            } else if let address = store.resolvedBitcoinAddress(for: wallet) {
                store.bitcoinSendPreview = try await decodedUTXOFeePreview(
                    chainId: SpectraChainID.bitcoin, address: address, satPerCoin: 100_000_000
                )
            } else { store.bitcoinSendPreview = nil }
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.bitcoinSendPreview = nil
            store.sendError = "Unable to estimate BTC fee right now. Check provider health and retry."
        }}
    private static func refreshUTXOSatChainPreview(
        using store: WalletStore, chainName: String, symbol: String, chainId: UInt32, resolveAddress: (WalletStore, ImportedWallet) -> String?, setPreview: (WalletStore, BitcoinSendPreview?) -> Void
    ) async {
        guard let wallet = store.wallet(for: store.sendWalletID), let selectedSendCoin = store.selectedSendCoin, selectedSendCoin.chainName == chainName, selectedSendCoin.symbol == symbol, let amount = Double(store.sendAmount), amount > 0 else { setPreview(store, nil); return }
        guard store.storedSeedPhrase(for: wallet.id) != nil, let sourceAddress = resolveAddress(store, wallet) else { setPreview(store, nil); return }
        do {
            setPreview(store, try await decodedUTXOFeePreview(chainId: chainId, address: sourceAddress, satPerCoin: 100_000_000))
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            setPreview(store, nil)
            store.sendError = "Unable to estimate \(symbol) fee right now. Check provider health and retry."
        }}
    static func refreshBitcoinCashSendPreview(using store: WalletStore) async {
        await refreshUTXOSatChainPreview(using: store, chainName: "Bitcoin Cash", symbol: "BCH", chainId: SpectraChainID.bitcoinCash, resolveAddress: { $0.resolvedBitcoinCashAddress(for: $1) }, setPreview: { $0.bitcoinCashSendPreview = $1 })
    }
    static func refreshBitcoinSVSendPreview(using store: WalletStore) async {
        await refreshUTXOSatChainPreview(using: store, chainName: "Bitcoin SV", symbol: "BSV", chainId: SpectraChainID.bitcoinSv, resolveAddress: { $0.resolvedBitcoinSVAddress(for: $1) }, setPreview: { $0.bitcoinSVSendPreview = $1 })
    }
    static func refreshLitecoinSendPreview(using store: WalletStore) async {
        await refreshUTXOSatChainPreview(using: store, chainName: "Litecoin", symbol: "LTC", chainId: SpectraChainID.litecoin, resolveAddress: { $0.resolvedLitecoinAddress(for: $1) }, setPreview: { $0.litecoinSendPreview = $1 })
    }
    static func refreshTronSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID), let selectedSendCoin = store.selectedSendCoin, selectedSendCoin.chainName == "Tron", (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"), let amount = Double(store.sendAmount), amount > 0 else {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
            return
        }
        guard let sourceAddress = store.resolvedTronAddress(for: wallet) else {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
            return
        }
        guard !store.isPreparingTronSend else { return }
        store.isPreparingTronSend = true
        defer { store.isPreparingTronSend = false }
        do {
            let previewJSON = try await WalletServiceBridge.shared.fetchTronSendPreviewJSON(
                address: sourceAddress, symbol: selectedSendCoin.symbol, contractAddress: selectedSendCoin.contractAddress ?? ""
            )
            store.tronSendPreview = decodeTronSendPreview(json: previewJSON)
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.tronSendPreview = nil
            store.sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
        }}
    // Decode fields from a normalized simple-chain preview JSON returned by
    // WalletServiceBridge.fetchSimpleChainSendPreviewJSON.
    private struct SimplePreviewFields {
        let feeDisplay: Double
        let feeRaw: String
        let feeRateDescription: String
        let balanceDisplay: Double
        let maxSendable: Double
    }
    private static func decodeSimplePreviewFields(from json: String) -> SimplePreviewFields {
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
    private static func refreshSimpleChainSendPreview<Preview>(
        using store: WalletStore,
        coinCheck: (Coin) -> Bool,
        chainId: UInt32,
        resolveAddress: (WalletStore, ImportedWallet) -> String?,
        preparingKP: WritableKeyPath<WalletStore, Bool>,
        previewKP: WritableKeyPath<WalletStore, Preview?>,
        build: (SimplePreviewFields) -> Preview,
        onError: ((WalletStore, Error) -> Void)? = nil
    ) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              coinCheck(selectedSendCoin),
              let amount = Double(store.sendAmount), amount > 0
        else { store[keyPath: previewKP] = nil; store[keyPath: preparingKP] = false; return }
        guard let src = resolveAddress(store, wallet) else { store[keyPath: previewKP] = nil; store[keyPath: preparingKP] = false; return }
        guard !store[keyPath: preparingKP] else { return }
        store[keyPath: preparingKP] = true; defer { store[keyPath: preparingKP] = false }
        do {
            let p = decodeSimplePreviewFields(from: try await WalletServiceBridge.shared.fetchSimpleChainSendPreviewJSON(chainId: chainId, address: src))
            store[keyPath: previewKP] = build(p); store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            if let onError { onError(store, error) } else { store[keyPath: previewKP] = nil; store.sendError = error.localizedDescription }
        }
    }
    static func refreshSolanaSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { store.isSupportedSolanaSendCoin($0) }, chainId: SpectraChainID.solana,
            resolveAddress: { s, w in s.resolvedSolanaAddress(for: w) },
            preparingKP: \.isPreparingSolanaSend, previewKP: \.solanaSendPreview,
            build: { SolanaSendPreview(estimatedNetworkFeeSOL: $0.feeDisplay, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, _ in s.solanaSendPreview = nil; s.sendError = "Unable to estimate Solana fee right now. Check provider health and retry." })
    }
    static func refreshXRPSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "XRP Ledger" && $0.symbol == "XRP" }, chainId: SpectraChainID.xrp,
            resolveAddress: { s, w in s.resolvedXRPAddress(for: w) },
            preparingKP: \.isPreparingXRPSend, previewKP: \.xrpSendPreview,
            build: { XRPSendPreview(estimatedNetworkFeeXRP: $0.feeDisplay, feeDrops: Int64($0.feeRaw) ?? 12, sequence: 0, lastLedgerSequence: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, _ in s.xrpSendPreview = nil; s.sendError = "Unable to estimate XRP fee right now. Check provider health and retry." })
    }
    static func refreshStellarSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Stellar" && $0.symbol == "XLM" }, chainId: SpectraChainID.stellar,
            resolveAddress: { s, w in s.resolvedStellarAddress(for: w) },
            preparingKP: \.isPreparingStellarSend, previewKP: \.stellarSendPreview,
            build: { StellarSendPreview(estimatedNetworkFeeXLM: $0.feeDisplay, feeStroops: Int64($0.feeRaw) ?? 100, sequence: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, _ in s.stellarSendPreview = nil; s.sendError = "Unable to estimate Stellar fee right now. Check provider health and retry." })
    }
    static func refreshMoneroSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Monero" && $0.symbol == "XMR" }, chainId: SpectraChainID.monero,
            resolveAddress: { s, w in s.resolvedMoneroAddress(for: w) },
            preparingKP: \.isPreparingMoneroSend, previewKP: \.moneroSendPreview,
            build: { MoneroSendPreview(estimatedNetworkFeeXMR: $0.feeDisplay, priorityLabel: "normal", spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, e in s.moneroSendPreview = MoneroSendPreview(estimatedNetworkFeeXMR: 0.0002, priorityLabel: "normal", spendableBalance: 0, feeRateDescription: "normal", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); s.sendError = e.localizedDescription })
    }
    static func refreshCardanoSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Cardano" && $0.symbol == "ADA" }, chainId: SpectraChainID.cardano,
            resolveAddress: { s, w in s.resolvedCardanoAddress(for: w) },
            preparingKP: \.isPreparingCardanoSend, previewKP: \.cardanoSendPreview,
            build: { CardanoSendPreview(estimatedNetworkFeeADA: $0.feeDisplay, ttlSlot: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, e in s.cardanoSendPreview = CardanoSendPreview(estimatedNetworkFeeADA: 0.2, ttlSlot: 0, spendableBalance: 0, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); s.sendError = e.localizedDescription })
    }
    static func refreshSuiSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Sui" && $0.symbol == "SUI" }, chainId: SpectraChainID.sui,
            resolveAddress: { s, w in s.resolvedSuiAddress(for: w) },
            preparingKP: \.isPreparingSuiSend, previewKP: \.suiSendPreview,
            build: { SuiSendPreview(estimatedNetworkFeeSUI: $0.feeDisplay, gasBudgetMist: UInt64($0.feeRaw) ?? 3_000_000, referenceGasPrice: 1_000, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, e in s.suiSendPreview = SuiSendPreview(estimatedNetworkFeeSUI: 0.001, gasBudgetMist: 3_000_000, referenceGasPrice: 1_000, spendableBalance: 0, feeRateDescription: "Reference gas price: 1000", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); s.sendError = e.localizedDescription })
    }
    static func refreshAptosSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Aptos" && $0.symbol == "APT" }, chainId: SpectraChainID.aptos,
            resolveAddress: { s, w in s.resolvedAptosAddress(for: w) },
            preparingKP: \.isPreparingAptosSend, previewKP: \.aptosSendPreview,
            build: { p in let g = UInt64(p.feeRaw) ?? 100; return AptosSendPreview(estimatedNetworkFeeAPT: p.feeDisplay, maxGasAmount: 10_000, gasUnitPriceOctas: g, spendableBalance: p.balanceDisplay, feeRateDescription: "\(g) octas/unit", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: p.maxSendable) },
            onError: { s, e in s.aptosSendPreview = AptosSendPreview(estimatedNetworkFeeAPT: 0.0002, maxGasAmount: 2_000, gasUnitPriceOctas: 100, spendableBalance: 0, feeRateDescription: "100 octas/unit", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); s.sendError = e.localizedDescription })
    }
    static func refreshTONSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "TON" && $0.symbol == "TON" }, chainId: SpectraChainID.ton,
            resolveAddress: { s, w in s.resolvedTONAddress(for: w) },
            preparingKP: \.isPreparingTONSend, previewKP: \.tonSendPreview,
            build: { TONSendPreview(estimatedNetworkFeeTON: $0.feeDisplay, sequenceNumber: 0, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, e in s.tonSendPreview = TONSendPreview(estimatedNetworkFeeTON: 0.005, sequenceNumber: 0, spendableBalance: 0, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); s.sendError = e.localizedDescription })
    }
    static func refreshICPSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Internet Computer" && $0.symbol == "ICP" }, chainId: SpectraChainID.icp,
            resolveAddress: { s, w in s.resolvedICPAddress(for: w) },
            preparingKP: \.isPreparingICPSend, previewKP: \.icpSendPreview,
            build: { ICPSendPreview(estimatedNetworkFeeICP: $0.feeDisplay, feeE8s: UInt64($0.feeRaw) ?? 10_000, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) })
    }
    static func refreshNearSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "NEAR" && $0.symbol == "NEAR" }, chainId: SpectraChainID.near,
            resolveAddress: { s, w in s.resolvedNearAddress(for: w) },
            preparingKP: \.isPreparingNearSend, previewKP: \.nearSendPreview,
            build: { NearSendPreview(estimatedNetworkFeeNEAR: $0.feeDisplay, gasPriceYoctoNear: $0.feeRaw, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRaw, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) },
            onError: { s, e in s.nearSendPreview = NearSendPreview(estimatedNetworkFeeNEAR: 0.00005, gasPriceYoctoNear: "100000000", spendableBalance: 0, feeRateDescription: "100000000", estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0); s.sendError = e.localizedDescription })
    }
    static func refreshPolkadotSendPreview(using store: WalletStore) async {
        await refreshSimpleChainSendPreview(using: store,
            coinCheck: { $0.chainName == "Polkadot" && $0.symbol == "DOT" }, chainId: SpectraChainID.polkadot,
            resolveAddress: { s, w in guard s.storedSeedPhrase(for: w.id) != nil else { return nil }; return s.resolvedPolkadotAddress(for: w) },
            preparingKP: \.isPreparingPolkadotSend, previewKP: \.polkadotSendPreview,
            build: { PolkadotSendPreview(estimatedNetworkFeeDOT: $0.feeDisplay, spendableBalance: $0.balanceDisplay, feeRateDescription: $0.feeRateDescription, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: $0.maxSendable) })
    }
}
