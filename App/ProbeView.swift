import SwiftUI
import HP15CFlasherCore

struct ProbeView: View {
    @EnvironmentObject private var store: FlasherStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hold ERASE, press RESET, then release ERASE.")
                        .fixedSize(horizontal: false, vertical: true)
                    ProgrammingModeDiagram()
                    if let port = store.probePortName {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Programming port")
                                .font(.headline)
                            Text("\(port) · USB CDC (SAM-BA)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    connectionStatus
                    if let error = store.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            footer
            Text("\(Bundle.main.appVersionLabel) · Mach II Labs · offline · no telemetry · free forever")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("15CE Flasher")
                    .font(.largeTitle.weight(.semibold))
                Text("Connection Probe — test cable detection only")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("PROBE")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.18), in: Capsule())
        }
    }

    private var connectionStatus: some View {
        let well = colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.18)
        let ink = Color(white: colorScheme == .dark ? 0.86 : 0.92)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Status  \(store.status)")
            Text("Port    \(store.portPath ?? "—")")
            Text("SAM-BA  \(store.sambaVersion ?? "—")")
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .foregroundStyle(ink)
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Button("Back to welcome", action: store.returnToWelcome)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
