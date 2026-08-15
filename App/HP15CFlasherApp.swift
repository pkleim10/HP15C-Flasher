import AppKit
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
            DebugCommands(store: store)
        }
        #endif

        #if DEBUG
        Window("Pogo Wing Editor", id: "pogo-wing-editor") {
            PogoWingEditorView()
        }
        .windowResizability(.contentSize)
        #endif
    }
}

#if DEBUG
private struct DebugCommands: Commands {
    @ObservedObject var store: FlasherStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Debug") {
            Toggle(
                "Use Simulated Calculator",
                isOn: Binding(
                    get: { store.usingSimulator },
                    set: { store.setUsingSimulator($0) }
                )
            )
            Button("Pogo Wing Editor") {
                openWindow(id: "pogo-wing-editor")
            }
            Button("Open HTML Wing Tracer…") {
                let root = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let html = root.appendingPathComponent("scripts/trace-pogo-wings.html")
                NSWorkspace.shared.open(html)
            }
        }
    }
}
#endif
