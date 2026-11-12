import SwiftUI

@main
struct ObjectifPrixApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = Store.shared
    @StateObject private var sync = SyncService.shared
    @StateObject private var settings = Settings.shared

    init() {
        BackgroundRefresh.register()
        // Au premier lancement, la permission des notifications est demandée pendant le tutoriel.
        Notifier.setup(askPermission: UserDefaults.standard.bool(forKey: "set.onboarded"))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if settings.tutorialPresented {
                    TutorialView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environmentObject(store)
            .environmentObject(sync)
            .environmentObject(settings)
            .preferredColorScheme(Theme.scheme)
            .environment(\.dynamicTypeSize, settings.typeSize)
            .onAppear {
                if !settings.onboarded { settings.tutorialPresented = true }
            }
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .active {
                Task {
                    await sync.syncNow()        // d'abord récupérer les changements de l'autre appareil
                    await store.refreshDue()    // puis relever les prix
                }
            } else if newPhase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }
}
