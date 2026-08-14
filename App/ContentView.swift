import SwiftUI
import HP15CFlasherCore

struct ContentView: View {
    @EnvironmentObject private var store: FlasherStore

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
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            if let success = store.successMessage {
                Text(success)
                    .foregroundStyle(.green)
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
            wrappingText("Open the battery door and seat the pogo cable. It is keyed: the wider wing goes right.")
            wrappingText("Plug USB-C into this Mac. Do not use this cable on an HP 15C Limited Edition or a pre-2015 12C.")
                .foregroundStyle(.secondary)
        case .programmingMode:
            ProgrammingModeDiagram()
            wrappingText("Hold ERASE, press RESET, then release ERASE. The display stays off; ON is ignored.")
            wrappingText("Continue stays off until this Mac sees SAM-BA on the cable.")
                .foregroundStyle(.secondary)
            connectionStatus
        case .backup:
            wrappingText("Save a copy of the 112 KB application image before anything is erased.")
            HStack {
                Button("Save Backup…", action: store.backup)
                    .disabled(!store.canBackup)
                Button("Skip") { store.confirmSkipBackup = true }
                    .disabled(store.wizard.isBusy)
            }
            if store.wizard.backupResolved {
                Text(store.backupSkipped ? "Backup skipped." : "Backup saved.")
                    .foregroundStyle(store.backupSkipped ? .orange : .green)
            }
        case .firmware:
            wrappingText("Choose a 112 KB .bin. This app does not download HP firmware.")
            wrappingText(store.firmwareDetail)
                .textSelection(.enabled)
            Button("Choose Firmware…", action: store.chooseFirmware)
                .disabled(store.wizard.isBusy)
        case .flash:
            wrappingText("Write starts at address 0x04000. The SAM-BA bootloader below that address is left intact.")
            Button("Flash Calculator") {
                store.confirmFlash = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!store.canFlash)
            connectionStatus
        case .finish:
            FinishDiagram()
            wrappingText("Press RESET on the cable, then turn the calculator ON. Pr Error is expected; user memory was cleared. Press any key to see 0.0000.")
        case .checksum:
            ChecksumDiagram()
            wrappingText("Turn the calculator OFF. Hold g and ENTER, then press ON. Release ON, then release g and ENTER.")
            wrappingText("The display shows 1.L 2.C 3.H. Press 2.")
            HStack(alignment: .center, spacing: 8) {
                Text("You should see")
                CalculatorDisplay(store.expectedChecksumLabel)
            }
            wrappingText("That value is the 8-bit checksum of the selected .bin, shown as a repeated byte. Press ON to leave the test menu.")
                .foregroundStyle(.secondary)
        }
    }

    private func wrappingText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: complete ? "checkmark.square.fill" : "square")
                .foregroundStyle(complete ? Color.accentColor : Color.secondary)
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
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Status", value: store.status)
            LabeledContent("Port", value: store.portPath ?? "—")
            LabeledContent("SAM-BA", value: store.sambaVersion ?? "—")
        }
        .font(.callout)
        .textSelection(.enabled)
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
