import SwiftUI
import HP15CFlasherCore

struct ContentView: View {
    @EnvironmentObject private var store: FlasherStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        wizardColumn
            .padding(24)
            .frame(minWidth: 640, idealWidth: 680, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .confirmationDialog(
            "Flash the calculator?",
            isPresented: $store.confirmFlash,
            titleVisibility: .visible
        ) {
            Button("Flash at 0x04000", role: .destructive, action: store.flash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("User memory will be wiped. The bootloader at 0x0000–0x3FFF is not overwritten.")
        }
        .confirmationDialog(
            "Skip backup?",
            isPresented: $store.confirmSkipBackup,
            titleVisibility: .visible
        ) {
            Button("Skip backup", role: .destructive, action: store.skipBackup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If the new firmware misbehaves, you will not have a copy of what is on the calculator now.")
        }
    }

    private var wizardColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            #if DEBUG
            demoControls
            #endif
            stepChrome
            stepBody
            stepChecklist
            if store.wizard.isBusy, let progress = store.progress {
                labeledProgress(
                    store.progressCaption ?? "Working",
                    value: progress,
                    tint: store.progressIsVerify ? .green : (store.progressCaption == "Flashing" ? .blue : Color.accentColor),
                    identity: store.progressBarID
                )
            }
            if let banner = store.stepBanner {
                wrappingText(banner.text)
                    .foregroundStyle(banner.caution ? Color.orange : Color.green)
                    .textSelection(.enabled)
            }
            if let error = store.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            navigation
            Text("\(Bundle.main.appVersionLabel) · Mach II Labs · offline · no telemetry · firmware files stay on this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HP 15C Flasher")
                .font(.largeTitle.weight(.semibold))
            Text("Native SAM-BA programmer for the Collector’s Edition")
                .foregroundStyle(.secondary)
        }
    }

    #if DEBUG
    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Use simulated calculator",
                isOn: Binding(
                    get: { store.usingSimulator },
                    set: { store.setUsingSimulator($0) }
                )
            )
            if store.usingSimulator {
                Text("DEMO — no hardware. Continue unlocks once the fake ATSAM4LC2C connects.")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    #endif

    private var stepChrome: some View {
        HStack {
            Text("Step \(store.wizard.step.number) of \(WizardStep.count)")
                .font(.headline)
            Text(store.wizard.step.title)
                .foregroundStyle(.secondary)
            Spacer()
            if store.identity != nil {
                Text(store.chipLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                stepInstruction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stepInstruction: some View {
        switch store.wizard.step {
        case .cable:
            CableDiagram()
            wrappingText("Open the calculator's battery door and insert the POGO cable. The connector is keyed; the POGO can only be inserted one way. Make sure the plug snaps securely into place.")
            wrappingText("Plug the other end of the cable (USB-A or USB-C) into this Mac.")
            warningBox("Use the POGO cable only on the HP 15C Collector’s Edition. This app will not flash other calculators. Do not use the cable on an HP 15C Limited Edition, a pre-2015 12C, an HP 20b, or an HP 30b, as it could permanently damage your calculator.")
        case .programmingMode:
            ProgrammingModeDiagram()
            wrappingText("On the cable's switch box, hold ERASE, press RESET, then release ERASE. The display stays off. The calculator's ON button is ignored in this state.")
            connectionStatus
            wrappingText("Once your calculator is recognized, continue with the next step.")
                .foregroundStyle(.secondary)
        case .backup:
            wrappingText("Save a copy of the currently installed firmware in case you want to restore it later.")
            HStack {
                Button("Save Backup…", action: store.backup)
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canBackup)
                Button("Skip") { store.confirmSkipBackup = true }
                    .disabled(store.wizard.isBusy)
            }
        case .firmware:
            wrappingText("Choose a 114,688 (0x1C000) byte file with .bin extension. This app does not download HP firmware.")
            if store.wizard.firmwareOK {
                Button("Choose Firmware…", action: store.chooseFirmware)
                    .disabled(store.wizard.isBusy)
            } else {
                Button("Choose Firmware…", action: store.chooseFirmware)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.wizard.isBusy)
            }
            if store.wizard.firmwareOK, let name = store.firmwareURL?.lastPathComponent {
                wrappingText(name)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        case .flash:
            wrappingText("Write starts at address 0x04000. The SAM-BA bootloader below that address is left intact.")
            if store.wizard.flashSucceeded {
                Button("Flash Calculator") {
                    store.confirmFlash = true
                }
                .disabled(!store.canFlash)
            } else {
                Button("Flash Calculator") {
                    store.confirmFlash = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canFlash)
            }
            connectionStatus
        case .finish:
            FinishDiagram()
            wrappingText("Press RESET on the cable switch-box, then turn the calculator ON. “Pr Error” in the display is expected. Press any key to see 0.0000.")
        case .checksum:
            ChecksumDiagram()
            wrappingText("Turn the calculator OFF (press ON button). Hold g and ENTER, then press ON. Release ON, then release g and ENTER.")
            wrappingText("The display shows the test menu: “1.L 2.C 3.H”. Press 2.")
            HStack(alignment: .center, spacing: 8) {
                Text("You should see")
                CalculatorDisplay(store.expectedChecksumLabel)
            }
            wrappingText("That value is the checksum of the installed firmware (the one you just flashed). Press ON to leave the test menu.")
                .foregroundStyle(.secondary)
        }
    }

    private func wrappingText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledProgress(_ title: String, value: Double, tint: Color? = nil, identity: Int = 0) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(tint ?? Color.accentColor)
                .animation(nil, value: identity)
                .id(identity)
                .accessibilityLabel(title)
        }
    }

    private func warningBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.black)
                .accessibilityHidden(true)
            wrappingText(text)
                .foregroundStyle(.black)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Warning. \(text)")
    }

    private var stepChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(WizardStep.allCases, id: \.self) { step in
                stepChecklistRow(step)
            }
        }
        .padding(.top, 4)
    }

    private func stepChecklistRow(_ step: WizardStep) -> some View {
        let complete = store.wizard.isComplete(step)
        let upcoming = store.wizard.isUpcoming(step)
        let current = store.wizard.step == step
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(complete ? Color.white : Color.secondary, complete ? Color.green : Color.secondary)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.number). \(step.title)")
                    .fontWeight(current ? .semibold : .regular)
                if let detail = store.completionDetail(for: step) {
                    Text(detail)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(upcoming ? Color.secondary : Color.primary)
        .opacity(upcoming ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(checklistAccessibilityLabel(step, complete: complete, upcoming: upcoming))
    }

    private func checklistAccessibilityLabel(_ step: WizardStep, complete: Bool, upcoming: Bool) -> String {
        var label = "\(step.number). \(step.title)"
        if complete {
            label += ", completed"
            if let detail = store.completionDetail(for: step) {
                label += ", \(detail)"
            }
        } else if upcoming {
            label += ", not started"
        } else {
            label += ", current"
        }
        return label
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

    private var navigation: some View {
        HStack {
            Button("Back", action: store.goBack)
                .disabled(!store.wizard.canGoBack)
            Spacer()
            if store.wizard.step == .checksum {
                Button("Done", action: store.done)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue", action: store.advance)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.wizard.canAdvance)
            }
        }
    }
}

private extension Bundle {
    var appVersionLabel: String {
        let marketing = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}
