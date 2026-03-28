// MARK: - File Overview
// Wallet onboarding and transaction flow screens (import/create/send/receive) composition.
//
// Responsibilities:
// - Coordinates form-driven wallet actions with WalletStore state mutations.
// - Defines end-user flow sequencing for key wallet operations.

import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import VisionKit

private func localizedWalletFlowString(_ key: String) -> String {
    AppLocalization.string(key)
}

private struct TransactionStatusBadge: View {
    let status: TransactionStatus

    private var statusText: String {
        status.rawValue.capitalized
    }

    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .confirmed:
            return .mint
        case .failed:
            return .red
        }
    }

    private var badgeScale: CGFloat {
        switch status {
        case .pending:
            return 1.0
        case .confirmed:
            return 1.05
        case .failed:
            return 0.97
        }
    }

    var body: some View {
        Text(statusText.uppercased())
            .font(.caption2.bold())
            .tracking(0.6)
            .frame(minWidth: 86)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.16), in: Capsule())
            .foregroundStyle(statusColor)
            .scaleEffect(badgeScale)
            .animation(.spring(response: 0.35, dampingFraction: 0.74), value: status)
    }
}

private struct SetupChainSelectionDescriptor: Identifiable {
    let id: String
    let titleKey: String
    let symbol: String
    let mark: String
    let chainName: String
    let assetIdentifier: String?
    let color: Color

    var title: String {
        localizedWalletFlowString(titleKey)
    }

    init(id: String, title: String, symbol: String, mark: String, chainName: String, color: Color) {
        self.id = id
        self.titleKey = title
        self.symbol = symbol
        self.mark = mark
        self.chainName = chainName
        self.assetIdentifier = Coin.iconIdentifier(symbol: symbol, chainName: chainName)
        self.color = color
    }
}

struct SetupView: View {
    private static let chainSelectionDescriptors: [SetupChainSelectionDescriptor] = [
        SetupChainSelectionDescriptor(id: "bitcoin", title: "Bitcoin", symbol: "BTC", mark: "B", chainName: "Bitcoin", color: .orange),
        SetupChainSelectionDescriptor(id: "bitcoin-cash", title: "Bitcoin Cash", symbol: "BCH", mark: "BC", chainName: "Bitcoin Cash", color: .orange),
        SetupChainSelectionDescriptor(id: "bitcoin-sv", title: "Bitcoin SV", symbol: "BSV", mark: "BS", chainName: "Bitcoin SV", color: .orange),
        SetupChainSelectionDescriptor(id: "litecoin", title: "Litecoin", symbol: "LTC", mark: "L", chainName: "Litecoin", color: .gray),
        SetupChainSelectionDescriptor(id: "ethereum", title: "Ethereum", symbol: "ETH", mark: "E", chainName: "Ethereum", color: .blue),
        SetupChainSelectionDescriptor(id: "ethereum-classic", title: "Ethereum Classic", symbol: "ETC", mark: "EC", chainName: "Ethereum Classic", color: .green),
        SetupChainSelectionDescriptor(id: "solana", title: "Solana", symbol: "SOL", mark: "S", chainName: "Solana", color: .purple),
        SetupChainSelectionDescriptor(id: "arbitrum", title: "Arbitrum", symbol: "ARB", mark: "AR", chainName: "Arbitrum", color: .cyan),
        SetupChainSelectionDescriptor(id: "optimism", title: "Optimism", symbol: "OP", mark: "OP", chainName: "Optimism", color: .red),
        SetupChainSelectionDescriptor(id: "bnb-chain", title: "BNB Chain", symbol: "BNB", mark: "BN", chainName: "BNB Chain", color: .yellow),
        SetupChainSelectionDescriptor(id: "avalanche", title: "Avalanche", symbol: "AVAX", mark: "AV", chainName: "Avalanche", color: .red),
        SetupChainSelectionDescriptor(id: "hyperliquid", title: "Hyperliquid", symbol: "HYPE", mark: "HY", chainName: "Hyperliquid", color: .mint),
        SetupChainSelectionDescriptor(id: "dogecoin", title: "Dogecoin", symbol: "DOGE", mark: "D", chainName: "Dogecoin", color: .brown),
        SetupChainSelectionDescriptor(id: "cardano", title: "Cardano", symbol: "ADA", mark: "A", chainName: "Cardano", color: .indigo),
        SetupChainSelectionDescriptor(id: "tron", title: "Tron", symbol: "TRX", mark: "T", chainName: "Tron", color: .teal),
        SetupChainSelectionDescriptor(id: "xrp-ledger", title: "XRP Ledger", symbol: "XRP", mark: "X", chainName: "XRP Ledger", color: .cyan),
        SetupChainSelectionDescriptor(id: "monero", title: "Monero", symbol: "XMR", mark: "M", chainName: "Monero", color: .indigo),
        SetupChainSelectionDescriptor(id: "sui", title: "Sui", symbol: "SUI", mark: "SU", chainName: "Sui", color: .mint),
        SetupChainSelectionDescriptor(id: "aptos", title: "Aptos", symbol: "APT", mark: "AP", chainName: "Aptos", color: .cyan),
        SetupChainSelectionDescriptor(id: "ton", title: "TON", symbol: "TON", mark: "TN", chainName: "TON", color: .blue),
        SetupChainSelectionDescriptor(id: "internet-computer", title: "Internet Computer", symbol: "ICP", mark: "IC", chainName: "Internet Computer", color: .indigo),
        SetupChainSelectionDescriptor(id: "near", title: "NEAR", symbol: "NEAR", mark: "N", chainName: "NEAR", color: .indigo),
        SetupChainSelectionDescriptor(id: "polkadot", title: "Polkadot", symbol: "DOT", mark: "P", chainName: "Polkadot", color: .pink),
        SetupChainSelectionDescriptor(id: "stellar", title: "Stellar", symbol: "XLM", mark: "XL", chainName: "Stellar", color: .teal),
    ]
    private static let popularChainSelectionIDs: Set<String> = [
        "bitcoin",
        "ethereum",
        "solana",
        "monero",
        "litecoin",
        "tron"
    ]
    private static let nonPopularChainSelectionDescriptors = chainSelectionDescriptors.filter {
        !popularChainSelectionIDs.contains($0.id)
    }
    private static let sortedChainSelectionDescriptors = chainSelectionDescriptors.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }

    private enum SetupPage {
        case details
        case watchAddresses
        case seedPhrase
        case password
        case advanced
        case backupVerification
    }

    @ObservedObject var store: WalletStore
    @ObservedObject var draft: WalletImportDraft
    private let copy = ImportFlowContent.current
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var setupPage: SetupPage = .details
    @State private var chainSearchText: String = ""
    @State private var isShowingAllChainsSheet: Bool = false
    @FocusState private var focusedSeedPhraseIndex: Int?
    private let chainSelectionColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let setupCardCornerRadius: CGFloat = 24

    private var isEditingWallet: Bool {
        draft.isEditingWallet
    }

    private var isCreateMode: Bool {
        draft.isCreateMode
    }

    private var isWatchAddressesImportMode: Bool {
        !isEditingWallet && !isCreateMode && draft.isWatchOnlyMode
    }

    private var usesSeedPhraseFlow: Bool {
        !isEditingWallet && !draft.isWatchOnlyMode
    }

    private var isPrivateKeyImportMode: Bool {
        draft.isPrivateKeyImportMode
    }

    private var usesWatchAddressesFlow: Bool {
        !isEditingWallet && draft.isWatchOnlyMode
    }

    private var isShowingDetailsPage: Bool {
        setupPage == .details
    }

    private var isShowingSeedPhrasePage: Bool {
        setupPage == .seedPhrase
    }

    private var isShowingWatchAddressesPage: Bool {
        setupPage == .watchAddresses
    }

    private var isShowingPasswordPage: Bool {
        setupPage == .password
    }

    private var isShowingBackupVerificationPage: Bool {
        setupPage == .backupVerification
    }

    private var isShowingAdvancedPage: Bool {
        setupPage == .advanced
    }

    private var setupTitle: String {
        if isShowingBackupVerificationPage {
            return copy.backupVerificationTitle
        }
        if isShowingAdvancedPage {
            return copy.advancedTitle
        }
        if isShowingPasswordPage {
            return NSLocalizedString("import_flow.wallet_password_title", comment: "Setup page title for optional wallet password step")
        }
        if isShowingWatchAddressesPage {
            return copy.watchAddressesTitle
        }
        if isShowingSeedPhrasePage {
            if isCreateMode {
                return copy.recordSeedPhraseTitle
            }
            return isPrivateKeyImportMode ? copy.enterPrivateKeyTitle : copy.enterSeedPhraseTitle
        }
        if isEditingWallet {
            return copy.editWalletTitle
        }
        if isCreateMode {
            return copy.createWalletTitle
        }
        return isWatchAddressesImportMode ? copy.watchAddressesTitle : copy.importWalletTitle
    }

    private var setupSubtitle: String {
        if isShowingBackupVerificationPage {
            return copy.backupVerificationSubtitle
        }
        if isShowingAdvancedPage {
            return copy.advancedSubtitle
        }
        if isShowingPasswordPage {
            return NSLocalizedString("import_flow.wallet_password_subtitle", comment: "Setup page subtitle for optional wallet password step")
        }
        if isShowingWatchAddressesPage {
            return copy.watchAddressesSubtitle
        }
        if isShowingSeedPhrasePage {
            if isPrivateKeyImportMode {
                return copy.privateKeySubtitle
            }
            return isCreateMode
                ? copy.saveRecoveryPhraseSubtitle
                : copy.enterRecoveryPhraseSubtitle
        }
        if isEditingWallet {
            return copy.editWalletSubtitle
        }
        if isCreateMode {
            return copy.chooseNameAndChainsSubtitle
        }
        if isWatchAddressesImportMode {
            return copy.chooseNameAndChainSubtitle
        }
        return copy.chooseNameAndChainsSubtitle
    }

    private var seedPhraseStatusText: String {
        if draft.seedPhraseWords.isEmpty {
            return ""
        }
        if !draft.invalidSeedWords.isEmpty {
            let format = NSLocalizedString("import_flow.seed_phrase_invalid_words_format", comment: "Seed phrase invalid words status")
            return String(format: format, draft.invalidSeedWords.joined(separator: ", "))
        }
        if draft.seedPhraseWords.count < draft.selectedSeedPhraseWordCount {
            let format = NSLocalizedString("import_flow.seed_phrase_progress_format", comment: "Seed phrase progress status")
            return String(format: format, draft.seedPhraseWords.count, draft.selectedSeedPhraseWordCount)
        }
        if let validationError = draft.seedPhraseValidationError {
            return validationError
        }
        return NSLocalizedString("import_flow.seed_phrase_valid_status", comment: "Seed phrase valid status")
    }

    private var seedPhraseStatusColor: Color {
        if draft.seedPhraseWords.isEmpty || draft.seedPhraseWords.count < draft.selectedSeedPhraseWordCount {
            return .white.opacity(0.7)
        }
        if !draft.invalidSeedWords.isEmpty || draft.seedPhraseValidationError != nil {
            return .red.opacity(0.9)
        }
        return .green.opacity(0.9)
    }

    /// Handles "seedPhraseBinding" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private func seedPhraseBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { draft.seedPhraseEntry(at: index) },
            set: { newValue in
                let shouldAdvance = newValue.last?.isWhitespace == true
                let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.updateSeedPhraseEntry(at: index, with: trimmedValue)

                guard shouldAdvance, !trimmedValue.isEmpty else { return }
                focusedSeedPhraseIndex = (index + 1) < draft.selectedSeedPhraseWordCount ? (index + 1) : nil
            }
        )
    }

    /// Handles "backupVerificationBinding" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private func backupVerificationBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.backupVerificationEntries.indices.contains(index) else { return "" }
                return draft.backupVerificationEntries[index]
            },
            set: { draft.updateBackupVerificationEntry(at: index, with: $0) }
        )
    }

    private var canContinueFromSecretStep: Bool {
        let hasChains = !draft.selectedChainNames.isEmpty
        if draft.isPrivateKeyImportMode {
            return hasChains
                && WalletCoreDerivation.isLikelyPrivateKeyHex(draft.privateKeyInput)
                && draft.unsupportedPrivateKeyChainNames.isEmpty
                && draft.selectedChainNames.count == 1
                && !store.isImportingWallet
        }

        let hasValidSeedPhrase = draft.seedPhraseWords.count == draft.selectedSeedPhraseWordCount
            && draft.seedPhraseValidationError == nil
            && draft.invalidSeedWords.isEmpty
            && draft.hasValidSeedPhraseChecksum
        return hasChains && hasValidSeedPhrase && !store.isImportingWallet
    }

    private var canContinueToBackupVerification: Bool {
        canContinueFromSecretStep
            && draft.walletPasswordValidationError == nil
            && !store.isImportingWallet
    }

    private var canSubmitFromPasswordStep: Bool {
        draft.walletPasswordValidationError == nil
            && store.canImportWallet
            && !store.isImportingWallet
    }

    private var canAdvanceFromDetailsPage: Bool {
        if usesSeedPhraseFlow {
            return !draft.selectedChainNames.isEmpty && !store.isImportingWallet
        }
        if usesWatchAddressesFlow {
            return !draft.selectedChainNames.isEmpty && !store.isImportingWallet
        }
        return store.canImportWallet && !store.isImportingWallet
    }

    private var primaryActionTitle: String {
        if isShowingDetailsPage && (usesSeedPhraseFlow || usesWatchAddressesFlow) {
            return NSLocalizedString("import_flow.next", comment: "Primary action title for next step")
        }
        if isShowingAdvancedPage {
            return ""
        }
        if isShowingSeedPhrasePage {
            return NSLocalizedString("import_flow.next", comment: "Primary action title for next step")
        }
        if isShowingPasswordPage && isCreateMode {
            return NSLocalizedString("import_flow.continue_to_backup_verification", comment: "Primary action title to continue to seed backup verification")
        }
        if isEditingWallet {
            return NSLocalizedString("import_flow.save_wallet", comment: "Primary action title to save wallet edits")
        }
        if isCreateMode {
            return NSLocalizedString("import_flow.create_wallet", comment: "Primary action title to create wallet")
        }
        return isWatchAddressesImportMode
            ? NSLocalizedString("import_flow.watch_addresses", comment: "Primary action title for watch addresses flow")
            : NSLocalizedString("import_flow.import_wallet", comment: "Primary action title to import wallet")
    }

    private var isPrimaryActionEnabled: Bool {
        if isShowingDetailsPage && (usesSeedPhraseFlow || usesWatchAddressesFlow) {
            return canAdvanceFromDetailsPage
        }
        if isShowingAdvancedPage {
            return false
        }
        if isShowingSeedPhrasePage {
            return canContinueFromSecretStep
        }
        if isShowingPasswordPage && isCreateMode {
            return canContinueToBackupVerification
        }
        if isShowingPasswordPage {
            return canSubmitFromPasswordStep
        }
        return store.canImportWallet && !store.isImportingWallet
    }

    private var popularChainSelectionDescriptors: [SetupChainSelectionDescriptor] {
        Self.chainSelectionDescriptors.filter { Self.popularChainSelectionIDs.contains($0.id) }
    }

    private var selectedChainNameSet: Set<String> {
        Set(draft.selectedChainNames)
    }

    private var selectedChainCount: Int {
        draft.selectedChainNames.count
    }

    private var chainSelectionSummary: String {
        switch selectedChainCount {
        case 0:
            return NSLocalizedString("import_flow.no_chains_selected", comment: "No chains selected summary")
        case 1:
            return NSLocalizedString("import_flow.one_chain_selected", comment: "Single chain selected summary")
        default:
            let format = NSLocalizedString("import_flow.multiple_chains_selected_format", comment: "Multiple chains selected summary")
            return String(format: format, selectedChainCount)
        }
    }

    private var chainSelectionSubtitle: String {
        if isCreateMode {
            return NSLocalizedString("import_flow.create_chain_selection_subtitle", comment: "Chain selection subtitle for create flow")
        }
        return NSLocalizedString("import_flow.import_chain_selection_subtitle", comment: "Chain selection subtitle for import flow")
    }

    @ViewBuilder
    /// Handles "seedPhraseField" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private func seedPhraseField(at index: Int) -> some View {
        let entry = draft.seedPhraseEntry(at: index).trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvalidWord = !entry.isEmpty && !BIP39EnglishWordList.words.contains(entry)
        numberedSeedPhraseRow(index: index, isInvalidWord: isInvalidWord)
    }

    @ViewBuilder
    private func watchedAddressEditor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .frame(minHeight: 88)
            .padding(10)
            .spectraInputFieldStyle()
            .foregroundStyle(Color.primary)
    }

    @ViewBuilder
    private func setupCard(glassOpacity: Double = 0.028, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16)
            .spectraBubbleFill()
            .glassEffect(.regular.tint(.white.opacity(glassOpacity)), in: .rect(cornerRadius: setupCardCornerRadius))
    }

    @ViewBuilder
    private var walletPasswordStepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("import_flow.wallet_password_optional", comment: "Optional wallet password section title"))
                .font(.headline)
                .foregroundStyle(Color.primary)

            Text(NSLocalizedString("import_flow.wallet_password_explanation", comment: "Optional wallet password explanation"))
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.76))

            SecureField(NSLocalizedString("import_flow.wallet_password_field", comment: "Wallet password field placeholder"), text: $draft.walletPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)

            SecureField(NSLocalizedString("import_flow.wallet_password_confirmation_field", comment: "Wallet password confirmation field placeholder"), text: $draft.walletPasswordConfirmation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)

            if let walletPasswordValidationError = draft.walletPasswordValidationError {
                Text(walletPasswordValidationError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            } else if draft.normalizedWalletPassword != nil {
                Text(NSLocalizedString("import_flow.wallet_password_success", comment: "Wallet password confirmation helper text"))
                    .font(.caption)
                    .foregroundStyle(.green.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private func chainSelectionCard(_ descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNameSet.contains(descriptor.chainName)

        Button {
            draft.toggleChainSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 10) {
                CoinBadge(
                    assetIdentifier: descriptor.assetIdentifier,
                    fallbackText: descriptor.mark,
                    color: descriptor.color,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(descriptor.symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.6))
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.28))
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? descriptor.color.opacity(0.12) : Color.white.opacity(colorScheme == .light ? 0.6 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? descriptor.color.opacity(0.9) : Color.primary.opacity(colorScheme == .light ? 0.12 : 0.08), lineWidth: isSelected ? 1.6 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func seedPhraseLengthPicker(
        title: String,
        subtitle: String,
        showsRegenerateButton: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizedWalletFlowString(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.88))

            Text(localizedWalletFlowString(subtitle))
                .font(.footnote)
                .foregroundStyle(Color.primary.opacity(0.7))

            HStack(spacing: 12) {
                Picker("Seed Phrase Length", selection: $draft.selectedSeedPhraseWordCount) {
                    ForEach(BitcoinWalletEngine.validMnemonicWordCounts, id: \.self) { wordCount in
                        Text(localizedFormat("%lld words", wordCount)).tag(wordCount)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .spectraInputFieldStyle()
                .tint(.white)

                if showsRegenerateButton {
                    Button("Regenerate") {
                        draft.regenerateSeedPhrase()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    @ViewBuilder
    private func numberedSeedPhraseRow(index: Int, text: String? = nil, isInvalidWord: Bool = false) -> some View {
        let validEntryColor: Color = colorScheme == .light ? Color.black.opacity(0.82) : .white

        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            if let text {
                Text(text)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                TextField("word \(index + 1)", text: seedPhraseBinding(for: index))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(isInvalidWord ? .red.opacity(0.95) : validEntryColor)
                    .focused($focusedSeedPhraseIndex, equals: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .spectraInputFieldStyle(borderColor: isInvalidWord ? Color.red.opacity(0.85) : nil)
    }

    @ViewBuilder
    private func watchedAddressSection(
        title: String,
        text: Binding<String>,
        caption: String? = nil,
        validationMessage: String? = nil,
        validationColor: Color? = nil
    ) -> some View {
        Text(localizedWalletFlowString(title))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(0.88))
        watchedAddressEditor(text: text)
        if let caption {
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.65))
        }
        if let validationMessage {
            Text(validationMessage)
                .font(.caption)
                .foregroundStyle(validationColor ?? Color.primary.opacity(0.72))
        }
    }

    private func watchedAddressValidationMessage(
        entries: [String],
        assetName: String,
        validator: (String) -> Bool
    ) -> (message: String, color: Color) {
        let localizedAssetName = assetName
        if entries.isEmpty {
            return (localizedFormat("Enter one %@ address per line.", localizedAssetName), Color.primary.opacity(0.72))
        }
        if !entries.allSatisfy(validator) {
            return (localizedFormat("Every line must contain a valid %@ address.", localizedAssetName), .red.opacity(0.9))
        }
        let count = entries.count
        let pluralSuffix = AppLocalization.locale.identifier.hasPrefix("en") && count != 1 ? "es" : ""
        return (localizedFormat("%lld valid %@ address%@ ready to import.", count, localizedAssetName, pluralSuffix), .green.opacity(0.9))
    }

    @ViewBuilder
    private var derivationAdvancedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Control the derivation path used for each selected chain.")
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.76))

            VStack(alignment: .leading, spacing: 16) {
                ForEach(draft.selectableDerivationChains) { chain in
                    SeedPathSlotEditor(
                        title: chain.rawValue,
                        path: Binding(
                            get: { draft.seedDerivationPaths.path(for: chain) },
                            set: { draft.seedDerivationPaths.setPath($0, for: chain) }
                        ),
                        defaultPath: chain.defaultPath
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var derivationAdvancedButton: some View {
        if !isEditingWallet && !draft.selectedChainNames.isEmpty {
            Button {
                withAnimation {
                    setupPage = .advanced
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 26, height: 26)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Advanced")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Text("Adjust derivation paths.")
                            .font(.caption2)
                            .foregroundStyle(Color.primary.opacity(0.68))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .spectraInputFieldStyle()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var importSecretModePicker: some View {
        if !isEditingWallet && !isCreateMode && !draft.isWatchOnlyMode {
            VStack(alignment: .leading, spacing: 10) {
                Text("Import Method")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.88))

                Picker("Import Method", selection: importSecretModeBinding) {
                    ForEach(WalletSecretImportMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(draft.secretImportMode == .seedPhrase
                    ? copy.seedImportMethodDescription
                    : copy.privateKeyImportMethodDescription)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.68))
            }
        }
    }

    private var importSecretModeBinding: Binding<WalletSecretImportMode> {
        Binding(
            get: { draft.secretImportMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    draft.secretImportMode = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var newWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(
            title: copy.importSeedLengthTitle,
            subtitle: copy.importSeedLengthSubtitle
        )

        Text(copy.seedPhraseEntryHelp)
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(0.7))

        LazyVGrid(columns: seedPhraseGridColumns, spacing: 12) {
            ForEach(0 ..< draft.selectedSeedPhraseWordCount, id: \.self) { index in
                seedPhraseField(at: index)
            }
        }

            if !seedPhraseStatusText.isEmpty {
                Text(seedPhraseStatusText)
                    .font(.footnote)
                    .foregroundStyle(seedPhraseStatusColor)
            }
    }

    @ViewBuilder
    private var createWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(
            title: copy.createSeedLengthTitle,
            subtitle: copy.createSeedLengthSubtitle,
            showsRegenerateButton: true
        )

        Text(copy.createSeedPhraseWarning)
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(0.72))

        LazyVGrid(columns: seedPhraseGridColumns, spacing: 12) {
            ForEach(Array(draft.seedPhraseWords.enumerated()), id: \.offset) { index, word in
                numberedSeedPhraseRow(index: index, text: word)
            }
        }
    }

    @ViewBuilder
    private var privateKeyImportSection: some View {
        importSecretModePicker

        privateKeyImportFields
    }

    @ViewBuilder
    private var privateKeyImportFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.privateKeyTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.88))

            Text(copy.privateKeyPrompt)
                .font(.footnote)
                .foregroundStyle(Color.primary.opacity(0.7))

            TextField(copy.privateKeyPlaceholder, text: $draft.privateKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)

            if !draft.unsupportedPrivateKeyChainNames.isEmpty {
                Text(localizedFormat("Private key import is not available for: %@.", draft.unsupportedPrivateKeyChainNames.joined(separator: ", ")))
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.9))
            } else if !draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !WalletCoreDerivation.isLikelyPrivateKeyHex(draft.privateKeyInput) {
                Text("Enter a valid 32-byte hex private key.")
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var walletSecretStepSection: some View {
        if isCreateMode {
            createWalletSeedPhraseSection
            derivationAdvancedButton
        } else {
            importSecretModePicker

            Group {
                if isPrivateKeyImportMode {
                    privateKeyImportFields
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        newWalletSeedPhraseSection
                        derivationAdvancedButton
                    }
                }
            }
            .id(draft.secretImportMode)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: draft.secretImportMode)
        }
    }

    @ViewBuilder
    private var backupVerificationStepSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.backupVerificationTitle)
                .font(.headline)
                .foregroundStyle(Color.primary)

            Text(draft.backupVerificationPromptLabel)
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.76))

            if draft.backupVerificationWordIndices.isEmpty {
                Button(copy.backupVerificationButtonTitle) {
                    draft.prepareBackupVerificationChallenge()
                }
                .buttonStyle(.glass)
            } else {
                ForEach(Array(draft.backupVerificationWordIndices.enumerated()), id: \.offset) { offset, wordIndex in
                    HStack(spacing: 10) {
                        Text(localizedFormat("Word #%lld", wordIndex + 1))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.primary.opacity(0.82))
                            .frame(width: 88, alignment: .leading)

                        TextField("Enter word \(wordIndex + 1)", text: backupVerificationBinding(for: offset))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: 16)
                }

                if draft.isBackupVerificationComplete {
                    Text(copy.backupVerifiedMessage)
                        .font(.footnote)
                        .foregroundStyle(.green.opacity(0.9))
                } else {
                    Text(copy.backupVerificationHint)
                        .font(.footnote)
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
            }
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
    
    var body: some View {
        ZStack {
            SpectraBackdrop()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    setupCard(glassOpacity: 0.033) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                SpectraLogo(size: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(setupTitle)
                                        .font(.system(size: 28, weight: .black, design: .rounded))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                        .allowsTightening(true)
                                        .layoutPriority(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(setupSubtitle)
                                        .font(.footnote)
                                        .foregroundStyle(Color.primary.opacity(0.76))
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    if isShowingBackupVerificationPage {
                        backupVerificationStepSection
                    } else if !isEditingWallet && isShowingDetailsPage {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Chains")
                                            .font(.headline)
                                            .foregroundStyle(Color.primary)
                                    }
                                    Spacer()
                                    Text(chainSelectionSummary)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selectedChainCount == 0 ? Color.primary.opacity(0.68) : .orange)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(selectedChainCount == 0 ? Color.white.opacity(colorScheme == .light ? 0.55 : 0.08) : Color.orange.opacity(0.12))
                                        )
                                }

                                LazyVGrid(columns: chainSelectionColumns, spacing: 10) {
                                    ForEach(popularChainSelectionDescriptors) { descriptor in
                                        chainSelectionCard(descriptor)
                                    }
                                }

                                if !Self.nonPopularChainSelectionDescriptors.isEmpty {
                                    Button {
                                        chainSearchText = ""
                                        isShowingAllChainsSheet = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "square.grid.2x2")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.orange)
                                                .frame(width: 26, height: 26)
                                                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("See All Chains")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(Color.primary)
                                                Text("Browse the full chain list.")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.primary.opacity(0.68))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.primary.opacity(0.72))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .spectraInputFieldStyle()
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(chainSelectionSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(Color.primary.opacity(0.72))

                                if isEditingWallet {
                                    Text(copy.watchOnlyFixedMessage)
                                        .font(.caption)
                                        .foregroundStyle(Color.primary.opacity(0.6))
                                } else if isWatchAddressesImportMode {
                                    Text(copy.publicAddressOnlyMessage)
                                        .font(.caption)
                                        .foregroundStyle(Color.primary.opacity(0.6))
                                } else if draft.wantsMonero {
                                    Text(copy.moneroWatchUnsupportedMessage)
                                        .font(.caption)
                                        .foregroundStyle(.orange.opacity(0.9))
                                }
                            }
                            .tint(.orange)
                        }
                        .sheet(isPresented: $isShowingAllChainsSheet) {
                            AllChainsSelectionView(
                                chainSearchText: $chainSearchText,
                                descriptors: Self.sortedChainSelectionDescriptors,
                                selectedChainNames: selectedChainNameSet,
                                toggleSelection: draft.toggleChainSelection
                            )
                        }
                    }
                    
                    if isShowingWatchAddressesPage, !isEditingWallet, draft.isWatchOnlyMode {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                            Text(copy.addressesToWatchTitle)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Text(copy.addressesToWatchSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.76))

                            if draft.wantsBitcoin {
                                let bitcoinAddressEntries = draft.watchOnlyEntries(from: draft.bitcoinAddressInput)
                                let bitcoinValidation = watchedAddressValidationMessage(
                                    entries: bitcoinAddressEntries,
                                    assetName: "Bitcoin",
                                    validator: { AddressValidation.isValidBitcoinAddress($0, networkMode: store.bitcoinNetworkMode) }
                                )
                                watchedAddressSection(
                                    title: "Bitcoin",
                                    text: $draft.bitcoinAddressInput,
                                    caption: copy.bitcoinWatchCaption,
                                    validationMessage: bitcoinValidation.message,
                                    validationColor: bitcoinValidation.color
                                )
                                TextField("xpub... / zpub...", text: $draft.bitcoinXPubInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(14)
                                    .spectraInputFieldStyle()
                                    .foregroundStyle(Color.primary)
                            }

                            if draft.wantsBitcoinCash {
                                let bitcoinCashAddressEntries = draft.watchOnlyEntries(from: draft.bitcoinCashAddressInput)
                                let bitcoinCashValidation = watchedAddressValidationMessage(
                                    entries: bitcoinCashAddressEntries,
                                    assetName: "Bitcoin Cash",
                                    validator: { AddressValidation.isValidBitcoinCashAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Bitcoin Cash",
                                    text: $draft.bitcoinCashAddressInput,
                                    validationMessage: bitcoinCashValidation.message,
                                    validationColor: bitcoinCashValidation.color
                                )
                            }

                            if draft.wantsBitcoinSV {
                                let bitcoinSVAddressEntries = draft.watchOnlyEntries(from: draft.bitcoinSVAddressInput)
                                let bitcoinSVValidation = watchedAddressValidationMessage(
                                    entries: bitcoinSVAddressEntries,
                                    assetName: "Bitcoin SV",
                                    validator: { AddressValidation.isValidBitcoinSVAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Bitcoin SV",
                                    text: $draft.bitcoinSVAddressInput,
                                    validationMessage: bitcoinSVValidation.message,
                                    validationColor: bitcoinSVValidation.color
                                )
                            }

                            if draft.wantsDogecoin {
                                let dogecoinAddressEntries = draft.watchOnlyEntries(from: draft.dogecoinAddressInput)
                                let dogecoinValidation = watchedAddressValidationMessage(
                                    entries: dogecoinAddressEntries,
                                    assetName: "Dogecoin",
                                    validator: { AddressValidation.isValidDogecoinAddress($0, allowTestnet: store.dogecoinAllowTestnet) }
                                )
                                watchedAddressSection(
                                    title: "Dogecoin",
                                    text: $draft.dogecoinAddressInput,
                                    validationMessage: dogecoinValidation.message,
                                    validationColor: dogecoinValidation.color
                                )
                            }

                            if draft.wantsLitecoin {
                                let litecoinAddressEntries = draft.watchOnlyEntries(from: draft.litecoinAddressInput)
                                let litecoinValidation = watchedAddressValidationMessage(
                                    entries: litecoinAddressEntries,
                                    assetName: "Litecoin",
                                    validator: { AddressValidation.isValidLitecoinAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Litecoin",
                                    text: $draft.litecoinAddressInput,
                                    validationMessage: litecoinValidation.message,
                                    validationColor: litecoinValidation.color
                                )
                            }

                            if draft.wantsEthereum || draft.wantsEthereumClassic || draft.wantsArbitrum || draft.wantsOptimism || draft.wantsBNBChain || draft.wantsAvalanche || draft.wantsHyperliquid {
                                let ethereumAddressEntries = draft.watchOnlyEntries(from: draft.ethereumAddressInput)
                                let evmValidation = watchedAddressValidationMessage(
                                    entries: ethereumAddressEntries,
                                    assetName: "EVM",
                                    validator: { AddressValidation.isValidEthereumAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "EVM (Ethereum / ETC / Arbitrum / Optimism / BNB Chain / Avalanche / Hyperliquid)",
                                    text: $draft.ethereumAddressInput,
                                    validationMessage: evmValidation.message,
                                    validationColor: evmValidation.color
                                )
                            }

                            if draft.wantsTron {
                                let tronAddressEntries = draft.watchOnlyEntries(from: draft.tronAddressInput)
                                let tronValidation = watchedAddressValidationMessage(
                                    entries: tronAddressEntries,
                                    assetName: "Tron",
                                    validator: { AddressValidation.isValidTronAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Tron",
                                    text: $draft.tronAddressInput,
                                    validationMessage: tronValidation.message,
                                    validationColor: tronValidation.color
                                )
                            }

                            if draft.wantsSolana {
                                let solanaAddressEntries = draft.watchOnlyEntries(from: draft.solanaAddressInput)
                                let solanaValidation = watchedAddressValidationMessage(
                                    entries: solanaAddressEntries,
                                    assetName: "Solana",
                                    validator: { AddressValidation.isValidSolanaAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Solana",
                                    text: $draft.solanaAddressInput,
                                    validationMessage: solanaValidation.message,
                                    validationColor: solanaValidation.color
                                )
                            }

                            if draft.wantsXRP {
                                let xrpAddressEntries = draft.watchOnlyEntries(from: draft.xrpAddressInput)
                                let xrpValidation = watchedAddressValidationMessage(
                                    entries: xrpAddressEntries,
                                    assetName: "XRP Ledger",
                                    validator: { AddressValidation.isValidXRPAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "XRP Ledger",
                                    text: $draft.xrpAddressInput,
                                    validationMessage: xrpValidation.message,
                                    validationColor: xrpValidation.color
                                )
                            }

                            if draft.wantsMonero {
                                watchedAddressSection(title: "Monero", text: $draft.moneroAddressInput)
                            }

                            if draft.wantsCardano {
                                let cardanoAddressEntries = draft.watchOnlyEntries(from: draft.cardanoAddressInput)
                                let cardanoValidation = watchedAddressValidationMessage(
                                    entries: cardanoAddressEntries,
                                    assetName: "Cardano",
                                    validator: { AddressValidation.isValidCardanoAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Cardano",
                                    text: $draft.cardanoAddressInput,
                                    validationMessage: cardanoValidation.message,
                                    validationColor: cardanoValidation.color
                                )
                            }

                            if draft.wantsSui {
                                let suiAddressEntries = draft.watchOnlyEntries(from: draft.suiAddressInput)
                                let suiValidation = watchedAddressValidationMessage(
                                    entries: suiAddressEntries,
                                    assetName: "Sui",
                                    validator: { AddressValidation.isValidSuiAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Sui",
                                    text: $draft.suiAddressInput,
                                    validationMessage: suiValidation.message,
                                    validationColor: suiValidation.color
                                )
                            }

                            if draft.wantsAptos {
                                let aptosAddressEntries = draft.watchOnlyEntries(from: draft.aptosAddressInput)
                                let aptosValidation = watchedAddressValidationMessage(
                                    entries: aptosAddressEntries,
                                    assetName: "Aptos",
                                    validator: { AddressValidation.isValidAptosAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Aptos",
                                    text: $draft.aptosAddressInput,
                                    validationMessage: aptosValidation.message,
                                    validationColor: aptosValidation.color
                                )
                            }

                            if draft.wantsTON {
                                let tonAddressEntries = draft.watchOnlyEntries(from: draft.tonAddressInput)
                                let tonValidation = watchedAddressValidationMessage(
                                    entries: tonAddressEntries,
                                    assetName: "TON",
                                    validator: { AddressValidation.isValidTONAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "TON",
                                    text: $draft.tonAddressInput,
                                    validationMessage: tonValidation.message,
                                    validationColor: tonValidation.color
                                )
                            }

                            if draft.wantsICP {
                                let icpAddressEntries = draft.watchOnlyEntries(from: draft.icpAddressInput)
                                let icpValidation = watchedAddressValidationMessage(
                                    entries: icpAddressEntries,
                                    assetName: "Internet Computer",
                                    validator: { AddressValidation.isValidICPAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Internet Computer",
                                    text: $draft.icpAddressInput,
                                    validationMessage: icpValidation.message,
                                    validationColor: icpValidation.color
                                )
                            }

                            if draft.wantsNear {
                                let nearAddressEntries = draft.watchOnlyEntries(from: draft.nearAddressInput)
                                let nearValidation = watchedAddressValidationMessage(
                                    entries: nearAddressEntries,
                                    assetName: "NEAR",
                                    validator: { AddressValidation.isValidNearAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "NEAR",
                                    text: $draft.nearAddressInput,
                                    validationMessage: nearValidation.message,
                                    validationColor: nearValidation.color
                                )
                            }

                            if draft.wantsPolkadot {
                                let polkadotAddressEntries = draft.watchOnlyEntries(from: draft.polkadotAddressInput)
                                let polkadotValidation = watchedAddressValidationMessage(
                                    entries: polkadotAddressEntries,
                                    assetName: "Polkadot",
                                    validator: { AddressValidation.isValidPolkadotAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Polkadot",
                                    text: $draft.polkadotAddressInput,
                                    validationMessage: polkadotValidation.message,
                                    validationColor: polkadotValidation.color
                                )
                            }

                            if draft.wantsStellar {
                                let stellarAddressEntries = draft.watchOnlyEntries(from: draft.stellarAddressInput)
                                let stellarValidation = watchedAddressValidationMessage(
                                    entries: stellarAddressEntries,
                                    assetName: "Stellar",
                                    validator: { AddressValidation.isValidStellarAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "Stellar",
                                    text: $draft.stellarAddressInput,
                                    validationMessage: stellarValidation.message,
                                    validationColor: stellarValidation.color
                                )
                            }

                            if !draft.wantsBitcoin && !draft.wantsBitcoinCash && !draft.wantsBitcoinSV && !draft.wantsLitecoin && !draft.wantsDogecoin && !draft.wantsEthereum && !draft.wantsEthereumClassic && !draft.wantsSolana && !draft.wantsBNBChain && !draft.wantsTron && !draft.wantsXRP && !draft.wantsMonero && !draft.wantsCardano && !draft.wantsSui && !draft.wantsAptos && !draft.wantsTON && !draft.wantsICP && !draft.wantsNear && !draft.wantsPolkadot && !draft.wantsStellar {
                                Text("Select a supported chain above to enter its address to watch.")
                                    .font(.caption)
                                    .foregroundStyle(.orange.opacity(0.9))
                            }
                        }
                        }
                    }
                    
                    if isShowingDetailsPage || isEditingWallet {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(
                                    isEditingWallet
                                        ? NSLocalizedString("import_flow.wallet_name", comment: "Wallet name field title")
                                        : NSLocalizedString("import_flow.wallet_name_optional", comment: "Optional wallet name field title")
                                )
                                    .font(.headline)
                                    .foregroundStyle(Color.primary)

                                if !isEditingWallet {
                                    Text(NSLocalizedString("import_flow.wallet_name_hint", comment: "Wallet name helper text"))
                                        .font(.subheadline)
                                        .foregroundStyle(Color.primary.opacity(0.76))
                                }

                                TextField(NSLocalizedString("import_flow.wallet_name_placeholder", comment: "Wallet name placeholder"), text: $draft.walletName)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .padding(14)
                                    .spectraInputFieldStyle()
                                    .foregroundStyle(Color.primary)

                            }
                        }
                    }

                    if isShowingSeedPhrasePage && !draft.isWatchOnlyMode {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                                walletSecretStepSection
                            }
                        }
                    }

                    if isShowingPasswordPage {
                        setupCard {
                            walletPasswordStepSection
                        }
                    }

                    if isShowingAdvancedPage {
                        setupCard {
                            derivationAdvancedContent
                        }
                    }

                    if let importError = store.importError {
                        Text(importError)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    if store.isImportingWallet {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text(NSLocalizedString("import_flow.initializing_wallet_connections", comment: "Wallet import progress message"))
                                .font(.footnote)
                                .foregroundStyle(Color.primary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !isShowingAdvancedPage {
                        Button(action: {
                            if isShowingDetailsPage && usesWatchAddressesFlow {
                                withAnimation {
                                    setupPage = .watchAddresses
                                }
                                return
                            }
                            if isShowingDetailsPage && usesSeedPhraseFlow {
                                withAnimation {
                                    setupPage = .seedPhrase
                                }
                                return
                            }
                            if isShowingSeedPhrasePage {
                                withAnimation {
                                    setupPage = .password
                                }
                                return
                            }
                            if isShowingPasswordPage && isCreateMode {
                                draft.prepareBackupVerificationChallenge()
                                withAnimation {
                                    setupPage = .backupVerification
                                }
                                return
                            }
                            Task {
                                await store.importWallet()
                            }
                        }) {
                            HStack {
                                Text(primaryActionTitle)
                                    .font(.headline)
                                Spacer()
                                SpectraLogo(size: 28)
                            }
                            .foregroundStyle(Color.primary)
                            .padding()
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!isPrimaryActionEnabled)
                        .opacity(isPrimaryActionEnabled ? 1.0 : 0.55)
                    }

                    if isShowingSeedPhrasePage || isShowingWatchAddressesPage {
                        Button(NSLocalizedString("import_flow.back", comment: "Back button title")) {
                            withAnimation {
                                setupPage = .details
                            }
                        }
                        .buttonStyle(.glass)
                    } else if isShowingAdvancedPage {
                        Button(NSLocalizedString("import_flow.back", comment: "Back button title")) {
                            withAnimation {
                                setupPage = .seedPhrase
                            }
                        }
                        .buttonStyle(.glass)
                    } else if isShowingPasswordPage {
                        Button(NSLocalizedString("import_flow.back", comment: "Back button title")) {
                            withAnimation {
                                setupPage = .seedPhrase
                            }
                        }
                        .buttonStyle(.glass)
                    } else if isShowingBackupVerificationPage {
                        Button(NSLocalizedString("import_flow.back_to_wallet_password", comment: "Back button title to wallet password step")) {
                            withAnimation {
                                setupPage = .password
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .onChange(of: draft.mode) { _, mode in
            setupPage = .details
        }
    }
}

private struct AllChainsSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var chainSearchText: String
    let descriptors: [SetupChainSelectionDescriptor]
    let selectedChainNames: Set<String>
    let toggleSelection: (String) -> Void

    private var filteredDescriptors: [SetupChainSelectionDescriptor] {
        let query = chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return descriptors
        }
        return descriptors.filter { descriptor in
            descriptor.title.localizedCaseInsensitiveContains(query)
                || descriptor.symbol.localizedCaseInsensitiveContains(query)
        }
    }

    private var isSearching: Bool {
        !chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func row(for descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNames.contains(descriptor.chainName)

        Button {
            toggleSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 12) {
                CoinBadge(
                    assetIdentifier: descriptor.assetIdentifier,
                    fallbackText: descriptor.mark,
                    color: descriptor.color,
                    size: 28
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Text(descriptor.symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.56))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.24))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? descriptor.color.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                TextField(NSLocalizedString("import_flow.search_chains", comment: "Search chains placeholder"), text: $chainSearchText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .spectraInputFieldStyle()

                            if filteredDescriptors.isEmpty {
                                Text(NSLocalizedString("import_flow.no_chains_match", comment: "Empty state when no chains match the search"))
                                    .font(.caption)
                                    .foregroundStyle(Color.primary.opacity(0.7))
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(filteredDescriptors) { descriptor in
                                        row(for: descriptor)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .spectraBubbleFill()
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(NSLocalizedString("import_flow.all_chains_title", comment: "All chains sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("import_flow.done", comment: "Done button title")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SendView: View {
    @ObservedObject var store: WalletStore
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?

    private struct SendLiveActivitySnapshot {
        let walletName: String
        let chainName: String
        let symbol: String
        let amountText: String
        let destinationAddress: String
    }

    private var sendPreviewTaskID: String {
        [
            store.sendWalletID,
            store.sendHoldingKey,
            store.sendAddress,
            store.sendAmount,
            store.dogecoinFeePriority.rawValue,
            store.useCustomEthereumFees ? "custom-on" : "custom-off",
            store.customEthereumMaxFeeGwei,
            store.customEthereumPriorityFeeGwei,
            store.ethereumManualNonceEnabled ? "manual-nonce-on" : "manual-nonce-off",
            store.ethereumManualNonce,
            store.sendAdvancedMode ? "adv-on" : "adv-off",
            "\(store.sendUTXOMaxInputCount)"
        ].joined(separator: "|")
    }

    private var isSendBusy: Bool {
        store.isSendingBitcoin
            || store.isSendingBitcoinCash
            || store.isSendingLitecoin
            || store.isSendingEthereum
            || store.isSendingDogecoin
            || store.isSendingTron
            || store.isSendingXRP
            || store.isSendingMonero
            || store.isSendingCardano
            || store.isSendingNear
            || store.isPreparingEthereumSend
            || store.isPreparingDogecoinSend
            || store.isPreparingTronSend
            || store.isPreparingXRPSend
            || store.isPreparingMoneroSend
            || store.isPreparingCardanoSend
            || store.isPreparingNearSend
    }

    private var sendLiveActivitySnapshot: SendLiveActivitySnapshot? {
        guard let selectedCoin = store.selectedSendCoin else { return nil }
        guard let selectedWallet = store.sendEnabledWallets.first(where: { $0.id.uuidString == store.sendWalletID }) else { return nil }
        let trimmedAmount = store.sendAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAmount.isEmpty, !trimmedAddress.isEmpty else { return nil }
        return SendLiveActivitySnapshot(
            walletName: selectedWallet.name,
            chainName: selectedCoin.chainName,
            symbol: selectedCoin.symbol,
            amountText: trimmedAmount,
            destinationAddress: trimmedAddress
        )
    }

    @ViewBuilder
    private var primarySendSections: some View {
        let availableSendCoins = store.availableSendCoins(for: store.sendWalletID)
        let selectedCoin = availableSendCoins.first(where: { $0.holdingKey == store.sendHoldingKey })

        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let selectedCoin {
                        CoinBadge(
                            assetIdentifier: selectedCoin.iconIdentifier,
                            fallbackText: selectedCoin.mark,
                            color: selectedCoin.color,
                            size: 42
                        )
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.mint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send")
                            .font(.title3.weight(.bold))
                        if let wallet = store.sendEnabledWallets.first(where: { $0.id.uuidString == store.sendWalletID }) {
                            Text(wallet.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let selectedCoin {
                        Text(selectedCoin.symbol)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedCoin.color.opacity(0.18), in: Capsule())
                            .foregroundStyle(selectedCoin.color)
                    }
                }

                if let selectedCoin {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(store.formattedAssetAmount(selectedCoin.amount, symbol: selectedCoin.symbol, chainName: selectedCoin.chainName))
                                .font(.headline.weight(.semibold))
                                .spectraNumericTextLayout()
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Network")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedCoin.chainName)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } else {
                    Text("Choose a wallet and asset to prepare a transfer with live fee previews and risk checks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }

        Section("Wallet & Asset") {
            Picker("Wallet", selection: store.sendWalletIDBinding) {
                ForEach(store.sendEnabledWallets) { wallet in
                    Text(wallet.name).tag(wallet.id.uuidString)
                }
            }
            .onChange(of: store.sendWalletID) { _, _ in
                store.syncSendAssetSelection()
            }

            Picker("Asset", selection: store.sendHoldingKeyBinding) {
                ForEach(availableSendCoins, id: \.holdingKey) { coin in
                    Text("\(coin.name) on \(coin.chainName)").tag(coin.holdingKey)
                }
            }

            sendAssetSummary(selectedCoin)
        }

        Section("Recipient") {
            if !store.sendAddressBookEntries.isEmpty {
                Picker("Saved Recipient", selection: $selectedAddressBookEntryID) {
                    Text("None").tag("")
                    ForEach(store.sendAddressBookEntries) { entry in
                        Text("\(entry.name) • \(entry.chainName)").tag(entry.id.uuidString)
                    }
                }
                .onChange(of: selectedAddressBookEntryID) { _, newValue in
                    guard let selectedEntry = store.sendAddressBookEntries.first(where: { $0.id.uuidString == newValue }) else {
                        return
                    }
                    store.sendAddress = selectedEntry.address
                }
            }

            HStack(spacing: 10) {
                TextField("Recipient address", text: store.sendAddressBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    guard DataScannerViewController.isSupported else {
                        qrScannerErrorMessage = "QR scanning is not supported on this device."
                        return
                    }
                    guard DataScannerViewController.isAvailable else {
                        qrScannerErrorMessage = "QR scanning is unavailable right now. Check camera permission and try again."
                        return
                    }
                    isShowingQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Scan QR Code")
            }

            if let qrScannerErrorMessage {
                Text(qrScannerErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if store.isCheckingSendDestinationBalance {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking destination on-chain balance...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let sendDestinationRiskWarning = store.sendDestinationRiskWarning {
                Text(sendDestinationRiskWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let sendDestinationInfoMessage = store.sendDestinationInfoMessage {
                Text(sendDestinationInfoMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Amount") {
            TextField("Amount", text: store.sendAmountBinding)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let selectedCoin {
                HStack {
                    Text("Using")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(selectedCoin.symbol)
                        .font(.subheadline.weight(.semibold))
                }

                if let fiatAmount = store.formattedFiatAmount(fromNative: Double(store.sendAmount) ?? 0, symbol: selectedCoin.symbol),
                   !(Double(store.sendAmount) ?? 0).isZero {
                    HStack {
                        Text("Approx. Value")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(fiatAmount)
                            .font(.subheadline.weight(.semibold))
                            .spectraNumericTextLayout()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sendStatusSections: some View {
        if let sendError = store.sendError {
            Section {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        if let sendVerificationNotice = store.sendVerificationNotice {
            Section("Verification") {
                Text(sendVerificationNotice)
                    .font(.caption)
                    .foregroundStyle(store.sendVerificationNoticeIsWarning ? .red : .orange)
            }
        }

        if let lastSentTransaction = store.lastSentTransaction {
            Section("Last Sent") {
                Text(localizedFormat("%@ sent to %@", lastSentTransaction.symbol, lastSentTransaction.addressPreviewText))
                    .font(.subheadline)
                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TransactionStatusBadge(status: lastSentTransaction.status)
                }
                if let pendingTransactionRefreshStatusText = store.pendingTransactionRefreshStatusText {
                    Text(pendingTransactionRefreshStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let transactionHash = lastSentTransaction.transactionHash {
                    Text(transactionHash)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }

                if let transactionExplorerURL = lastSentTransaction.transactionExplorerURL,
                   let transactionExplorerLabel = lastSentTransaction.transactionExplorerLabel {
                    Link(destination: transactionExplorerURL) {
                        Label(transactionExplorerLabel, systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                }

                Button {
                    store.saveLastSentRecipientToAddressBook()
                } label: {
                    Label(
                        store.canSaveLastSentRecipientToAddressBook() ? "Save Recipient To Address Book" : "Recipient Already Saved",
                        systemImage: store.canSaveLastSentRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .disabled(!store.canSaveLastSentRecipientToAddressBook())
            }
        }

        if store.isSendingBitcoin {
            sendingSection("Broadcasting Bitcoin transaction...")
        }
        if store.isSendingBitcoinCash {
            sendingSection("Broadcasting Bitcoin Cash transaction...")
        }
        if store.isSendingLitecoin {
            sendingSection("Broadcasting Litecoin transaction...")
        }
        if store.isSendingEthereum {
            sendingSection("Broadcasting \(store.selectedSendCoin?.chainName ?? "EVM") transaction...")
        }
        if store.isSendingDogecoin {
            sendingSection("Broadcasting Dogecoin transaction...")
        }
        if store.isSendingTron {
            sendingSection("Broadcasting Tron transaction...")
        }
        if store.isSendingXRP {
            sendingSection("Broadcasting XRP transaction...")
        }
        if store.isSendingMonero {
            sendingSection("Broadcasting Monero transaction...")
        }
        if store.isSendingCardano {
            sendingSection("Broadcasting Cardano transaction...")
        }
    }

    private func sendingSection(_ title: String) -> some View {
        Section {
            HStack(spacing: 10) {
                ProgressView()
                Text(title)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func sendAssetSummary(_ coin: Coin?) -> some View {
        if let coin {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CoinBadge(
                        assetIdentifier: coin.iconIdentifier,
                        fallbackText: coin.mark,
                        color: coin.color,
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(coin.name)
                            .font(.headline)
                        Text(coin.chainName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                LabeledContent("Available") {
                    Text(store.formattedAssetAmount(coin.amount, symbol: coin.symbol, chainName: coin.chainName))
                        .font(.subheadline.weight(.semibold))
                        .spectraNumericTextLayout()
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func utxoPreview(for coin: Coin) -> BitcoinSendPreview? {
        if coin.chainName == "Litecoin" {
            return store.litecoinSendPreview
        }
        if coin.chainName == "Bitcoin Cash" {
            return store.bitcoinCashSendPreview
        }
        return store.bitcoinSendPreview
    }

    @ViewBuilder
    private func networkSendSections(selectedCoin: Coin?) -> some View {
        if let selectedCoin,
           selectedCoin.chainName == "Bitcoin" || selectedCoin.chainName == "Bitcoin Cash" || selectedCoin.chainName == "Bitcoin SV" || selectedCoin.chainName == "Litecoin" || selectedCoin.chainName == "Dogecoin" {
            Section("Advanced UTXO Mode") {
                Toggle("Enable Advanced Controls", isOn: $store.sendAdvancedMode)
                if store.sendAdvancedMode {
                    Stepper(
                        "Max Inputs: \(store.sendUTXOMaxInputCount == 0 ? "Auto" : "\(store.sendUTXOMaxInputCount)")",
                        value: $store.sendUTXOMaxInputCount,
                        in: 0 ... 50
                    )
                    if selectedCoin.chainName == "Litecoin" {
                        Toggle("Enable RBF Policy", isOn: $store.sendEnableRBF)
                        Picker("Change Strategy", selection: $store.sendLitecoinChangeStrategy) {
                            ForEach(LitecoinWalletEngine.ChangeStrategy.allCases) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("RBF Intent", isOn: $store.sendEnableRBF)
                        Toggle("CPFP Intent", isOn: $store.sendEnableCPFP)
                        if selectedCoin.chainName == "Bitcoin" {
                            Text("For Bitcoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedCoin.chainName == "Bitcoin Cash" {
                            Text("For Bitcoin Cash sends, advanced mode records RBF intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedCoin.chainName == "Dogecoin" {
                            Text("For Dogecoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if let selectedCoin,
           ((selectedCoin.chainName == "Bitcoin" && selectedCoin.symbol == "BTC")
               || (selectedCoin.chainName == "Bitcoin Cash" && selectedCoin.symbol == "BCH")
               || (selectedCoin.chainName == "Bitcoin SV" && selectedCoin.symbol == "BSV")
               || (selectedCoin.chainName == "Litecoin" && selectedCoin.symbol == "LTC")) {
            let feeSymbol = selectedCoin.symbol
            let utxoPreview = utxoPreview(for: selectedCoin)
            Section(localizedFormat("%@ Network", selectedCoin.chainName)) {
                Picker("Fee Priority", selection: $store.bitcoinFeePriority) {
                    ForEach(BitcoinFeePriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                if let utxoPreview {
                    Text(localizedFormat("Estimated Fee Rate: %llu sat/vB", utxoPreview.estimatedFeeRateSatVb))
                    if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFeeBTC, symbol: feeSymbol) {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBTC, specifier: "%.8f") \(feeSymbol) (~\(fiatFee))")
                    } else {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBTC, specifier: "%.8f") \(feeSymbol)")
                    }
                } else {
                    Text(localizedFormat("Enter amount to preview estimated %@ network fee.", selectedCoin.chainName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let selectedCoin,
           (selectedCoin.chainName == "Ethereum" || selectedCoin.chainName == "Ethereum Classic" || selectedCoin.chainName == "Arbitrum" || selectedCoin.chainName == "Optimism" || selectedCoin.chainName == "BNB Chain" || selectedCoin.chainName == "Avalanche" || selectedCoin.chainName == "Hyperliquid") {
            Section(localizedFormat("%@ Network", selectedCoin.chainName)) {
                Toggle("Use Custom Fees", isOn: $store.useCustomEthereumFees)

                if store.useCustomEthereumFees {
                    TextField("Max Fee (gwei)", text: $store.customEthereumMaxFeeGwei)
                        .keyboardType(.decimalPad)
                    TextField("Priority Fee (gwei)", text: $store.customEthereumPriorityFeeGwei)
                        .keyboardType(.decimalPad)

                    if let customEthereumFeeValidationError = store.customEthereumFeeValidationError {
                        Text(customEthereumFeeValidationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Custom EIP-1559 fees are applied to this send and preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Manual Nonce", isOn: $store.ethereumManualNonceEnabled)
                if store.ethereumManualNonceEnabled {
                    TextField("Nonce", text: $store.ethereumManualNonce)
                        .keyboardType(.numberPad)
                    if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
                        Text(customEthereumNonceValidationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if selectedCoin.chainName == "Ethereum" {
                    if store.isPreparingEthereumReplacementContext {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing replacement/cancel context...")
                                .font(.caption)
                        }
                    } else if store.hasPendingEthereumSendForSelectedWallet {
                        Button("Speed Up Pending Transaction") {
                            Task { await store.prepareEthereumSpeedUpContext() }
                        }
                        Button("Cancel Pending Transaction") {
                            Task { await store.prepareEthereumCancelContext() }
                        }
                    }

                    if let ethereumReplacementNonceStateMessage = store.ethereumReplacementNonceStateMessage {
                        Text(ethereumReplacementNonceStateMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.isPreparingEthereumSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading nonce and fee estimate...")
                            .font(.caption)
                    }
                } else if let ethereumSendPreview = store.ethereumSendPreview {
                    Text(localizedFormat("send.preview.nonceLabel", ethereumSendPreview.nonce))
                    Text(localizedFormat("Gas Limit: %lld", ethereumSendPreview.gasLimit))
                    Text(localizedFormat("Max Fee: %.2f gwei", ethereumSendPreview.maxFeePerGasGwei))
                    Text(localizedFormat("Priority Fee: %.2f gwei", ethereumSendPreview.maxPriorityFeePerGasGwei))
                    let feeSymbol = selectedCoin.chainName == "BNB Chain" ? "BNB" : (selectedCoin.chainName == "Ethereum Classic" ? "ETC" : (selectedCoin.chainName == "Avalanche" ? "AVAX" : (selectedCoin.chainName == "Hyperliquid" ? "HYPE" : "ETH")))
                    if let fiatFee = store.formattedFiatAmount(fromNative: ethereumSendPreview.estimatedNetworkFeeETH, symbol: feeSymbol) {
                        Text(localizedFormat("Estimated Network Fee: %.6f %@ (~%@)", ethereumSendPreview.estimatedNetworkFeeETH, feeSymbol, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.6f %@", ethereumSendPreview.estimatedNetworkFeeETH, feeSymbol))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(localizedFormat("Spectra signs and broadcasts supported %@ transfers. This preview is the live nonce and fee estimate for the transaction you are about to send.", selectedCoin.chainName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Tron" {
            Section("Tron Network") {
                if store.isPreparingTronSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Tron fee estimate...")
                            .font(.caption)
                    }
                } else if let tronSendPreview = store.tronSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: tronSendPreview.estimatedNetworkFeeTRX, symbol: "TRX") {
                        Text(localizedFormat("Estimated Network Fee: %.6f TRX (~%@)", tronSendPreview.estimatedNetworkFeeTRX, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.6f TRX", tronSendPreview.estimatedNetworkFeeTRX))
                            .font(.subheadline.weight(.semibold))
                    }
                    if selectedCoin.symbol == "USDT" {
                        Text("USDT on Tron uses TRX for network fees. Keep a TRX balance for gas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter an amount to load a Tron fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "XRP Ledger" {
            Section("XRP Ledger Network") {
                if store.isPreparingXRPSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading XRP fee estimate...")
                            .font(.caption)
                    }
                } else if let xrpSendPreview = store.xrpSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: xrpSendPreview.estimatedNetworkFeeXRP, symbol: "XRP") {
                        Text(localizedFormat("Estimated Network Fee: %.6f XRP (~%@)", xrpSendPreview.estimatedNetworkFeeXRP, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.6f XRP", xrpSendPreview.estimatedNetworkFeeXRP))
                            .font(.subheadline.weight(.semibold))
                    }
                    if xrpSendPreview.sequence > 0 {
                        Text(localizedFormat("Sequence: %lld", xrpSendPreview.sequence))
                    }
                    if xrpSendPreview.lastLedgerSequence > 0 {
                        Text(localizedFormat("Last Ledger Sequence: %lld", xrpSendPreview.lastLedgerSequence))
                    }
                } else {
                    Text("Enter an amount to load an XRP fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts XRP transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Cardano" {
            Section("Cardano Network") {
                if store.isPreparingCardanoSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Cardano fee estimate...")
                            .font(.caption)
                    }
                } else if let cardanoSendPreview = store.cardanoSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: cardanoSendPreview.estimatedNetworkFeeADA, symbol: "ADA") {
                        Text(localizedFormat("Estimated Network Fee: %.6f ADA (~%@)", cardanoSendPreview.estimatedNetworkFeeADA, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.6f ADA", cardanoSendPreview.estimatedNetworkFeeADA))
                            .font(.subheadline.weight(.semibold))
                    }
                    if cardanoSendPreview.ttlSlot > 0 {
                        Text(localizedFormat("TTL Slot: %lld", cardanoSendPreview.ttlSlot))
                    }
                } else {
                    Text("Enter an amount to load a Cardano fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts ADA transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "NEAR" {
            Section("NEAR Network") {
                if store.isPreparingNearSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading NEAR fee estimate...")
                            .font(.caption)
                    }
                } else if let nearSendPreview = store.nearSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: nearSendPreview.estimatedNetworkFeeNEAR, symbol: "NEAR") {
                        Text(localizedFormat("Estimated Network Fee: %.6f NEAR (~%@)", nearSendPreview.estimatedNetworkFeeNEAR, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.6f NEAR", nearSendPreview.estimatedNetworkFeeNEAR))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a NEAR fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts NEAR transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Polkadot" {
            Section("Polkadot Network") {
                if store.isPreparingPolkadotSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Polkadot fee estimate...")
                            .font(.caption)
                    }
                } else if let polkadotSendPreview = store.polkadotSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: polkadotSendPreview.estimatedNetworkFeeDOT, symbol: "DOT") {
                        Text(localizedFormat("Estimated Network Fee: %.6f DOT (~%@)", polkadotSendPreview.estimatedNetworkFeeDOT, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.6f DOT", polkadotSendPreview.estimatedNetworkFeeDOT))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a Polkadot fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Polkadot transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Stellar" {
            Section("Stellar Network") {
                if store.isPreparingStellarSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Stellar fee estimate...")
                            .font(.caption)
                    }
                } else if let stellarSendPreview = store.stellarSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: stellarSendPreview.estimatedNetworkFeeXLM, symbol: "XLM") {
                        Text(localizedFormat("Estimated Network Fee: %.7f XLM (~%@)", stellarSendPreview.estimatedNetworkFeeXLM, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.7f XLM", stellarSendPreview.estimatedNetworkFeeXLM))
                            .font(.subheadline.weight(.semibold))
                    }
                    if stellarSendPreview.sequence > 0 {
                        Text(localizedFormat("Sequence: %lld", stellarSendPreview.sequence))
                    }
                } else {
                    Text("Enter an amount to load a Stellar fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Stellar payments in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Internet Computer" {
            Section("Internet Computer Network") {
                if store.isPreparingICPSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading ICP fee estimate...")
                            .font(.caption)
                    }
                } else if let icpSendPreview = store.icpSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: icpSendPreview.estimatedNetworkFeeICP, symbol: "ICP") {
                        Text(localizedFormat("Estimated Network Fee: %.8f ICP (~%@)", icpSendPreview.estimatedNetworkFeeICP, fiatFee))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(localizedFormat("Estimated Network Fee: %.8f ICP", icpSendPreview.estimatedNetworkFeeICP))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load an ICP fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts ICP transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Dogecoin" {
            Section("Dogecoin Send") {
                Picker("Fee Priority", selection: $store.dogecoinFeePriority) {
                    Text("Economy").tag(DogecoinWalletEngine.FeePriority.economy)
                    Text("Normal").tag(DogecoinWalletEngine.FeePriority.normal)
                    Text("Priority").tag(DogecoinWalletEngine.FeePriority.priority)
                }
                .pickerStyle(.segmented)

                if store.isPreparingDogecoinSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading UTXOs and fee estimate...")
                            .font(.caption)
                    }
                } else if let dogecoinSendPreview = store.dogecoinSendPreview {
                    Text(localizedFormat("Spendable Balance: %.6f DOGE", dogecoinSendPreview.spendableBalanceDOGE))
                    if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFeeDOGE, symbol: "DOGE") {
                        Text(localizedFormat("Estimated Fee: %.6f DOGE (~%@)", dogecoinSendPreview.estimatedNetworkFeeDOGE, fiatFee))
                    } else {
                        Text(localizedFormat("Estimated Fee: %.6f DOGE", dogecoinSendPreview.estimatedNetworkFeeDOGE))
                    }
                    Text(localizedFormat("Fee Rate: %.4f DOGE/KB", dogecoinSendPreview.estimatedFeeRateDOGEPerKB))
                    Text(localizedFormat("Estimated Size: %lld bytes", dogecoinSendPreview.estimatedTransactionBytes))
                    Text(localizedFormat("Selected Inputs: %lld", dogecoinSendPreview.selectedInputCount))
                    Text(localizedFormat("Change Output: %@", dogecoinSendPreview.usesChangeOutput ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No (dust-safe fee absorption)", comment: "")))
                    Text(localizedFormat("Confirmation Preference: %@", confirmationPreferenceText(for: dogecoinSendPreview.feePriority)))
                    Text(localizedFormat("Max Sendable: %.6f DOGE", dogecoinSendPreview.maxSendableDOGE))
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Enter an amount to load a live UTXO and fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Dogecoin in-app. The preview shows estimated network fee and max sendable DOGE for this wallet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        let selectedCoin = store.selectedSendCoin

        ZStack {
            SpectraBackdrop()

            Form {
                primarySendSections
                networkSendSections(selectedCoin: selectedCoin)

                sendStatusSections
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Send")
            .task(id: sendPreviewTaskID) {
                await store.refreshSendPreview()
            }
            .sheet(isPresented: $isShowingQRScanner) {
                SendQRScannerSheet { payload in
                    applyScannedRecipientPayload(payload)
                }
            }
            .alert("QR Scanner", isPresented: qrScannerAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                if let qrScannerErrorMessage {
                    Text(verbatim: qrScannerErrorMessage)
                }
            }
            .onChange(of: store.sendHoldingKey) { _, _ in
                selectedAddressBookEntryID = ""
            }
            .onChange(of: isSendBusy) { _, isBusy in
                guard isBusy, let snapshot = sendLiveActivitySnapshot else { return }
                Task {
                    await SendTransactionLiveActivityManager.shared.startSending(
                        walletName: snapshot.walletName,
                        chainName: snapshot.chainName,
                        symbol: snapshot.symbol,
                        amountText: snapshot.amountText,
                        destinationAddress: snapshot.destinationAddress
                    )
                }
            }
            .onChange(of: store.lastSentTransaction?.id) { _, _ in
                guard let transaction = store.lastSentTransaction,
                      transaction.kind == .send else { return }
                Task {
                    let walletName = transaction.walletID.flatMap { walletID in
                        store.wallet(for: walletID.uuidString)?.name
                    } ?? "Wallet"
                    await SendTransactionLiveActivityManager.shared.complete(
                        walletName: walletName,
                        transactionHash: transaction.transactionHash,
                        chainName: transaction.chainName,
                        symbol: transaction.symbol,
                        amountText: String(format: "%.8f", transaction.amount),
                        destinationAddress: transaction.address
                    )
                }
            }
            .onChange(of: store.sendError) { _, sendError in
                guard !isSendBusy,
                      let sendError,
                      !sendError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task {
                    await SendTransactionLiveActivityManager.shared.fail(message: sendError)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            await store.submitSend()
                        }
                    }
                    .disabled(isSendBusy)
                }
            }
            .alert("High-Risk Send", isPresented: store.isShowingHighRiskSendConfirmationBinding) {
                Button("Cancel", role: .cancel) {
                    store.clearHighRiskSendConfirmation()
                }
                Button("Send Anyway", role: .destructive) {
                    Task {
                        await store.confirmHighRiskSendAndSubmit()
                    }
                }
            } message: {
                Text(store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                     ? "This transfer has elevated risk."
                     : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• "))
            }
        }
    }

    private var qrScannerAlertBinding: Binding<Bool> {
        Binding(
            get: { qrScannerErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    qrScannerErrorMessage = nil
                }
            }
        )
    }

    private func applyScannedRecipientPayload(_ payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            qrScannerErrorMessage = "The scanned QR code did not contain a usable address."
            return
        }

        let selectedChainName = store.availableSendCoins(for: store.sendWalletID)
            .first(where: { $0.holdingKey == store.sendHoldingKey })?
            .chainName

        guard let resolvedAddress = resolvedRecipientAddress(from: trimmedPayload, chainName: selectedChainName) else {
            qrScannerErrorMessage = "The scanned QR code does not contain a valid address for the selected asset."
            return
        }

        store.sendAddress = resolvedAddress
        qrScannerErrorMessage = nil
    }

    private func resolvedRecipientAddress(from payload: String, chainName: String?) -> String? {
        let candidates = qrAddressCandidates(from: payload)
        guard let chainName else {
            return candidates.first
        }

        for candidate in candidates {
            if isValidScannedAddress(candidate, for: chainName) {
                if chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid" {
                    return EthereumWalletEngine.normalizeAddress(candidate)
                }
                return candidate
            }
        }
        return nil
    }

    private func qrAddressCandidates(from payload: String) -> [String] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [String] = []

        func appendCandidate(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        appendCandidate(trimmed)

        let withoutQuery = trimmed.components(separatedBy: "?").first ?? trimmed
        appendCandidate(withoutQuery)

        if let colonIndex = withoutQuery.firstIndex(of: ":") {
            let suffix = String(withoutQuery[withoutQuery.index(after: colonIndex)...])
            appendCandidate(suffix)
        }

        if let components = URLComponents(string: trimmed) {
            if let host = components.host {
                appendCandidate(host + components.path)
            }
            if let firstPathComponent = components.path.split(separator: "/").first {
                appendCandidate(String(firstPathComponent))
            }
        }

        return candidates
    }

    private func isValidScannedAddress(_ address: String, for chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin":
            return AddressValidation.isValidBitcoinAddress(address, networkMode: store.bitcoinNetworkMode)
        case "Bitcoin Cash":
            return AddressValidation.isValidBitcoinCashAddress(address)
        case "Bitcoin SV":
            return AddressValidation.isValidBitcoinSVAddress(address)
        case "Litecoin":
            return AddressValidation.isValidLitecoinAddress(address)
        case "Dogecoin":
            return AddressValidation.isValidDogecoinAddress(address, allowTestnet: store.dogecoinAllowTestnet)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return AddressValidation.isValidEthereumAddress(address)
        case "Tron":
            return AddressValidation.isValidTronAddress(address)
        case "Solana":
            return AddressValidation.isValidSolanaAddress(address)
        case "Cardano":
            return AddressValidation.isValidCardanoAddress(address)
        case "XRP Ledger":
            return AddressValidation.isValidXRPAddress(address)
        case "Monero":
            return AddressValidation.isValidMoneroAddress(address)
        case "Sui":
            return AddressValidation.isValidSuiAddress(address)
        case "Aptos":
            return AddressValidation.isValidAptosAddress(address)
        case "TON":
            return AddressValidation.isValidTONAddress(address)
        case "Internet Computer":
            return AddressValidation.isValidICPAddress(address)
        case "NEAR":
            return AddressValidation.isValidNearAddress(address)
        default:
            return false
        }
    }

    /// Handles "confirmationPreferenceText" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private func confirmationPreferenceText(for priority: DogecoinWalletEngine.FeePriority) -> String {
        switch priority {
        case .economy:
            return "Economy (cost-optimized)"
        case .normal:
            return "Normal (balanced)"
        case .priority:
            return "Priority (faster confirmation bias)"
        }
    }
}

struct ReceiveView: View {
    @ObservedObject var store: WalletStore
    @State private var didCopyReceiveAddress: Bool = false
    @State private var isShowingReceiveQRShareSheet: Bool = false
    @State private var receiveQRExportMessage: String?
    @State private var receiveQRImageSaver: PhotoLibraryImageSaver?
    
    var body: some View {
        let resolvedReceiveAddress = store.receiveAddress()
        let canUseReceiveAddress = !resolvedReceiveAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ZStack {
            SpectraBackdrop()

            Form {
                Section("Wallet") {
                    Picker("Wallet", selection: store.receiveWalletIDBinding) {
                        ForEach(store.receiveEnabledWallets) { wallet in
                            Text(wallet.name).tag(wallet.id.uuidString)
                        }
                    }
                    .onChange(of: store.receiveWalletID) { _, _ in
                        store.syncReceiveAssetSelection()
                    }
                }
                receiveAddressSections
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Receive")
            .task(id: store.receiveWalletID) {
                await store.refreshReceiveAddress()
            }
            .sheet(isPresented: $isShowingReceiveQRShareSheet) {
                if let receiveQRImage = QRCodeRenderer.makeImage(from: store.receiveAddress()) {
                    ActivityItemSheet(activityItems: [receiveQRImage])
                }
            }
            .alert("QR Code Export", isPresented: Binding(
                get: { receiveQRExportMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        receiveQRExportMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    receiveQRExportMessage = nil
                }
            } message: {
                if let receiveQRExportMessage {
                    Text(verbatim: receiveQRExportMessage)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = resolvedReceiveAddress
                        didCopyReceiveAddress = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            didCopyReceiveAddress = false
                        }
                    } label: {
                        Label("Copy", systemImage: didCopyReceiveAddress ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(!canUseReceiveAddress || store.isResolvingReceiveAddress)
                }
            }
        }
    }

    @ViewBuilder
    private var receiveAddressSections: some View {
        let resolvedReceiveAddress = store.receiveAddress()
        let canUseReceiveAddress = !resolvedReceiveAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let receiveQRImage = QRCodeRenderer.makeImage(from: resolvedReceiveAddress)
        Section("QR Code") {
            VStack(alignment: .center, spacing: 12) {
                if canUseReceiveAddress {
                    QRCodeImage(address: resolvedReceiveAddress)
                        .frame(width: 184, height: 184)
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text("Scan to receive")
                        .font(.headline)
                    Text("Share this QR code or copy the address below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        guard let receiveQRImage else { return }
                        let saver = PhotoLibraryImageSaver { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    receiveQRExportMessage = "QR code saved to Photos."
                                case .failure(let error):
                                    receiveQRExportMessage = error.localizedDescription
                                }
                                receiveQRImageSaver = nil
                            }
                        }
                        receiveQRImageSaver = saver
                        saver.save(receiveQRImage)
                    } label: {
                        Label("Save QR Code", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .disabled(receiveQRImage == nil)
                } else {
                    ProgressView()
                    Text("Preparing receive address...")
                        .font(.headline)
                    Text("Spectra is resolving the current address for this wallet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }

        Section("Address") {
            Text(resolvedReceiveAddress)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if didCopyReceiveAddress {
                Label("Address copied to clipboard.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }

        if let receiveCoin = store.selectedReceiveCoin(for: store.receiveWalletID) {
            Section("Asset Details") {
                HStack(spacing: 12) {
                    CoinBadge(
                        assetIdentifier: receiveCoin.iconIdentifier,
                        fallbackText: receiveCoin.mark,
                        color: receiveCoin.color,
                        size: 34
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(receiveCoin.name)
                            .font(.headline)
                        Text(receiveCoin.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                LabeledContent("Network", value: receiveCoin.chainName)
                LabeledContent("Standard", value: receiveCoin.tokenStandard)
                let chainAssets = store.availableReceiveCoins(for: store.receiveWalletID)
                    .filter { $0.chainName == receiveCoin.chainName }
                if chainAssets.count > 1 {
                    let chainSymbols = Array(Set(chainAssets.map(\.symbol))).sorted().joined(separator: ", ")
                    LabeledContent("Also Receives") {
                        Text(chainSymbols)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let contractAddress = receiveCoin.contractAddress {
                    LabeledContent("Contract") {
                        Text(contractAddress)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct SendQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            QRCodeScannerView { payload in
                onScan(payload)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasResolvedPayload = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            resolve(item, from: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let firstItem = addedItems.first else { return }
            resolve(firstItem, from: dataScanner)
        }

        private func resolve(_ item: RecognizedItem, from dataScanner: DataScannerViewController) {
            guard !hasResolvedPayload else { return }
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty else {
                return
            }
            hasResolvedPayload = true
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
}

struct WalletCardView: View {
    @ObservedObject var store: WalletStore
    let wallet: ImportedWallet

    private var isWatchOnly: Bool {
        store.isWatchOnlyWallet(wallet)
    }

    private var isPrivateKeyWallet: Bool {
        store.isPrivateKeyWallet(wallet)
    }

    private var nonZeroAssetCount: Int {
        wallet.holdings.filter { $0.amount > 0 }.count
    }

    private var walletBadge: (assetIdentifier: String?, mark: String, color: Color) {
        Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, "W", .mint)
    }

    private var watchOnlyBadge: some View {
        Image(systemName: "eye")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CoinBadge(assetIdentifier: walletBadge.assetIdentifier, fallbackText: walletBadge.mark, color: walletBadge.color, size: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isWatchOnly {
                            watchOnlyBadge
                        }
                        Text(wallet.name)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                    }
                    Text(wallet.selectedChain)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: wallet)))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .spectraNumericTextLayout()
                    Text(localizedFormat("%lld assets", nonZeroAssetCount))
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.68))
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}

struct QRCodeRenderer {
    static func makeImage(from string: String, scale: CGFloat = 12) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

struct ActivityItemSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class PhotoLibraryImageSaver: NSObject {
    private let completion: (Result<Void, Error>) -> Void

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc
    private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }
}

struct DonationQRCodeView: View {
    let donation: DonationDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop()

                VStack(spacing: 24) {
                    CoinBadge(
                        assetIdentifier: donation.assetIdentifier,
                        fallbackText: donation.mark,
                        color: donation.color,
                        size: 54
                    )

                    Text(localizedWalletFlowString("Scan to Donate"))
                        .font(.title2.bold())
                        .foregroundStyle(Color.primary)

                    Text(donation.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary.opacity(0.76))

                    QRCodeImage(address: donation.address)
                        .frame(width: 220, height: 220)
                        .padding(18)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    Text(donation.address)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 24)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(localizedWalletFlowString("QR Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizedWalletFlowString("Done")) {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

struct QRCodeImage: View {
    let address: String

    var body: some View {
        Group {
            if let image = qrUIImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .foregroundStyle(.black)
            }
        }
    }

    private var qrUIImage: UIImage? {
        QRCodeRenderer.makeImage(from: address)
    }
}

struct WalletDetailView: View {
    @ObservedObject var store: WalletStore
    let wallet: ImportedWallet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSeedPhrasePasswordPrompt: Bool = false
    @State private var isShowingSeedPhraseSheet: Bool = false
    @State private var seedPhrasePasswordInput: String = ""
    @State private var revealedSeedPhrase: String = ""
    @State private var seedPhraseErrorMessage: String?
    @State private var isRevealingSeedPhrase: Bool = false
    @State private var didCopyWalletAddress: Bool = false
    @State private var isShowingDeleteWalletAlert: Bool = false

    private var isWatchOnly: Bool {
        store.isWatchOnlyWallet(displayedWallet)
    }

    private var isPrivateKeyWallet: Bool {
        store.isPrivateKeyWallet(displayedWallet)
    }

    private var requiresSeedPhrasePassword: Bool {
        store.walletRequiresSeedPhrasePassword(displayedWallet.id)
    }

    private var displayedWallet: ImportedWallet {
        store.wallets.first(where: { $0.id == wallet.id }) ?? wallet
    }

    private var firstActivityDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        guard let firstDate = store.transactions
            .filter({ $0.walletID == wallet.id })
            .map(\.createdAt)
            .min() else {
            return NSLocalizedString("No activity yet", comment: "")
        }
        return formatter.string(from: firstDate)
    }

    private var nonZeroAssetCount: Int {
        displayedWallet.holdings.filter { $0.amount > 0 }.count
    }

    private var walletAddress: String? {
        [
            displayedWallet.bitcoinAddress,
            displayedWallet.bitcoinCashAddress,
            displayedWallet.litecoinAddress,
            displayedWallet.dogecoinAddress,
            displayedWallet.ethereumAddress,
            displayedWallet.tronAddress,
            displayedWallet.solanaAddress,
            displayedWallet.xrpAddress,
            displayedWallet.moneroAddress,
            displayedWallet.cardanoAddress,
            displayedWallet.suiAddress,
            displayedWallet.aptosAddress,
            displayedWallet.tonAddress,
            displayedWallet.nearAddress,
            displayedWallet.polkadotAddress,
            displayedWallet.stellarAddress,
        ]
        .compactMap { $0 }
        .first
    }

    private var derivationPathsText: String? {
        guard !isWatchOnly, !isPrivateKeyWallet else { return nil }

        let chainMappings: [(String, SeedDerivationChain)] = [
            ("Bitcoin", .bitcoin),
            ("Bitcoin Cash", .bitcoinCash),
            ("Bitcoin SV", .bitcoinSV),
            ("Litecoin", .litecoin),
            ("Dogecoin", .dogecoin),
            ("Ethereum", .ethereum),
            ("Ethereum Classic", .ethereumClassic),
            ("Arbitrum", .arbitrum),
            ("Optimism", .optimism),
            ("BNB Chain", .ethereum),
            ("Avalanche", .avalanche),
            ("Hyperliquid", .hyperliquid),
            ("Tron", .tron),
            ("Solana", .solana),
            ("Cardano", .cardano),
            ("XRP Ledger", .xrp),
            ("Sui", .sui),
            ("Aptos", .aptos),
            ("TON", .ton),
            ("Internet Computer", .internetComputer),
            ("NEAR", .near),
            ("Polkadot", .polkadot),
            ("Stellar", .stellar),
        ]

        guard let derivationChain = chainMappings.first(where: { $0.0 == displayedWallet.selectedChain })?.1 else {
            return nil
        }
        return localizedFormat("wallet.detail.chainPath", displayedWallet.selectedChain, displayedWallet.seedDerivationPaths.path(for: derivationChain))
    }

    private var walletBadge: (assetIdentifier: String?, mark: String, color: Color) {
        Coin.nativeChainBadge(chainName: displayedWallet.selectedChain) ?? (nil, "W", .mint)
    }

    private var visibleHoldings: [Coin] {
        displayedWallet.holdings
            .filter { $0.amount > 0 }
            .sorted {
                let lhsValue = store.currentValueIfAvailable(for: $0) ?? -1
                let rhsValue = store.currentValueIfAvailable(for: $1) ?? -1
                if abs(lhsValue - rhsValue) > 0.000001 {
                    return lhsValue > rhsValue
                }
                return $0.symbol.localizedCaseInsensitiveCompare($1.symbol) == .orderedAscending
            }
    }

    private var watchOnlyBadge: some View {
        Label(NSLocalizedString("Watching", comment: ""), systemImage: "eye")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    private var deleteWalletMessage: String {
        if isWatchOnly {
            return NSLocalizedString("You can't recover this wallet after deletion until you still have this address.", comment: "")
        }
        if isPrivateKeyWallet {
            return NSLocalizedString("Please keep this private key because you can't recover this wallet after deletion.", comment: "")
        }
        return NSLocalizedString("Please take note of your seed phrase because you can't recover this wallet after deletion.", comment: "")
    }

    private func clearSeedRevealState() {
        isShowingSeedPhrasePasswordPrompt = false
        isShowingSeedPhraseSheet = false
        seedPhrasePasswordInput = ""
        revealedSeedPhrase = ""
        seedPhraseErrorMessage = nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    CoinBadge(
                        assetIdentifier: walletBadge.assetIdentifier,
                        fallbackText: walletBadge.mark,
                        color: walletBadge.color,
                        size: 46
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(displayedWallet.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.primary)

                            Spacer(minLength: 0)

                            if isWatchOnly {
                                watchOnlyBadge
                            }
                        }
                        Text(displayedWallet.selectedChain)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .spectraBubbleFill()
                .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Mode", value: isWatchOnly ? "Watch Addresses" : (isPrivateKeyWallet ? "Private Key" : "Seed-Based"))
                    if let derivationPathsText {
                        detailRow(label: "Derivation Paths", value: derivationPathsText)
                    }
                    detailRow(label: "Current Value", value: store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: displayedWallet)))
                    detailRow(label: "Asset Count", value: "\(nonZeroAssetCount)")
                    detailRow(label: "First Activity", value: firstActivityDateText)
                    detailRow(label: "Wallet ID", value: displayedWallet.id.uuidString)
                }
                .padding(16)
                .spectraBubbleFill()
                .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Holdings")
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(visibleHoldings.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.68))
                    }

                    if visibleHoldings.isEmpty {
                        Text("No assets loaded for this wallet yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.72))
                    } else {
                        ForEach(visibleHoldings) { holding in
                            HStack(spacing: 12) {
                                CoinBadge(
                                    assetIdentifier: holding.iconIdentifier,
                                    fallbackText: holding.mark,
                                    color: holding.color,
                                    size: 34
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(holding.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primary)
                                    Text("\(holding.symbol) • \(holding.tokenStandard)")
                                        .font(.caption)
                                        .foregroundStyle(Color.primary.opacity(0.62))
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(store.formattedAssetAmount(holding.amount, symbol: holding.symbol, chainName: holding.chainName))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primary)
                                        .spectraNumericTextLayout()
                                    Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentValueIfAvailable(for: holding)))
                                        .font(.caption)
                                        .foregroundStyle(Color.primary.opacity(0.68))
                                        .spectraNumericTextLayout()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(16)
                .spectraBubbleFill()
                .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))

                if let walletAddress {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Wallet Address")
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = walletAddress
                                didCopyWalletAddress = true
                            } label: {
                                Label(didCopyWalletAddress ? "Copied" : "Copy", systemImage: didCopyWalletAddress ? "checkmark" : "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.primary)
                        }

                        Text(walletAddress)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .spectraBubbleFill()
                    .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.beginEditingWallet(wallet)
                        }
                    } label: {
                        Label("Edit Wallet", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    if !isWatchOnly && !isPrivateKeyWallet {
                        Button {
                            if requiresSeedPhrasePassword {
                                seedPhrasePasswordInput = ""
                                isShowingSeedPhrasePasswordPrompt = true
                            } else {
                                Task {
                                    await revealSeedPhrase()
                                }
                            }
                        } label: {
                            Label(
                                isRevealingSeedPhrase
                                    ? "Checking Face ID..."
                                    : (requiresSeedPhrasePassword ? "Show Seed Phrase (Password)" : "Show Seed Phrase"),
                                systemImage: requiresSeedPhrasePassword ? "lock.shield" : "faceid"
                            )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glass)
                        .disabled(isRevealingSeedPhrase || !store.canRevealSeedPhrase(for: wallet.id))
                    }

                    Button(role: .destructive) {
                        isShowingDeleteWalletAlert = true
                    } label: {
                        Label("Delete Wallet", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(SpectraBackdrop())
        .navigationTitle("Wallet Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { store.isShowingWalletImporter && store.editingWalletID == wallet.id },
            set: { isPresented in
                if !isPresented {
                    store.isShowingWalletImporter = false
                }
            }
        )) {
            SetupView(store: store, draft: store.importDraft)
        }
        .alert("Delete Wallet?", isPresented: $isShowingDeleteWalletAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    store.confirmDeleteWallet(wallet)
                    await store.deletePendingWallet()
                }
            }
            Button("Cancel", role: .cancel) {
                isShowingDeleteWalletAlert = false
            }
        } message: {
            Text(deleteWalletMessage)
        }
        .alert("Cannot Reveal Seed Phrase", isPresented: Binding(
            get: { seedPhraseErrorMessage != nil },
            set: { isPresented in
                if !isPresented { seedPhraseErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(seedPhraseErrorMessage ?? "Unknown error")
        }
        .onChange(of: wallet.id) { _, _ in
            didCopyWalletAddress = false
        }
        .onChange(of: store.wallets.contains(where: { $0.id == wallet.id })) { _, walletStillExists in
            guard !walletStillExists else { return }
            isShowingDeleteWalletAlert = false
            clearSeedRevealState()
            dismiss()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            clearSeedRevealState()
        }
        .sheet(isPresented: $isShowingSeedPhrasePasswordPrompt, onDismiss: {
            seedPhrasePasswordInput = ""
        }) {
            NavigationStack {
                ZStack {
                    SpectraBackdrop()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("This wallet has an optional seed phrase password. Enter it after Face ID to reveal the recovery phrase.")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.76))

                        SecureField("Wallet Password", text: $seedPhrasePasswordInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .privacySensitive()
                            .padding(14)
                            .spectraInputFieldStyle()
                            .foregroundStyle(Color.primary)

                        Button {
                            isShowingSeedPhrasePasswordPrompt = false
                            Task {
                                await revealSeedPhrase(password: seedPhrasePasswordInput)
                            }
                        } label: {
                            Text("Reveal Seed Phrase")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(seedPhrasePasswordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()
                    }
                    .padding(20)
                }
                .navigationTitle("Wallet Password")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            isShowingSeedPhrasePasswordPrompt = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSeedPhraseSheet, onDismiss: {
            revealedSeedPhrase = ""
        }) {
            NavigationStack {
                ZStack {
                    SpectraBackdrop()

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Write this down and keep it offline. Anyone with this phrase can control your funds.")
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.76))

                            Text(revealedSeedPhrase)
                                .font(.body.monospaced())
                                .foregroundStyle(Color.primary)
                                .privacySensitive()
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .spectraInputFieldStyle(cornerRadius: 16)
                        }
                        .padding(16)
                        .spectraBubbleFill()
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
                        .padding(20)
                    }
                }
                .navigationTitle("Seed Phrase")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingSeedPhraseSheet = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    /// Handles "detailRow" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString(label, comment: ""))
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.65))
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Handles "revealSeedPhrase" for this module.
    /// Keeps behavior deterministic and aligned with app state expectations.
    private func revealSeedPhrase(password: String? = nil) async {
        guard !isRevealingSeedPhrase else { return }
        isRevealingSeedPhrase = true
        defer { isRevealingSeedPhrase = false }

        do {
            let phrase = try await store.revealSeedPhrase(for: wallet, password: password)
            revealedSeedPhrase = phrase
            seedPhrasePasswordInput = ""
            isShowingSeedPhraseSheet = true
        } catch {
            seedPhraseErrorMessage = error.localizedDescription
        }
    }
}

private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}

private struct SeedPathSlotEditor: View {
    let title: String
    @Binding var path: String
    let defaultPath: String

    private var segments: [DerivationPathSegment] {
        DerivationPathParser.parse(path) ?? DerivationPathParser.parse(defaultPath) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizedWalletFlowString(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Button("Reset") {
                    path = defaultPath
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("m")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.72))

                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        HStack(spacing: 4) {
                            Text(verbatim: "/")
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.primary.opacity(0.52))
                            TextField(
                                "0",
                                text: Binding(
                                    get: { String(segment.value) },
                                    set: { updateSegment(at: index, value: $0) }
                                )
                            )
                            .keyboardType(.numberPad)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .spectraInputFieldStyle(cornerRadius: 12)

                            if segment.isHardened {
                                Text(verbatim: "'")
                                    .font(.caption.monospaced().weight(.bold))
                                    .foregroundStyle(Color.primary.opacity(0.72))
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateSegment(at index: Int, value: String) {
        guard var resolvedSegments = DerivationPathParser.parse(path) ?? DerivationPathParser.parse(defaultPath),
              resolvedSegments.indices.contains(index),
              let numericValue = UInt32(value.filter(\.isNumber)) else { return }
        resolvedSegments[index].value = numericValue
        path = DerivationPathParser.string(from: resolvedSegments)
    }
}

struct AssetRowView: View {
    @ObservedObject var store: WalletStore
    let coin: Coin
    
    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: coin.iconIdentifier,
                fallbackText: coin.mark,
                color: coin.color,
                size: 46
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(coin.name)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(store.formattedAssetAmount(coin.amount, symbol: coin.symbol, chainName: coin.chainName))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .spectraNumericTextLayout()
                Text(localizedFormat("wallet.detail.onChainLowercase", coin.chainName))
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.6))
                Text(coin.tokenStandard)
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.55))
                if let contractAddress = coin.contractAddress {
                    Text(contractAddress)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentValueIfAvailable(for: coin)))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .spectraNumericTextLayout()
                Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentPriceIfAvailable(for: coin)))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .spectraNumericTextLayout()
            }
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}
