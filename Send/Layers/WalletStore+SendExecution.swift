import Foundation

// MARK: - Pure JSON helpers (no store state)

func rustField(_ key: String, from json: String) -> String {
    guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let val = obj[key] else { return "" }
    if let s = val as? String { return s }
    return "\(val)"
}

private func nearToYoctoString(_ near: Double) -> String {
    let formatted = String(format: "%.12f", near)
    let noDecimal = formatted.replacingOccurrences(of: ".", with: "")
    let yoctoStr  = noDecimal + String(repeating: "0", count: 12)
    let trimmed   = yoctoStr.drop(while: { $0 == "0" })
    return trimmed.isEmpty ? "0" : String(trimmed)
}

private func dotToPlanckString(_ dot: Double) -> String { return "\(UInt64((dot * 1e10).rounded()))" }

private func ethToWeiString(_ eth: Double) -> String { return tokenAmountToRawString(eth, decimals: 18) }

private func tokenAmountToRawString(_ amount: Double, decimals: Int) -> String {
    guard amount.isFinite, amount >= 0 else { return "0" }
    let formatted = String(format: "%.9f", amount)
    let parts = formatted.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = parts.first.map(String.init) ?? "0"
    var frac = parts.count > 1 ? String(parts[1]) : ""
    if frac.count < decimals { frac += String(repeating: "0", count: decimals - frac.count) } else if frac.count > decimals { frac = String(frac.prefix(decimals)) }
    let combined = whole + frac
    let trimmed = combined.drop(while: { $0 == "0" })
    return trimmed.isEmpty ? "0" : String(trimmed)
}

private func evmOverridesJSONFragment(nonce: Int?, customFees: EthereumCustomFeeConfiguration?) -> String {
    var fragments: [String] = []
    if let nonce { fragments.append("\"nonce\":\(nonce)") }
    if let customFees {
        let maxFeeWei = UInt64((customFees.maxFeePerGasGwei * 1e9).rounded())
        let priorityWei = UInt64((customFees.maxPriorityFeePerGasGwei * 1e9).rounded())
        fragments.append("\"max_fee_per_gas_wei\":\"\(maxFeeWei)\"")
        fragments.append("\"max_priority_fee_per_gas_wei\":\"\(priorityWei)\"")
    }
    return fragments.isEmpty ? "" : "," + fragments.joined(separator: ",")
}

private func decodeEvmSendResult(_ json: String, fallbackNonce: Int) -> EthereumSendResult {
    let txid = rustField("txid", from: json)
    let rawTxHex = rustField("raw_tx_hex", from: json)
    let nonceString = rustField("nonce", from: json)
    let nonce = Int(nonceString) ?? fallbackNonce
    let gasLimit = Int(rustField("gas_limit", from: json)) ?? 0
    let preview = EthereumSendPreview(
        nonce: nonce, gasLimit: gasLimit, maxFeePerGasGwei: 0, maxPriorityFeePerGasGwei: 0, estimatedNetworkFeeETH: 0, spendableBalance: nil, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: nil
    )
    return EthereumSendResult(
        fromAddress: "", transactionHash: txid, rawTransactionHex: rawTxHex, preview: preview, verificationStatus: .verified
    )
}

// MARK: - WalletStore send execution

extension WalletStore {
    func submitSend() async {
        let destinationInput = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let walletIndex = wallets.firstIndex(where: { $0.id.uuidString == sendWalletID })
        let holdingIndex = walletIndex.flatMap { index in
            wallets[index].holdings.firstIndex(where: { $0.holdingKey == sendHoldingKey })
        }
        let selectedCoin = holdingIndex.flatMap { holdingIndex in
            walletIndex.map { wallets[$0].holdings[holdingIndex] }}
        let preflight: WalletRustSendSubmitPreflightPlan
        do {
            preflight = try WalletRustAppCoreBridge.planSendSubmitPreflight(
                WalletRustSendSubmitPreflightRequest(
                    walletFound: walletIndex != nil, assetFound: holdingIndex != nil, destinationAddress: destinationInput, amountInput: sendAmount, availableBalance: selectedCoin?.amount ?? 0, asset: selectedCoin.map {
                        WalletRustSendAssetRoutingInput(
                            chainName: $0.chainName, symbol: $0.symbol, isEVMChain: isEVMChain($0.chainName), supportsSolanaSendCoin: isSupportedSolanaSendCoin($0), supportsNearTokenSend: isSupportedNearTokenSend($0)
                        )
                    }
                )
            )
        } catch {
            sendError = error.localizedDescription
            return
        }
        guard let walletIndex, let holdingIndex else {
            sendError = "Select an asset"
            return
        }
        let wallet = wallets[walletIndex]
        let holding = wallet.holdings[holdingIndex]
        var destinationAddress = preflight.normalizedDestinationAddress
        var usedENSResolution = false
        let amount = preflight.amount
        if holding.chainName == "Sui", holding.symbol == "SUI" {
            guard !isSendingSui else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedSuiAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Sui signing address from the seed phrase."; return }
            if suiSendPreview == nil { await refreshSuiSendPreview() }
            guard let preview = suiSendPreview else { sendError = sendError ?? "Unable to estimate Sui network fee."; return }
            let mistAmount = UInt64(amount * 1e9)
            let gasBudget = UInt64(preview.estimatedNetworkFeeSUI * 1e9)
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeSUI, symbol: "SUI", isSendingPath: \.isSendingSui, chainId: SpectraChainID.sui, chain: .sui, derivationPath: walletDerivationPath(for: wallet, chain: .sui), format: "sui.rust_json", txHashField: "digest", checkSelfSend: true, buildJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"mist\":\(mistAmount),\"gas_budget\":\(gasBudget),\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, clearPreview: { self.suiSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "Aptos", holding.symbol == "APT" {
            guard !isSendingAptos else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedAptosAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Aptos signing address from the seed phrase."; return }
            if aptosSendPreview == nil { await refreshAptosSendPreview() }
            guard let preview = aptosSendPreview else { sendError = sendError ?? "Unable to estimate Aptos network fee."; return }
            let octasAmount = UInt64(amount * 1e8)
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeAPT, symbol: "APT", isSendingPath: \.isSendingAptos, chainId: SpectraChainID.aptos, chain: .aptos, derivationPath: walletDerivationPath(for: wallet, chain: .aptos), format: "aptos.rust_json", checkSelfSend: true, buildJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"octas\":\(octasAmount),\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, clearPreview: { self.aptosSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "TON", holding.symbol == "TON" {
            guard !isSendingTON else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedTONAddress(for: wallet) else { sendError = "Unable to resolve this wallet's TON signing address from the seed phrase."; return }
            if tonSendPreview == nil { await refreshTONSendPreview() }
            guard let preview = tonSendPreview else { sendError = sendError ?? "Unable to estimate TON network fee."; return }
            let nanotons = UInt64(amount * 1e9)
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeTON, symbol: "TON", isSendingPath: \.isSendingTON, chainId: SpectraChainID.ton, chain: .ton, derivationPath: walletDerivationPath(for: wallet, chain: .ton), format: "ton.rust_json", checkSelfSend: true, buildJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"nanotons\":\(nanotons),\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, clearPreview: { self.tonSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "Internet Computer", holding.symbol == "ICP" {
            guard !isSendingICP else { return }
            if icpSendPreview == nil { await refreshICPSendPreview() }
            guard let walletIndex = wallets.firstIndex(where: { $0.id == wallet.id }), let sourceAddress = resolvedICPAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's ICP address."
                return
            }
            let privateKey = storedPrivateKey(for: wallet.id)
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            guard privateKey != nil || seedPhrase != nil else {
                sendError = "This wallet's signing secret is unavailable."
                return
            }
            if requiresSelfSendConfirmation(
                wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount
            ) {
                return
            }
            isSendingICP = true
            defer { isSendingICP = false }
            do {
                let e8sAmount = UInt64(amount * 1e8)
                let resultJSON: String
                if let seedPhrase {
                    resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.icp, seedPhrase: seedPhrase, chain: .internetComputer, derivationPath: wallet.seedDerivationPaths.internetComputer
                    ) { privKeyHex, pubKeyHex in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"e8s\":\(e8sAmount),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                    }
                } else if let privateKey {
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    let paramsJson = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"e8s\":\(e8sAmount),\"private_key_hex\":\"\(normalizedPriv)\"}"
                    resultJSON = try await WalletServiceBridge.shared.signAndSend(
                        chainId: SpectraChainID.icp, paramsJson: paramsJson
                    )
                } else { throw NSError(domain: "ICPSend", code: 1, userInfo: [NSLocalizedDescriptionKey: "This wallet seed phrase cannot derive a valid ICP signer."]) }
                let txid = rustField("block_index", from: resultJSON)
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: txid.isEmpty ? resultJSON : txid, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: "icp.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.icpSendPreview = nil
                    self.wallets[walletIndex] = self.wallets[walletIndex]
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if isEVMChain(holding.chainName) {
            do {
                let resolvedDestination = try await resolveEVMRecipientAddress(input: destinationInput, for: holding.chainName)
                destinationAddress = resolvedDestination.address
                usedENSResolution = resolvedDestination.usedENS
                if usedENSResolution { sendDestinationInfoMessage = "Resolved ENS \(destinationInput) to \(destinationAddress)." }
            } catch {
                sendError = (error as? LocalizedError)?.errorDescription ?? "Enter a valid \(holding.chainName) destination."
                return
            }}
        if !bypassHighRiskSendConfirmation {
            var highRiskReasons = evaluateHighRiskSendReasons(
                wallet: wallet, holding: holding, amount: amount, destinationAddress: destinationAddress, destinationInput: destinationInput, usedENSResolution: usedENSResolution
            )
            if let chain = evmChainContext(for: holding.chainName) {
                let preflightReasons = await evmRecipientPreflightReasons(
                    holding: holding, chain: chain, destinationAddress: destinationAddress
                )
                highRiskReasons.append(contentsOf: preflightReasons)
            }
            if !highRiskReasons.isEmpty {
                pendingHighRiskSendReasons = highRiskReasons
                isShowingHighRiskSendConfirmation = true
                sendError = nil
                return
            }
        } else { bypassHighRiskSendConfirmation = false }
        if requiresSelfSendConfirmation(
            wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount
        ) {
            return
        }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction send") else { return }
        if holding.symbol == "BTC" {
            guard amount > 0 else {
                sendError = "Enter a valid amount"
                return
            }
            guard !isSendingBitcoin else { return }
            isSendingBitcoin = true
            defer { isSendingBitcoin = false }
            do {
                guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                    sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                guard let sourceAddress = resolvedBitcoinAddress(for: wallet) else {
                    sendError = "Unable to resolve this wallet's Bitcoin address from the seed phrase."
                    return
                }
                if bitcoinSendPreview == nil { await refreshBitcoinSendPreview() }
                let amountSat = UInt64(amount * 1e8)
                let feeRateSvB: Double = Double(bitcoinSendPreview?.estimatedFeeRateSatVb ?? 10)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.bitcoin, seedPhrase: seedPhrase, chain: .bitcoin, derivationPath: walletDerivationPath(for: wallet, chain: .bitcoin)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_rate_svb\":\(feeRateSvB),\"private_key_hex\":\"\(privKeyHex)\"}"
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: rustField("txid", from: resultJSON), signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: "bitcoin.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.bitcoinSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "BCH", holding.chainName == "Bitcoin Cash" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinCash, chain: .bitcoinCash, isSendingPath: \.isSendingBitcoinCash, symbol: "BCH", feeFallback: 0.00001, format: "bitcoin_cash.rust_json", resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, getPreview: { self.bitcoinCashSendPreview }, refreshPreview: { await self.refreshBitcoinCashSendPreview() }, clearPreview: { self.bitcoinCashSendPreview = nil }
            )
            return
        }
        if holding.symbol == "BSV", holding.chainName == "Bitcoin SV" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinSv, chain: .bitcoinSV, isSendingPath: \.isSendingBitcoinSV, symbol: "BSV", feeFallback: 0.00001, format: "bitcoin_sv.rust_json", resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, getPreview: { self.bitcoinSVSendPreview }, refreshPreview: { await self.refreshBitcoinSVSendPreview() }, clearPreview: { self.bitcoinSVSendPreview = nil }
            )
            return
        }
        if holding.symbol == "LTC", holding.chainName == "Litecoin" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.litecoin, chain: .litecoin, isSendingPath: \.isSendingLitecoin, symbol: "LTC", feeFallback: 0.0001, format: "litecoin.rust_json", resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, getPreview: { self.litecoinSendPreview }, refreshPreview: { await self.refreshLitecoinSendPreview() }, clearPreview: { self.litecoinSendPreview = nil }
            )
            return
        }
        if holding.symbol == "DOGE", holding.chainName == "Dogecoin" {
            guard !isSendingDogecoin else { return }
            guard let dogecoinAmount = parseDogecoinAmountInput(sendAmount) else {
                sendError = "Enter a valid DOGE amount with up to 8 decimal places."
                return
            }
            guard isValidDogecoinAddressForPolicy(destinationAddress, networkMode: dogecoinNetworkMode(for: wallet)) else {
                sendError = CommonLocalization.invalidDestinationAddressPrompt("Dogecoin")
                return
            }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard resolvedDogecoinAddress(for: wallet) != nil else {
                sendError = "Unable to resolve this wallet's Dogecoin signing address from the seed phrase."
                return
            }
            appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send initiated.")
            if dogecoinSendPreview == nil { await refreshDogecoinSendPreview() }
            if let dogecoinSendPreview = dogecoinSendPreview, dogecoinAmount > dogecoinSendPreview.maxSendableDOGE {
                sendError = "Insufficient DOGE for amount plus network fee (max sendable ~\(String(format: "%.6f", dogecoinSendPreview.maxSendableDOGE)) DOGE)."
                return
            }
            isSendingDogecoin = true
            defer { isSendingDogecoin = false }
            guard let sourceAddress = resolvedDogecoinAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Dogecoin signing address."
                return
            }
            do {
                let amountSat = UInt64(dogecoinAmount * 1e8)
                let feeRateDOGEPerKB = dogecoinSendPreview?.estimatedFeeRateDOGEPerKB ?? 0.01
                let feeSat = UInt64(feeRateDOGEPerKB * 350.0 / 1000.0 * 1e8)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.dogecoin, seedPhrase: seedPhrase, chain: .dogecoin, derivationPath: walletDerivationPath(for: wallet, chain: .dogecoin)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
                }
                let txid = rustField("txid", from: resultJSON)
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: dogecoinAmount, address: destinationAddress, transactionHash: txid, dogecoinConfirmations: 0, dogecoinFeePriorityRaw: dogecoinFeePriority.rawValue, dogecoinEstimatedFeeRateDOGEPerKB: dogecoinSendPreview?.estimatedFeeRateDOGEPerKB, dogecoinUsedChangeOutput: dogecoinSendPreview?.usesChangeOutput, sourceAddress: sourceAddress, dogecoinRawTransactionHex: resultJSON, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: "dogecoin.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                clearSendVerificationNotice()
                appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send broadcast.", transactionHash: txid)
                await refreshDogecoinTransactions()
                await refreshPendingDogecoinTransactions()
                updateSendVerificationNoticeForLastSentTransaction()
                resetSendComposerState {
                    self.dogecoinSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE send failed: \(error.localizedDescription)")
                noteSendBroadcastFailure(for: holding.chainName, message: error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Tron", holding.symbol == "TRX" || holding.symbol == "USDT" {
            guard !isSendingTron else { return }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."
                return
            }
            guard let sourceAddress = resolvedTronAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Tron signing address."
                return
            }
            if tronSendPreview == nil { await refreshTronSendPreview() }
            guard let preview = tronSendPreview else {
                sendError = sendError ?? "Unable to estimate Tron network fee."
                return
            }
            if holding.symbol == "TRX" {
                let totalCost = amount + preview.estimatedNetworkFeeTRX
                if totalCost > holding.amount {
                    sendError = "Insufficient TRX for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) TRX)."
                    return
                }
            } else {
                let trxBalance = wallet.holdings.first(where: { $0.chainName == "Tron" && $0.symbol == "TRX" })?.amount ?? 0
                if preview.estimatedNetworkFeeTRX > trxBalance {
                    sendError = "Insufficient TRX to cover Tron network fee (~\(String(format: "%.6f", preview.estimatedNetworkFeeTRX)) TRX)."
                    return
                }}
            isSendingTron = true
            defer { isSendingTron = false }
            do {
                let sendResult: TronSendResult
                if holding.symbol == "TRX", let seedPhrase {
                    let amountSun = UInt64(amount * 1e6)
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                        chainId: SpectraChainID.tron, seedPhrase: seedPhrase, chain: .tron, derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sun\":\(amountSun),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = TronSendResult(
                        transactionHash: rustField("txid", from: resultJSON), estimatedNetworkFeeTRX: tronSendPreview?.estimatedNetworkFeeTRX ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                    )
                } else if let seedPhrase, let contract = holding.contractAddress {
                    let amountRawUInt = UInt64((amount * 1_000_000.0).rounded())
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                        chainId: SpectraChainID.tron, seedPhrase: seedPhrase, chain: .tron, derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contract)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRawUInt)\",\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = TronSendResult(
                        transactionHash: rustField("txid", from: resultJSON), estimatedNetworkFeeTRX: tronSendPreview?.estimatedNetworkFeeTRX ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                    )
                } else if let privateKey {
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    if holding.symbol == "TRX" {
                        let amountSun = UInt64(amount * 1e6)
                        let paramsJson = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sun\":\(amountSun),\"private_key_hex\":\"\(normalizedPriv)\"}"
                        let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                            chainId: SpectraChainID.tron, paramsJson: paramsJson
                        )
                        sendResult = TronSendResult(
                            transactionHash: rustField("txid", from: resultJSON), estimatedNetworkFeeTRX: tronSendPreview?.estimatedNetworkFeeTRX ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                        )
                    } else if let contract = holding.contractAddress {
                        let amountRawUInt = UInt64((amount * 1_000_000.0).rounded())
                        let paramsJson = "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contract)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRawUInt)\",\"private_key_hex\":\"\(normalizedPriv)\"}"
                        let resultJSON = try await WalletServiceBridge.shared.signAndSendToken(
                            chainId: SpectraChainID.tron, paramsJson: paramsJson
                        )
                        sendResult = TronSendResult(
                            transactionHash: rustField("txid", from: resultJSON), estimatedNetworkFeeTRX: tronSendPreview?.estimatedNetworkFeeTRX ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                        )
                    } else {
                        sendError = "Unsupported Tron asset for private-key send."
                        return
                    }
                } else {
                    sendError = "This wallet's signing key is unavailable."
                    return
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: sendResult.transactionHash, signedTransactionPayload: sendResult.signedTransactionJSON, signedTransactionPayloadFormat: "tron.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                resetSendComposerState {
                    self.tronSendPreview = nil
                    self.tronLastSendErrorDetails = nil
                    self.tronLastSendErrorAt = nil
                }
            } catch {
                let message = userFacingTronSendError(error, symbol: holding.symbol)
                sendError = message
                recordTronSendDiagnosticError(message)
                noteSendBroadcastFailure(for: holding.chainName, message: message)
            }
            return
        }
        if isSupportedSolanaSendCoin(holding) {
            guard !isSendingSolana else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = resolvedSolanaAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Solana signing address from the seed phrase."
                return
            }
            if solanaSendPreview == nil { await refreshSolanaSendPreview() }
            guard let preview = solanaSendPreview else {
                sendError = sendError ?? "Unable to estimate Solana network fee."
                return
            }
            if holding.symbol == "SOL" {
                let totalCost = amount + preview.estimatedNetworkFeeSOL
                if totalCost > holding.amount {
                    sendError = "Insufficient SOL for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) SOL)."
                    return
                }
            } else {
                if amount > holding.amount {
                    sendError = "Insufficient \(holding.symbol) balance for this transfer."
                    return
                }
                let solBalance = wallet.holdings.first(where: { $0.chainName == "Solana" && $0.symbol == "SOL" })?.amount ?? 0
                if preview.estimatedNetworkFeeSOL > solBalance {
                    sendError = "Insufficient SOL to cover Solana network fee (~\(String(format: "%.6f", preview.estimatedNetworkFeeSOL)) SOL)."
                    return
                }}
            isSendingSolana = true
            defer { isSendingSolana = false }
            do {
                let sendResult: SolanaSendResult
                if holding.symbol == "SOL" {
                    let lamports = UInt64(amount * 1e9)
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.solana, seedPhrase: seedPhrase, chain: .solana, derivationPath: walletDerivationPath(for: wallet, chain: .solana)
                    ) { privKeyHex, pubKeyHex in
                        "{\"from_pubkey_hex\":\"\(pubKeyHex)\",\"to\":\"\(destinationAddress)\",\"lamports\":\(lamports),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = SolanaSendResult(
                        transactionHash: rustField("signature", from: resultJSON), estimatedNetworkFeeSOL: solanaSendPreview?.estimatedNetworkFeeSOL ?? 0, signedTransactionBase64: resultJSON, verificationStatus: .verified
                    )
                } else {
                    let solanaTokenMetadataByMint = solanaTrackedTokens(includeDisabled: true)
                    guard let mintAddress = holding.contractAddress ?? SolanaBalanceService.mintAddress(for: holding.symbol), let tokenMetadata = solanaTokenMetadataByMint[mintAddress] else {
                        sendError = "\(holding.symbol) on Solana is not configured for sending yet."
                        return
                    }
                    let decimals = tokenMetadata.decimals
                    let scale = pow(10.0, Double(decimals))
                    let amountRawUInt = UInt64((amount * scale).rounded())
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                        chainId: SpectraChainID.solana, seedPhrase: seedPhrase, chain: .solana, derivationPath: walletDerivationPath(for: wallet, chain: .solana)
                    ) { privKeyHex, pubKeyHex in
                        let pk = pubKeyHex ?? ""
                        return "{\"from_pubkey_hex\":\"\(pk)\",\"to\":\"\(destinationAddress)\",\"mint\":\"\(mintAddress)\",\"amount_raw\":\"\(amountRawUInt)\",\"decimals\":\(decimals),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = SolanaSendResult(
                        transactionHash: rustField("signature", from: resultJSON), estimatedNetworkFeeSOL: solanaSendPreview?.estimatedNetworkFeeSOL ?? 0, signedTransactionBase64: resultJSON, verificationStatus: .verified
                    )
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: sendResult.transactionHash, signedTransactionPayload: sendResult.signedTransactionBase64, signedTransactionPayloadFormat: "solana.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                resetSendComposerState {
                    self.solanaSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "XRP Ledger", holding.symbol == "XRP" {
            guard !isSendingXRP else { return }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."; return
            }
            guard let sourceAddress = resolvedXRPAddress(for: wallet) else { sendError = "Unable to resolve this wallet's XRP signing address."; return }
            if xrpSendPreview == nil { await refreshXRPSendPreview() }
            guard let preview = xrpSendPreview else { sendError = sendError ?? "Unable to estimate XRP network fee."; return }
            let drops = UInt64(amount * 1e6)
            await submitDualKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeXRP, symbol: "XRP", feeFormat: "%.6f", isSendingPath: \.isSendingXRP, chainId: SpectraChainID.xrp, chain: .xrp, derivationPath: walletDerivationPath(for: wallet, chain: .xrp), format: "xrp.rust_json", buildSeedJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"drops\":\(drops),\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, buildPrivKeyJSON: { priv in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"drops\":\(drops),\"private_key_hex\":\"\(priv)\"}" }, clearPreview: { self.xrpSendPreview = nil }, seedPhrase: seedPhrase, privateKey: privateKey, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "Stellar", holding.symbol == "XLM" {
            guard !isSendingStellar else { return }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."; return
            }
            guard let sourceAddress = resolvedStellarAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Stellar signing address."; return }
            if stellarSendPreview == nil { await refreshStellarSendPreview() }
            guard let preview = stellarSendPreview else { sendError = sendError ?? "Unable to estimate Stellar network fee."; return }
            let stroops = Int64(amount * 1e7)
            await submitDualKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeXLM, symbol: "XLM", feeFormat: "%.7f", isSendingPath: \.isSendingStellar, chainId: SpectraChainID.stellar, chain: .stellar, derivationPath: wallet.seedDerivationPaths.stellar, format: "stellar.rust_json", buildSeedJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"stroops\":\(stroops),\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, buildPrivKeyJSON: { priv in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"stroops\":\(stroops),\"private_key_hex\":\"\(priv)\"}" }, clearPreview: { self.stellarSendPreview = nil }, seedPhrase: seedPhrase, privateKey: privateKey, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "Monero", holding.symbol == "XMR" {
            guard !isSendingMonero else { return }
            guard let sourceAddress = resolvedMoneroAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Monero address."
                return
            }
            if moneroSendPreview == nil { await refreshMoneroSendPreview() }
            guard let preview = moneroSendPreview else {
                sendError = sendError ?? "Unable to estimate Monero network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeXMR
            if totalCost > holding.amount {
                sendError = "Insufficient XMR for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) XMR)."
                return
            }
            isSendingMonero = true
            defer { isSendingMonero = false }
            do {
                let piconeros = UInt64(amount * 1e12)
                let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                    chainId: SpectraChainID.monero, paramsJson: "{\"to\":\"\(destinationAddress)\",\"piconeros\":\(piconeros),\"priority\":2}"
                )
                let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: rustField("txid", from: resultJSON), signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: "monero.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.moneroSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Cardano", holding.symbol == "ADA" {
            guard !isSendingCardano else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedCardanoAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Cardano signing address from the seed phrase."; return }
            if cardanoSendPreview == nil { await refreshCardanoSendPreview() }
            guard let preview = cardanoSendPreview else { sendError = sendError ?? "Unable to estimate Cardano network fee."; return }
            let amountLovelace = UInt64(amount * 1e6)
            let feeLovelace = UInt64(preview.estimatedNetworkFeeADA * 1e6)
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeADA, symbol: "ADA", isSendingPath: \.isSendingCardano, chainId: SpectraChainID.cardano, chain: .cardano, derivationPath: walletDerivationPath(for: wallet, chain: .cardano), format: "cardano.rust_json", buildJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_lovelace\":\(amountLovelace),\"fee_lovelace\":\(feeLovelace),\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, clearPreview: { self.cardanoSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "NEAR", holding.symbol == "NEAR" {
            guard !isSendingNear else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedNearAddress(for: wallet) else { sendError = "Unable to resolve this wallet's NEAR signing address from the seed phrase."; return }
            if nearSendPreview == nil { await refreshNearSendPreview() }
            guard let preview = nearSendPreview else { sendError = sendError ?? "Unable to estimate NEAR network fee."; return }
            let yoctoStr = nearToYoctoString(amount)
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeNEAR, symbol: "NEAR", isSendingPath: \.isSendingNear, chainId: SpectraChainID.near, chain: .near, derivationPath: walletDerivationPath(for: wallet, chain: .near), format: "near.rust_json", buildJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"yocto_near\":\"\(yoctoStr)\",\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, clearPreview: { self.nearSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "NEAR", holding.tokenStandard == "NEP-141", let contractAddress = holding.contractAddress {
            guard !isSendingNear else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."; return
            }
            guard let sourceAddress = resolvedNearAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's NEAR signing address from the seed phrase."; return
            }
            let nearNativeBalance = wallet.holdings.first(where: { $0.chainName == "NEAR" && $0.symbol == "NEAR" })?.amount ?? 0
            if nearNativeBalance < 0.001 {
                sendError = "Insufficient NEAR balance to cover the network fee for this \(holding.symbol) transfer."; return
            }
            let tokenPref = (cachedTokenPreferencesByChain[.near] ?? []).first {
                $0.contractAddress.lowercased() == contractAddress.lowercased()
            }
            let decimals = min(tokenPref?.decimals ?? 6, 18)
            let amountRaw = "\(UInt64((amount * pow(10.0, Double(decimals))).rounded()))"
            isSendingNear = true
            defer { isSendingNear = false }
            do {
                let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                    chainId: SpectraChainID.near, seedPhrase: seedPhrase, chain: .near, derivationPath: walletDerivationPath(for: wallet, chain: .near)
                ) { privKeyHex, pubKeyHex in
                    let pub = pubKeyHex ?? ""
                    return "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contractAddress)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pub)\"}"
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: rustField("txid", from: resultJSON), signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: "near.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.nearSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Polkadot", holding.symbol == "DOT" {
            guard !isSendingPolkadot else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedPolkadotAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Polkadot signing address from the seed phrase."; return }
            if polkadotSendPreview == nil { await refreshPolkadotSendPreview() }
            guard let preview = polkadotSendPreview else { sendError = sendError ?? "Unable to estimate Polkadot network fee."; return }
            let planckStr = dotToPlanckString(amount)
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeDOT, symbol: "DOT", isSendingPath: \.isSendingPolkadot, chainId: SpectraChainID.polkadot, chain: .polkadot, derivationPath: wallet.seedDerivationPaths.polkadot, format: "polkadot.rust_json", buildJSON: { priv, pub in "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"planck\":\"\(planckStr)\",\"private_key_hex\":\"\(priv)\",\"public_key_hex\":\"\(pub)\"}" }, clearPreview: { self.polkadotSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if isEVMChain(holding.chainName) {
            guard let chain = evmChainContext(for: holding.chainName) else {
                sendError = "\(holding.chainName) native sending is not enabled yet."
                return
            }
            guard !isSendingEthereum else { return }
            guard !activeEthereumSendWalletIDs.contains(wallet.id) else {
                sendError = "An \(holding.chainName) send is already in progress for this wallet."
                return
            }
            if customEthereumNonceValidationError != nil {
                sendError = customEthereumNonceValidationError
                return
            }
            if holding.symbol != "ETH" && holding.symbol != "BNB", amount <= 0 {
                sendError = "Enter a valid amount"
                return
            }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."
                return
            }
            let nativeSymbol = preflight.nativeEVMSymbol ?? "ETH"
            let nativeBalance = wallet.holdings.first(where: { $0.chainName == holding.chainName && $0.symbol == nativeSymbol })?.amount ?? 0
            if ethereumSendPreview == nil { await refreshEthereumSendPreview() }
            guard let preview = ethereumSendPreview else {
                sendError = sendError ?? "Unable to estimate \(holding.chainName) network fee."
                return
            }
            if preflight.isNativeEVMAsset {
                let totalCost = amount + preview.estimatedNetworkFeeETH
                if totalCost > nativeBalance {
                    sendError = "Insufficient \(nativeSymbol) for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) \(nativeSymbol))."
                    return
                }
            } else if preview.estimatedNetworkFeeETH > nativeBalance {
                sendError = "Insufficient \(nativeSymbol) to cover the network fee (~\(String(format: "%.6f", preview.estimatedNetworkFeeETH)) \(nativeSymbol))."
                return
            }
            isSendingEthereum = true
            activeEthereumSendWalletIDs.insert(wallet.id)
            defer {
                isSendingEthereum = false
                activeEthereumSendWalletIDs.remove(wallet.id)
            }
            do {
                if customEthereumFeeValidationError != nil {
                    sendError = customEthereumFeeValidationError
                    return
                }
                let customFees = customEthereumFeeConfiguration()
                let explicitNonce = explicitEthereumNonce()
                let evmDerivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: holding.chainName) ?? .ethereum
                let result: EthereumSendResult
                let spectraEvmChainId = SpectraChainID.id(for: holding.chainName)
                let overridesFragment = evmOverridesJSONFragment(nonce: explicitNonce, customFees: customFees)
                let rustSupportsChain = spectraEvmChainId != nil
                if preflight.isNativeEVMAsset && rustSupportsChain, let chainId = spectraEvmChainId {
                    let valueWei = ethToWeiString(amount)
                    guard let sourceAddress = resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                        sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                        return
                    }
                    let resultJSON: String
                    if let seedPhrase {
                        resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                            chainId: chainId, seedPhrase: seedPhrase, chain: evmDerivationChain, derivationPath: walletDerivationPath(for: wallet, chain: evmDerivationChain)
                        ) { privKeyHex, _ in
                            "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"value_wei\":\"\(valueWei)\",\"private_key_hex\":\"\(privKeyHex)\"\(overridesFragment)}"
                        }
                    } else if let privateKey {
                        let payload = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"value_wei\":\"\(valueWei)\",\"private_key_hex\":\"\(privateKey)\"\(overridesFragment)}"
                        resultJSON = try await WalletServiceBridge.shared.signAndSend(chainId: chainId, paramsJson: payload)
                    } else {
                        sendError = "This wallet's signing key is unavailable."
                        return
                    }
                    result = decodeEvmSendResult(
                        resultJSON, fallbackNonce: explicitNonce ?? ethereumSendPreview?.nonce ?? 0
                    )
                } else if let token = supportedEVMToken(for: holding), rustSupportsChain, let chainId = spectraEvmChainId {
                    guard let sourceAddress = resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                        sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                        return
                    }
                    let amountRaw = tokenAmountToRawString(amount, decimals: token.decimals)
                    let resultJSON: String
                    if let seedPhrase {
                        resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                            chainId: chainId, seedPhrase: seedPhrase, chain: evmDerivationChain, derivationPath: walletDerivationPath(for: wallet, chain: evmDerivationChain)
                        ) { privKeyHex, _ in
                            "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(token.contractAddress)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privKeyHex)\"\(overridesFragment)}"
                        }
                    } else if let privateKey {
                        let payload = "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(token.contractAddress)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privateKey)\"\(overridesFragment)}"
                        resultJSON = try await WalletServiceBridge.shared.signAndSendToken(chainId: chainId, paramsJson: payload)
                    } else {
                        sendError = "This wallet's signing key is unavailable."
                        return
                    }
                    result = decodeEvmSendResult(
                        resultJSON, fallbackNonce: explicitNonce ?? ethereumSendPreview?.nonce ?? 0
                    )
                } else {
                    sendError = "\(holding.symbol) transfers on \(holding.chainName) are not enabled yet."
                    return
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, ethereumNonce: result.preview.nonce, signedTransactionPayload: result.rawTransactionHex, signedTransactionPayloadFormat: "evm.raw_hex"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: result.verificationStatus)
                resetSendComposerState()
            } catch {
                sendError = mapEthereumSendError(error)
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        sendError = "\(holding.chainName) native sending is not enabled yet."
    }

    @MainActor private func submitSeedPubKeyChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, networkFee: Double, symbol: String, isSendingPath: ReferenceWritableKeyPath<WalletStore, Bool>, chainId: UInt32, chain: SeedDerivationChain, derivationPath: String, format: String, txHashField: String = "txid", checkSelfSend: Bool = false, buildJSON: @escaping (String, String) -> String, clearPreview: @escaping () -> Void, seedPhrase: String, sourceAddress: String
    ) async {
        let totalCost = amount + networkFee
        if totalCost > holding.amount {
            sendError = "Insufficient \(symbol) for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) \(symbol))."
            return
        }
        if checkSelfSend && requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount) { return }
        self[keyPath: isSendingPath] = true
        defer { self[keyPath: isSendingPath] = false }
        do {
            let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(chainId: chainId, seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath) { priv, pub in buildJSON(priv, pub) }
            let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: rustField(txHashField, from: resultJSON), signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: format
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}

    @MainActor private func submitDualKeyChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, networkFee: Double, symbol: String, feeFormat: String, isSendingPath: ReferenceWritableKeyPath<WalletStore, Bool>, chainId: UInt32, chain: SeedDerivationChain, derivationPath: String, format: String, buildSeedJSON: @escaping (String, String) -> String, buildPrivKeyJSON: @escaping (String) -> String, clearPreview: @escaping () -> Void, seedPhrase: String?, privateKey: String?, sourceAddress: String
    ) async {
        let totalCost = amount + networkFee
        if totalCost > holding.amount {
            sendError = "Insufficient \(symbol) for amount plus network fee (needs ~\(String(format: feeFormat, totalCost)) \(symbol))."
            return
        }
        self[keyPath: isSendingPath] = true
        defer { self[keyPath: isSendingPath] = false }
        do {
            let txHash: String
            let signedPayload: String
            if let seedPhrase {
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(chainId: chainId, seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath) { priv, pub in buildSeedJSON(priv, pub) }
                txHash = rustField("txid", from: resultJSON)
                signedPayload = resultJSON
            } else if let privateKey {
                let norm = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                let resultJSON = try await WalletServiceBridge.shared.signAndSend(chainId: chainId, paramsJson: buildPrivKeyJSON(norm))
                txHash = rustField("txid", from: resultJSON)
                signedPayload = resultJSON
            } else {
                sendError = "This wallet's signing key is unavailable."
                return
            }
            let transaction = decoratePendingSendTransaction(TransactionRecord(
                walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: txHash, signedTransactionPayload: signedPayload, signedTransactionPayloadFormat: format
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}

    @MainActor private func submitUTXOSatChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, chainId: UInt32, chain: SeedDerivationChain, isSendingPath: ReferenceWritableKeyPath<WalletStore, Bool>, symbol: String, feeFallback: Double, format: String, resolveAddress: @escaping (ImportedWallet) -> String?, getPreview: @escaping () -> BitcoinSendPreview?, refreshPreview: @escaping () async -> Void, clearPreview: @escaping () -> Void
    ) async {
        guard amount > 0 else { sendError = "Enter a valid amount"; return }
        guard !self[keyPath: isSendingPath] else { return }
        self[keyPath: isSendingPath] = true
        defer { self[keyPath: isSendingPath] = false }
        do {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolveAddress(wallet) else { sendError = "Unable to resolve this wallet's \(symbol) address from the seed phrase."; return }
            if getPreview() == nil { await refreshPreview() }
            if let preview = getPreview() {
                let totalCost = amount + preview.estimatedNetworkFeeBTC
                if totalCost > holding.amount {
                    sendError = "Insufficient \(symbol) for amount plus network fee (needs ~\(String(format: "%.8f", totalCost)) \(symbol))."
                    return
                }}
            let amountSat = UInt64(amount * 1e8)
            let feeSat = UInt64((getPreview()?.estimatedNetworkFeeBTC ?? feeFallback) * 1e8)
            let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: chain, derivationPath: walletDerivationPath(for: wallet, chain: chain)
            ) { privKeyHex, _ in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
            }
            let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: rustField("txid", from: resultJSON), signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: format
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}
}
