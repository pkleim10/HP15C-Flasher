import AppKit
import Foundation
import SwiftUI
import HP15CFlasherCore

enum FlasherMode: String, CaseIterable {
    case demo
    case flash
}

@MainActor
final class FlasherStore: ObservableObject {
    @Published var wizard = WizardState()
    @Published var status = "Waiting for programming cable…"
    @Published var portPath: String?
    @Published var identity: DeviceIdentity?
    @Published var sambaVersion: String?
    @Published var firmwareURL: URL?
    @Published var firmwareDetail = "No firmware selected."
    @Published var expectedChecksumLabel = "ChE - - ----h"
    @Published var backupSkipped = false
    @Published var backupFileName: String?
    @Published var backupAssessment: BackupChecksumAssessment?
    @Published var firmwareAssessment: FirmwareFileAssessment?
    @Published var progress: Double?
    @Published var progressCaption: String?
    @Published var progressIsVerify = false
    @Published var progressBarID = 0
    @Published var flashPageHeader: String?
    @Published var flashPageLines: [String] = []
    @Published var lastError: String?
    @Published var successMessage: String?
    @Published var confirmFlash = false
    @Published var confirmSkipBackup = false
    @Published var usingSimulator = false
    @Published var showWelcome = true
    @Published var selectedMode: FlasherMode = FlasherStore.savedMode()
    @Published var hasCompletedDemo = UserDefaults.standard.bool(forKey: FlasherStore.demoCompletedDefaultsKey)

    private var client: SambaClient?
    private var pollTask: Task<Void, Never>?
    private var flasher = Flasher()
    private var simulator: SimulatedCalculatorTransport?
    private var simulatorHotKeyMonitor: Any?
    private var demoConnectAfter: Date?

    private static let modeDefaultsKey = "flasherMode"
    private static let demoCompletedDefaultsKey = "demoModeCompleted"
    private static let demoCableDetectedSeconds: TimeInterval = 3

    private static func savedMode() -> FlasherMode {
        if let raw = UserDefaults.standard.string(forKey: modeDefaultsKey),
           let mode = FlasherMode(rawValue: raw) {
            return mode
        }
        return .demo
    }

    private func resetWizardForNewSession() {
        let keepFirmware = wizard.firmwareOK
        wizard = WizardState()
        wizard.firmwareOK = keepFirmware
        backupSkipped = false
        backupFileName = nil
        backupAssessment = nil
        if keepFirmware, let firmwareURL, let data = try? Data(contentsOf: firmwareURL) {
            refreshFirmwareAssessment(selected: data)
        } else {
            firmwareAssessment = nil
        }
        wizard.flashSucceeded = false
        lastError = nil
        successMessage = nil
        progress = nil
        progressCaption = nil
        clearFlashPagePreview()
        identity = nil
        portPath = nil
        sambaVersion = nil
        demoConnectAfter = nil
    }

    var canBackup: Bool {
        !wizard.isBusy && client != nil && identity?.isSupported15C == true
    }

    var canFlash: Bool {
        canBackup && wizard.firmwareOK && wizard.backupResolved
    }

    var chipLabel: String {
        identity?.name ?? "Not connected"
    }

    /// Test-menu checksum of the chosen file, for example `0A0Ah`.
    var expectedChecksumShort: String {
        let prefix = "ChE - - "
        guard expectedChecksumLabel.hasPrefix(prefix) else { return "----h" }
        return String(expectedChecksumLabel.dropFirst(prefix.count))
    }

    var stepBanner: (text: String, caution: Bool)? {
        switch wizard.step {
        case .backup:
            if !wizard.backupResolved { return nil }
            if backupSkipped {
                return ("Backup skipped.", true)
            }
            if let assessment = backupAssessment {
                return (assessment.message, !assessment.isRecognized)
            }
            return ("Backup saved.", false)
        case .firmware:
            guard let firmwareAssessment else { return nil }
            return (firmwareAssessment.message, firmwareAssessment.isCaution)
        case .flash:
            if wizard.flashSucceeded {
                return ("Flashed and verified.", false)
            }
            return nil
        default:
            return nil
        }
    }

    func start() {
        installSimulatorHotKey()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.showWelcome {
                    await self.refreshConnection()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func beginChosenSession() {
        UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.modeDefaultsKey)
        resetWizardForNewSession()
        showWelcome = false
        setUsingSimulator(selectedMode == .demo)
    }

    func returnToWelcome() {
        disconnect()
        wizard.identitySupported = false
        wizard.isBusy = false
        lastError = nil
        successMessage = nil
        progress = nil
        progressCaption = nil
        demoConnectAfter = nil
        showWelcome = true
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        removeSimulatorHotKey()
        disconnect()
    }

    func advance() {
        wizard.advance()
        if wizard.step == .programmingMode {
            status = usingSimulator
                ? "Cable detected. Hold ERASE, press RESET, then release ERASE."
                : "Waiting for SAM-BA…"
            Task { await refreshConnection() }
        }
        if usingSimulator, wizard.step == .checksum {
            markDemoCompleted()
        }
    }

    private func markDemoCompleted() {
        guard !hasCompletedDemo else { return }
        hasCompletedDemo = true
        UserDefaults.standard.set(true, forKey: Self.demoCompletedDefaultsKey)
    }

    func goBack() {
        if wizard.step == .programmingMode {
            disconnect()
            wizard.identitySupported = false
            demoConnectAfter = nil
        }
        wizard.goBack()
    }

    func chooseFirmware() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose HP 15C CE firmware"
        panel.message = "Select a 114,688 (0x1C000) byte file with a .bin extension. This app does not download firmware."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyFirmware(from: url)
    }

    func applyFirmware(from url: URL) {
        do {
            let image = try FirmwareImage.load(from: url)
            firmwareURL = image.url
            let checksum = VoyagerFirmwareChecksum.formatted(of: image.data)
            expectedChecksumLabel = VoyagerFirmwareChecksum.testMenuDisplay(of: image.data)
            firmwareDetail = "\(image.url.lastPathComponent) — \(image.byteCount) bytes, write at 0x04000, checksum \(checksum)"
            wizard.firmwareOK = true
            lastError = nil
            refreshFirmwareAssessment(selected: image.data)
        } catch {
            firmwareURL = nil
            firmwareDetail = error.localizedDescription
            expectedChecksumLabel = "ChE - - ----h"
            wizard.firmwareOK = false
            firmwareAssessment = nil
            lastError = error.localizedDescription
        }
    }

    func backup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "hp15c-firmware.bin"
        panel.title = "Save current firmware"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backup(to: url)
    }

    func backup(to url: URL) {
        backupSkipped = false
        backupAssessment = nil
        let existing = client
        let tool = flasher
        beginBusy(statusText: "Reading firmware…", caption: "Backing up")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let samba = try await FlasherStore.preparedClient(existing: existing, tool: tool, store: self)
                try tool.read(to: url, client: samba) { fraction, _ in
                    Task { @MainActor in
                        self.progress = fraction
                        self.progressCaption = "Backing up"
                        self.progressIsVerify = false
                    }
                }
                await MainActor.run {
                    self.finishBusySuccess("Backup saved.") {
                        if let saved = try? Data(contentsOf: url) {
                            self.backupAssessment = VoyagerFirmwareChecksum.backupAssessment(of: saved)
                        }
                        self.backupFileName = url.lastPathComponent
                        self.wizard.backupResolved = true
                        if let firmwareURL = self.firmwareURL, let selected = try? Data(contentsOf: firmwareURL) {
                            self.refreshFirmwareAssessment(selected: selected)
                        }
                    }
                }
            } catch {
                await MainActor.run { self.finishBusyFailure(error) }
            }
        }
    }

    func skipBackup() {
        confirmSkipBackup = false
        backupSkipped = true
        backupFileName = nil
        backupAssessment = nil
        wizard.backupResolved = true
        firmwareAssessment = nil
        if let firmwareURL, let selected = try? Data(contentsOf: firmwareURL) {
            refreshFirmwareAssessment(selected: selected)
        }
    }

    func done() {
        if usingSimulator {
            markDemoCompleted()
        }
        NSApp.terminate(nil)
    }

    func completionDetail(for step: WizardStep) -> String? {
        guard wizard.isComplete(step) else { return nil }
        switch step {
        case .cable:
            return "Pogo cable seated"
        case .programmingMode:
            var parts: [String] = []
            if identity?.isSupported15C == true {
                parts.append(chipLabel)
            }
            if let portPath {
                parts.append(portPath)
            }
            return parts.isEmpty ? "SAM-BA connected" : "Connected \(parts.joined(separator: " · "))"
        case .backup:
            if backupSkipped { return "Backup skipped" }
            if let assessment = backupAssessment {
                let name = backupFileName.map { "Saved \($0) · " } ?? "Saved · "
                return name + VoyagerFirmwareChecksum.formatted(assessment.displayed)
            }
            if let backupFileName { return "Saved backup \(backupFileName)" }
            return "Backup saved"
        case .firmware:
            if let name = firmwareURL?.lastPathComponent {
                return "Loaded firmware \(name)"
            }
            return "Firmware selected"
        case .flash:
            return "Flashed and verified at 0x04000"
        case .finish:
            return "RESET, then ON. Pr Error expected"
        case .checksum:
            return nil
        }
    }

    func flash() {
        guard let firmwareURL else { return }
        confirmFlash = false
        let url = firmwareURL
        let existing = client
        let tool = flasher
        beginBusy(statusText: "Writing firmware…", caption: "Flashing")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let samba = try await FlasherStore.preparedClient(existing: existing, tool: tool, store: self)
                try tool.write(firmwareURL: url, client: samba, verify: true) { fraction, phase in
                    Task { @MainActor in
                        self.applyFlashProgress(fraction, phase)
                    }
                } pageProgress: { page in
                    Task { @MainActor in
                        self.applyFlashPageWrite(page)
                    }
                }
                await MainActor.run {
                    self.finishBusySuccess("Flashed and verified.") {
                        self.wizard.flashSucceeded = true
                    }
                }
            } catch {
                await MainActor.run { self.finishBusyFailure(error) }
            }
        }
    }

    private func installSimulatorHotKey() {
        guard simulatorHotKeyMonitor == nil else { return }
        simulatorHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isSimulatorToggle(event) else { return event }
            Task { @MainActor in
                guard let self else { return }
                if self.showWelcome {
                    self.selectedMode = self.selectedMode == .demo ? .flash : .demo
                } else {
                    self.setUsingSimulator(!self.usingSimulator)
                }
            }
            return nil
        }
    }

    /// ⌘⇧S only. Ignores repeats and leftover modifier combinations.
    private static func isSimulatorToggle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !event.isARepeat, event.keyCode == 1 else { return false }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return mods == [.command, .shift]
    }

    private func removeSimulatorHotKey() {
        if let simulatorHotKeyMonitor {
            NSEvent.removeMonitor(simulatorHotKeyMonitor)
            self.simulatorHotKeyMonitor = nil
        }
    }

    func setUsingSimulator(_ enabled: Bool) {
        disconnect()
        wizard.identitySupported = false
        demoConnectAfter = nil
        usingSimulator = enabled
        selectedMode = enabled ? .demo : .flash
        UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.modeDefaultsKey)
        if enabled {
            let sim = SimulatedCalculatorTransport(operationDelay: 0.010, preloadApplication: true)
            simulator = sim
            flasher = Flasher(
                ports: SimulatedPortListing(),
                openTransport: { _ in sim },
                flashCommandSettleSeconds: 0
            )
            status = "DEMO: connecting simulated calculator…"
            Task { await refreshConnection() }
        } else {
            simulator = nil
            flasher = Flasher()
            status = "Waiting for programming cable…"
        }
    }

    private func refreshFirmwareAssessment(selected: Data) {
        firmwareAssessment = VoyagerFirmwareChecksum.firmwareFileAssessment(
            of: selected,
            backup: backupAssessment,
            backupSkipped: backupSkipped
        )
    }

    private func beginBusy(statusText: String, caption: String?) {
        wizard.isBusy = true
        lastError = nil
        successMessage = nil
        progress = 0
        progressCaption = caption
        progressIsVerify = false
        status = statusText
        clearFlashPagePreview()
    }

    private func clearFlashPagePreview() {
        flashPageHeader = nil
        flashPageLines = []
    }

    private func applyFlashPageWrite(_ page: FlashPageWrite) {
        flashPageHeader = page.header
        flashPageLines = page.formattedWordLines()
    }

    private func finishBusySuccess(_ message: String, extra: () -> Void) {
        wizard.isBusy = false
        progress = 1
        progressCaption = nil
        progressIsVerify = false
        clearFlashPagePreview()
        successMessage = message
        status = "Connected: \(chipLabel)"
        extra()
    }

    private func finishBusyFailure(_ error: Error) {
        wizard.isBusy = false
        progress = nil
        progressCaption = nil
        progressIsVerify = false
        clearFlashPagePreview()
        lastError = error.localizedDescription
        status = "Operation failed."
        disconnect()
        wizard.identitySupported = false
    }

    private func applyFlashProgress(_ fraction: Double, _ phase: FlashProgressPhase) {
        switch phase {
        case .writing:
            progress = min(1, fraction)
            progressCaption = "Flashing"
            progressIsVerify = false
            status = "Writing firmware…"
        case .verifying:
            clearFlashPagePreview()
            if !progressIsVerify {
                progress = nil
                progressBarID += 1
                progressCaption = "Verifying"
                progressIsVerify = true
                status = "Verifying firmware…"
            }
            progress = fraction
        case .reading:
            break
        }
    }

    /// Ping/connect on the caller’s executor so flash sleeps never run on the UI thread.
    private nonisolated static func preparedClient(
        existing: SambaClient?,
        tool: Flasher,
        store: FlasherStore
    ) async throws -> SambaClient {
        if let existing {
            do {
                try existing.ping(timeout: 2.0)
                return existing
            } catch {
                await MainActor.run {
                    store.status = "Reconnecting to SAM-BA…"
                    store.disconnect()
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        do {
            let connected = try tool.connect(timeout: 3.0)
            await MainActor.run { store.adopt(connected) }
            return connected.client
        } catch {
            if case FlasherError.sambaTimeout = error {
                throw FlasherError.sambaTimeout(
                    "Timed out reconnecting to SAM-BA. Leave the cable plugged in. If Status is not Connected, hold ERASE, press RESET, then release ERASE."
                )
            }
            throw error
        }
    }

    private func adopt(_ connected: ConnectedTarget) {
        client = connected.client
        identity = connected.identity
        portPath = connected.port.path
        sambaVersion = connected.client.version
        wizard.identitySupported = connected.identity.isSupported15C
    }

    private func refreshConnection() async {
        if wizard.isBusy { return }
        // Step 1 is seating the cable. Do not open serial there.
        if wizard.step == .cable { return }
        let cables = (try? flasher.listProgrammingCables()) ?? []
        let modems = cables.filter { $0.name.lowercased().hasPrefix("cu.usbmodem") }
        if cables.isEmpty {
            if client != nil {
                disconnect()
                wizard.identitySupported = false
            }
            status = "Waiting for programming cable…"
            portPath = nil
            return
        }
        if let existing = client {
            if await probePing(existing) {
                return
            }
            disconnect()
            wizard.identitySupported = false
        }
        portPath = modems.first?.path ?? cables.first?.path
        if usingSimulator {
            if demoConnectAfter == nil {
                demoConnectAfter = Date().addingTimeInterval(Self.demoCableDetectedSeconds)
            }
            if let until = demoConnectAfter, Date() < until {
                status = "Cable detected. Hold ERASE, press RESET, then release ERASE."
                return
            }
        }
        if modems.isEmpty {
            status = "Cable detected. Hold ERASE, press RESET, then release ERASE."
            return
        }
        if !usingSimulator {
            status = "Waiting for SAM-BA…"
        }
        let tool = flasher
        let probed = await probeConnect(tool)
        switch probed {
        case .success(let connected):
            adopt(connected)
            if connected.identity.isSupported15C {
                status = "Connected: \(connected.identity.name)"
                lastError = nil
            } else {
                status = "Unsupported chip: \(connected.identity.name)"
                lastError = FlasherError.unsupportedDevice(
                    name: connected.identity.name,
                    cidr: connected.identity.cidr,
                    exid: connected.identity.exid
                ).localizedDescription
            }
        case .failure:
            disconnect()
            wizard.identitySupported = false
            portPath = modems.first?.path ?? cables.first?.path
            status = "Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE."
        }
    }

    /// Handshake off the main thread. A wedged CDC node must not stall the poll loop.
    private func probeConnect(_ tool: Flasher) async -> Result<ConnectedTarget, Error> {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    gate.finish(.success(try tool.connect(timeout: 1.5)))
                } catch {
                    gate.finish(.failure(error))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                gate.finish(.failure(FlasherError.sambaTimeout()))
            }
        }
    }

    /// CHIPID read off the main thread. Detects RESET leaving SAM-BA while USB stays up.
    private func probePing(_ client: SambaClient) async -> Bool {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try client.ping(timeout: 1.5)
                    gate.finish(true)
                } catch {
                    gate.finish(false)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                gate.finish(false)
            }
        }
    }

    private func disconnect() {
        client?.close()
        client = nil
        identity = nil
        portPath = nil
        sambaVersion = nil
    }
}

private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }
}
