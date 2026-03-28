import SwiftUI

struct EndpointCatalogSettingsView: View {
    @ObservedObject var store: WalletStore
    @State private var newBitcoinEndpoint: String = ""
    private let copy = EndpointsContentCopy.current

    private var endpointSections: [AppChainDescriptor] {
        ChainBackendRegistry.endpointCatalogChains
    }

    private var parsedBitcoinCustomEndpoints: [String] {
        store.bitcoinEsploraEndpoints
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var bitcoinEndpoints: [String] {
        BitcoinWalletEngine.endpointCatalog(for: store.bitcoinNetworkMode, custom: parsedBitcoinCustomEndpoints)
    }

    private var ethereumEndpoints: [String] {
        var endpoints: [String] = []
        let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            endpoints.append(custom)
        }
        for endpoint in EVMChainContext.ethereum.defaultRPCEndpoints where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        for endpoint in ChainBackendRegistry.EVMExplorerRegistry.supplementalEndpointCatalogEntries(for: ChainBackendRegistry.ethereumChainName) {
            if !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    private var ethereumClassicEndpoints: [String] {
        EVMChainContext.ethereumClassic.defaultRPCEndpoints
    }

    private var arbitrumEndpoints: [String] {
        EVMChainContext.arbitrum.defaultRPCEndpoints
    }

    private var optimismEndpoints: [String] {
        EVMChainContext.optimism.defaultRPCEndpoints
    }

    private var bnbEndpoints: [String] {
        var endpoints = EVMChainContext.bnb.defaultRPCEndpoints
        for endpoint in ChainBackendRegistry.EVMExplorerRegistry.supplementalEndpointCatalogEntries(for: ChainBackendRegistry.bnbChainName) {
            if !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    private var avalancheEndpoints: [String] {
        EVMChainContext.avalanche.defaultRPCEndpoints
    }

    private var hyperliquidEndpoints: [String] {
        EVMChainContext.hyperliquid.defaultRPCEndpoints
    }

    private var dogecoinEndpoints: [String] {
        DogecoinBalanceService.endpointCatalog()
    }

    private var moneroEndpoints: [String] {
        let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return [trimmed]
        }
        return [MoneroBalanceService.defaultPublicBackend.baseURL]
    }

    private func addBitcoinEndpoint() {
        let trimmed = newBitcoinEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var endpoints = parsedBitcoinCustomEndpoints
        guard !endpoints.contains(trimmed) else {
            newBitcoinEndpoint = ""
            return
        }
        endpoints.append(trimmed)
        store.bitcoinEsploraEndpoints = endpoints.joined(separator: "\n")
        newBitcoinEndpoint = ""
    }

    @ViewBuilder
    private func endpointRows(_ endpoints: [String]) -> some View {
        ForEach(endpoints, id: \.self) { endpoint in
            Text(endpoint)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func endpointSection(_ descriptor: AppChainDescriptor) -> some View {
        Section(descriptor.chainName) {
            switch descriptor.id {
            case .bitcoin:
                endpointRows(bitcoinEndpoints)

                TextField(copy.addEsploraEndpointPlaceholder, text: $newBitcoinEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button(copy.addEndpointButtonTitle) {
                    addBitcoinEndpoint()
                }

                if !parsedBitcoinCustomEndpoints.isEmpty {
                    Button(copy.clearCustomBitcoinEndpointsTitle, role: .destructive) {
                        store.bitcoinEsploraEndpoints = ""
                    }
                }

                if let error = store.bitcoinEsploraEndpointsValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            case .bitcoinCash:
                endpointRows(BitcoinCashBalanceService.diagnosticsChecks().map(\.endpoint))
            case .litecoin:
                endpointRows(LitecoinBalanceService.diagnosticsChecks().map(\.endpoint))
            case .dogecoin:
                endpointRows(dogecoinEndpoints)
            case .ethereum:
                endpointRows(ethereumEndpoints)

                TextField(copy.customEthereumRPCURLPlaceholder, text: $store.ethereumRPCEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let error = store.ethereumRPCEndpointValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            case .ethereumClassic:
                endpointRows(ethereumClassicEndpoints)
                readOnlyFootnote
            case .arbitrum:
                endpointRows(arbitrumEndpoints)
                readOnlyFootnote
            case .optimism:
                endpointRows(optimismEndpoints)
                readOnlyFootnote
            case .bnb:
                endpointRows(bnbEndpoints)
                readOnlyFootnote
            case .avalanche:
                endpointRows(avalancheEndpoints)
                readOnlyFootnote
            case .hyperliquid:
                endpointRows(hyperliquidEndpoints)
                readOnlyFootnote
            case .tron:
                endpointRows(TronBalanceService.diagnosticsChecks().map(\.endpoint))
            case .solana:
                endpointRows(SolanaBalanceService.diagnosticsChecks().map(\.endpoint))
            case .cardano:
                endpointRows(CardanoBalanceService.diagnosticsChecks().map(\.endpoint))
            case .xrp:
                endpointRows(XRPBalanceService.diagnosticsChecks().map(\.endpoint))
            case .stellar:
                endpointRows(StellarBalanceService.diagnosticsChecks().map(\.endpoint))
            case .monero:
                endpointRows(moneroEndpoints)

                TextField(copy.customMoneroBackendURLPlaceholder, text: $store.moneroBackendBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let error = store.moneroBackendBaseURLValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            case .sui:
                endpointRows(SuiBalanceService.diagnosticsChecks().map(\.endpoint))
            case .aptos:
                endpointRows(AptosBalanceService.diagnosticsChecks().map(\.endpoint))
            case .ton:
                endpointRows(TONBalanceService.diagnosticsChecks().map(\.endpoint))
            case .icp:
                endpointRows(ICPBalanceService.diagnosticsChecks().map(\.endpoint))
            case .near:
                endpointRows(NearBalanceService.diagnosticsChecks().map(\.endpoint))
            case .polkadot:
                endpointRows(PolkadotBalanceService.diagnosticsChecks().map(\.endpoint))
            case .bitcoinSV:
                EmptyView()
            }
        }
    }

    private var readOnlyFootnote: some View {
        Text(copy.readOnlyFootnote)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        Form {
            Section {
                Text(copy.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(endpointSections) { descriptor in
                endpointSection(descriptor)
            }
        }
        .navigationTitle(copy.navigationTitle)
    }
}
