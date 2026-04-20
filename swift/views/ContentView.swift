import SwiftUI
private struct SpectraInputFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let borderColor: Color?
    private var resolvedBackground: Color { colorScheme == .light ? Color.black.opacity(0.045) : Color.white.opacity(0.08) }
    private var resolvedBorderColor: Color {
        borderColor ?? (colorScheme == .light ? Color.black.opacity(0.18) : Color.white.opacity(0.14))
    }
    func body(content: Content) -> some View {
        content.background(resolvedBackground).clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)).overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(resolvedBorderColor, lineWidth: 1)
        )
    }
}
extension View {
    func spectraBubbleFill(alignment: Alignment = .leading) -> some View { frame(maxWidth: .infinity, alignment: alignment) }
    func spectraInputFieldStyle(cornerRadius: CGFloat = 18, borderColor: Color? = nil) -> some View {
        modifier(SpectraInputFieldChrome(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
@ViewBuilder
func spectraDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        if let title { Text(AppLocalization.string(title)).font(.headline.weight(.semibold)).foregroundStyle(Color.primary) }
        VStack(alignment: .leading, spacing: 12) { content() }
    }.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
}
struct ContentView: View {
    @State private var store: AppState
    @Environment(\.scenePhase) private var scenePhase
    @MainActor
    init() {
        _store = State(wrappedValue: AppState())
    }
    @MainActor
    init(store: AppState) {
        _store = State(wrappedValue: store)
    }
    private func refreshAppStateForActivePhase() {
        store.setAppIsActive(true)
        Task {
            await store.refreshForForegroundIfNeeded()
        }
    }
    var body: some View {
        ZStack {
            MainTabView(store: store).blur(radius: store.isAppLocked ? 8 : 0).disabled(store.isAppLocked)
            if store.isAppLocked {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill").font(.system(size: 36, weight: .semibold)).foregroundStyle(.secondary)
                    Text(AppLocalization.string("content.locked.title")).font(.headline)
                    Text(AppLocalization.string("content.locked.subtitle")).font(.subheadline).foregroundStyle(.secondary)
                    if let appLockError = store.appLockError { Text(appLockError).font(.caption).foregroundStyle(.red) }
                    Button {
                        Task {
                            await store.unlockApp()
                        }
                    } label: {
                        Label(AppLocalization.string("content.locked.unlock"), systemImage: "faceid").frame(maxWidth: 220)
                    }.buttonStyle(.borderedProminent)
                }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(28)
            }
        }.onAppear {
            store.setAppIsActive(scenePhase == .active)
            if scenePhase == .active { refreshAppStateForActivePhase() }
        }.environment(\.locale, AppLocalization.locale).onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: refreshAppStateForActivePhase()
            case .background: store.setAppIsActive(false)
            case .inactive: store.setAppIsActive(false)
            default: break
            }
        }
    }
}
#Preview {
    ContentView()
}
@main
struct SpectraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
