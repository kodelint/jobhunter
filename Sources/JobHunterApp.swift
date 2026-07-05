import SwiftUI

@main
struct JobHunterApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(store)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Now") { Task { await store.scanNow() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.scan.running)
            }
        }

        MenuBarExtra("JobHunter", systemImage: "scope") {
            MenuBarView().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
