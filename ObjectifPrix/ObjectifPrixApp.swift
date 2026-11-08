import SwiftUI

@main
struct ObjectifPrixApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = Store.shared

    init() {
        BackgroundRefresh.register()
        Notifier.setup()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .active {
                Task { await store.refreshDue() }
            } else if newPhase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }
}
