import SwiftUI

@main
struct HP15CFlasherApp: App {
    @StateObject private var store = FlasherStore()

    var body: some Scene {
        Window("HP 15C Flasher", id: "wizard") {
            ContentView()
                .environmentObject(store)
                .onAppear { store.start() }
                .onDisappear { store.stop() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 760)
        #if DEBUG
        .commands {
            CommandMenu("Debug") {
                Toggle(
                    "Use Simulated Calculator",
                    isOn: Binding(
                        get: { store.usingSimulator },
                        set: { store.setUsingSimulator($0) }
                    )
                )
            }
        }
        #endif
    }
}
