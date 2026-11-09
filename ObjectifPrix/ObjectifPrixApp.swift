import SwiftUI

@main
struct ObjectifPrixApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = Store.shared
    @StateObject private var sync = SyncService.shared

    init() {
        BackgroundRefresh.register()
        Notifier.setup()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(sync)
                .preferredColorScheme(.dark)
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
