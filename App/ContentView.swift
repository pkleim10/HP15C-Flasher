import SwiftUI
import HP15CFlasherCore

struct ContentView: View {
    @EnvironmentObject private var store: FlasherStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if store.showWelcome {
                WelcomeView()
            } else if store.isBatchSession {
                BatchView()
            } else {
                wizardColumn
                    .padding(24)
                    .frame(minWidth: 900, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .topLeading)
            }
        }
            .confirmationDialog(
            store.usingSimulator ? "Flash the simulated calculator?" : "Flash the calculator?",
            isPresented: $store.confirmFlash,
            titleVisibility: .visible
        ) {
            Button("Flash at 0x04000", role: .destructive, action: store.flash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.usingSimulator
                 ? "DEMO writes only the simulated calculator on this Mac. A real HP 15C is not changed."
                 : "FLASH writes a real calculator. User memory will be wiped. The bootloader at 0x0000–0x3FFF is not overwritten.")
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
            HStack(alignment: .top, spacing: 20) {
                stepSidebar
                VStack(alignment: .leading, spacing: 16) {
                    stepBody
                    if store.wizard.isBusy, let progress = store.progress {
                        labeledProgress(
                            store.progressCaption ?? "Working",
                            value: progress,
                            tint: store.progressIsVerify ? .green : (store.progressCaption == "Flashing" ? .blue : Color.accentColor),
                            identity: store.progressBarID
                        )
                        if store.progressCaption == "Flashing", let header = store.flashPageHeader {
                            flashPagePreview(header: header, lines: store.flashPageLines)
                        }
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
                    Spacer(minLength: 0)
                    navigation
                    Text("\(Bundle.main.appVersionLabel) · Mach II Labs · offline · no telemetry · free forever")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("15CE Flasher")
                    .font(.largeTitle.weight(.semibold))
                Text(store.usingSimulator
                     ? "DEMO — simulated Collector’s Edition"
                     : "Native SAM-BA programmer for the Collector’s Edition")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.usingSimulator {
                Text("DEMO")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
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
            if store.usingSimulator {
                wrappingText("DEMO uses a simulated calculator. You do not need a cable. Follow the same steps so FLASH is familiar later.")
                    .foregroundStyle(.secondary)
            }
            warningBox("Use the POGO cable only on the HP 15C Collector’s Edition. This app will not flash other calculators. Do not use the cable on an HP 15C Limited Edition, a pre-2015 12C, an HP 20b, or an HP 30b, as it could permanently damage your calculator.")
        case .programmingMode:
            ProgrammingModeDiagram()
            wrappingText("On the cable's switch box, hold ERASE, press RESET, then release ERASE. The display stays off. The calculator's ON button is ignored in this state.")
            if store.usingSimulator {
                wrappingText("DEMO connects the simulated calculator automatically. Continue when it appears below.")
                    .foregroundStyle(.secondary)
            }
            connectionStatus
            wrappingText("Once your calculator is recognized (“Connected: ATSAM4LC2C” is shown), continue with the next step.")
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
                Button(store.usingSimulator ? "Flash Simulated Calculator" : "Flash Calculator") {
                    store.confirmFlash = true
                }
                .disabled(!store.canFlash)
            } else {
                Button(store.usingSimulator ? "Flash Simulated Calculator" : "Flash Calculator") {
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
            wrappingText("That value is the checksum of the installed firmware (the one you just flashed). Press ON a few times to exit the test menu.")
                .foregroundStyle(.secondary)
            wrappingText("If you received the expected checksum of \(store.expectedChecksumShort), then congratulations — you have successfully updated the firmware on your HP 15C Collector’s Edition.")
            wrappingText("If you received a different checksum, all is not lost. A retry with either the new firmware or the original backup is likely to succeed.")
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

    private var sidebarGreen: Color { Color(red: 0.20, green: 0.78, blue: 0.40) }
    private var sidebarBlue: Color { Color(red: 0.18, green: 0.47, blue: 0.98) }

    private var stepSidebar: some View {
        let steps = WizardStep.allCases
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                sidebarRow(step)
                if index < steps.count - 1 {
                    sidebarConnector(after: step)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 196, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func sidebarRow(_ step: WizardStep) -> some View {
        let complete = store.wizard.isComplete(step)
        let upcoming = store.wizard.isUpcoming(step)
        let current = store.wizard.step == step
        return HStack(alignment: .center, spacing: 10) {
            sidebarMarker(step, complete: complete, current: current, upcoming: upcoming)
            Text("\(step.number). \(step.title)")
                .font(.callout.weight(current ? .semibold : .medium))
                .foregroundStyle(upcoming ? Color.secondary : Color.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background {
            if current {
                Capsule(style: .continuous)
                    .fill(sidebarBlue.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    .shadow(color: sidebarBlue.opacity(0.35), radius: 6, y: 1)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(sidebarBlue.opacity(0.85), lineWidth: 1.5)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(checklistAccessibilityLabel(step, complete: complete, upcoming: upcoming))
    }

    private func sidebarMarker(_ step: WizardStep, complete: Bool, current: Bool, upcoming: Bool) -> some View {
        ZStack {
            if complete {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [sidebarGreen.opacity(0.95), sidebarGreen.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: sidebarGreen.opacity(0.35), radius: 2, y: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else if current {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [sidebarBlue.opacity(0.98), sidebarBlue.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: sidebarBlue.opacity(0.4), radius: 3, y: 1)
                Text("\(step.number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                Text("\(step.number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .opacity(upcoming ? 0.85 : 1)
    }

    private func sidebarConnector(after step: WizardStep) -> some View {
        let next = WizardStep(rawValue: step.rawValue + 1)
        let toCurrent = next == store.wizard.step
        let toComplete = next.map { store.wizard.isComplete($0) } ?? false
        let color: Color = {
            if toComplete { return sidebarGreen }
            if toCurrent { return sidebarBlue }
            return Color.secondary.opacity(0.35)
        }()
        return HStack(spacing: 0) {
            Group {
                if toComplete || toCurrent {
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 16)
                } else {
                    Capsule()
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 2, height: 16)
                }
            }
            .padding(.leading, 18)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
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

    private func flashPagePreview(header: String, lines: [String]) -> some View {
        let well = colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.18)
        let ink = Color(white: colorScheme == .dark ? 0.86 : 0.92)
        return VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flash page data. \(header)")
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
            if store.wizard.step == .cable {
                Button("Back", action: store.returnToWelcome)
            } else if store.wizard.canGoBack {
                Button("Back", action: store.goBack)
            }
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

extension Bundle {
    var appVersionLabel: String {
        let marketing = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}
