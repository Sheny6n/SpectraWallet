import SwiftUI
struct AddWalletEntryView: View {
    let store: AppState
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    actionCard(
                        title: AppLocalization.string("Create New Wallet"),
                        subtitle: AppLocalization.string("Generate a new seed phrase and set up your wallet."), icon: "plus.circle.fill",
                        tint: Color.green
                    ) {
                        store.beginWalletCreation()
                    }
                    actionCard(
                        title: AppLocalization.string("Import Wallet"),
                        subtitle: AppLocalization.string("Use an existing seed phrase or private key."), icon: "arrow.down.circle.fill",
                        tint: Color.blue
                    ) {
                        store.beginWalletImport()
                    }
                    actionCard(
                        title: AppLocalization.string("Watch Addresses"),
                        subtitle: AppLocalization.string("Track public addresses without adding private keys."), icon: "eye.circle.fill",
                        tint: Color.orange
                    ) {
                        store.beginWatchAddressesImport()
                    }
                }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }
        }.navigationTitle(AppLocalization.string("Add Wallet")).navigationBarTitleDisplayMode(.inline).navigationDestination(
            isPresented: Binding(
                get: { store.isShowingWalletImporter && store.editingWalletID == nil },
                set: { isPresented in
                    if !isPresented { store.isShowingWalletImporter = false }
                }
            )
        ) {
            SetupView(store: store, draft: store.importDraft)
        }
    }
    private func actionCard(
        title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(tint).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.primary.opacity(0.72)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.primary.opacity(0.38)).padding(
                    .top, 4)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 22))
    }
}
