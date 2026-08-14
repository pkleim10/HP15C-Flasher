import AppKit
import Foundation
import HP15CFlasherCore

@MainActor
final class FlasherStore: ObservableObject {
    @Published var wizard = WizardState()
    @Published var status = "Waiting for programming cable…"
    @Published var portPath: String?
    @Published var identity: DeviceIdentity?
    @Published var sambaVersion: String?
    @Published var firmwareURL: URL?
    @Published var firmwareDetail = "No firmware selected."
    @Published var expectedChecksumLabel = "the checksum for your .bin"
    @Published var backupSkipped = false
    @Published var backupFileName: String?
    @Published var progress: Double?
    @Published var lastError: String?
    @Published var successMessage: String?
    @Published var confirmFlash = false
    @Published var confirmSkipBackup = false
    #if DEBUG
    @Published var usingSimulator = false
    #endif

    private var client: SambaClient?
    private var pollTask: Task<Void, Never>?
    private var flasher = Flasher()
    #if DEBUG
    private var simulator: SimulatedCalculatorTransport?
    #endif

    var canBackup: Bool {
        !wizard.isBusy && client != nil && identity?.isSupported15C == true
    }

    var canFlash: Bool {
        canBackup && wizard.firmwareOK && wizard.backupResolved
    }

    var chipLabel: String {
        identity?.name ?? "Not connected"
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refreshConnection()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        disconnect()
    }

    func advance() {
        wizard.advance()
    }

    func goBack() {
        wizard.goBack()
    }

    func chooseFirmware() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose HP 15C CE firmware"
        panel.message = "Select a 112 KB .bin application image. This app does not download firmware."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyFirmware(from: url)
    }

    func applyFirmware(from url: URL) {
        do {
            let image = try FirmwareImage.load(from: url)
            firmwareURL = image.url
            let checksum = VoyagerFirmwareChecksum.formatted(of: image.data)
            expectedChecksumLabel = checksum
            firmwareDetail = "\(image.url.lastPathComponent) — \(image.byteCount) bytes, write at 0x04000, checksum \(checksum)"
            wizard.firmwareOK = true
            lastError = nil
        } catch {
            firmwareURL = nil
            firmwareDetail = error.localizedDescription
            expectedChecksumLabel = "the checksum for your .bin"
            wizard.firmwareOK = false
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
        guard let client else { return }
        backupSkipped = false
        runBusy(statusText: "Reading firmware…") {
            try self.flasher.read(to: url, client: client) { fraction in
                Task { @MainActor in
                    self.progress = fraction
                }
            }
            return "Saved backup to \(url.lastPathComponent)"
        } onSuccess: {
            self.backupFileName = url.lastPathComponent
            self.wizard.backupResolved = true
        }
    }

    func skipBackup() {
        confirmSkipBackup = false
        backupSkipped = true
        backupFileName = nil
        wizard.backupResolved = true
    }

    func done() {
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
        guard let firmwareURL, let client else { return }
        confirmFlash = false
        runBusy(statusText: "Writing firmware…") {
            try self.flasher.write(firmwareURL: firmwareURL, client: client) { fraction in
                Task { @MainActor in
                    self.progress = fraction
                }
            }
            return "Flashed and verified."
        } onSuccess: {
            self.wizard.flashSucceeded = true
        }
    }

    #if DEBUG
    func setUsingSimulator(_ enabled: Bool) {
        disconnect()
        wizard.identitySupported = false
        usingSimulator = enabled
        if enabled {
            let sim = SimulatedCalculatorTransport(operationDelay: 0.010, preloadApplication: true)
            simulator = sim
            flasher = Flasher(
                ports: SimulatedPortListing(),
                openTransport: { _ in sim }
            )
            status = "DEMO: connecting simulated ATSAM4LC2C…"
            Task { await refreshConnection() }
        } else {
            simulator = nil
            flasher = Flasher()
            status = "Waiting for programming cable…"
        }
    }
    #endif

    private func runBusy(
        statusText: String,
        work: @escaping () throws -> String,
        onSuccess: @escaping () -> Void
    ) {
        wizard.isBusy = true
        lastError = nil
        successMessage = nil
        progress = 0
        status = statusText
        Task.detached {
            do {
                let done = try work()
                await MainActor.run {
                    self.wizard.isBusy = false
                    self.progress = 1
                    self.successMessage = done
                    self.status = "Connected: \(self.chipLabel)"
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    self.wizard.isBusy = false
                    self.progress = nil
                    self.lastError = error.localizedDescription
                    self.status = "Operation failed."
                }
            }
        }
    }

    private func refreshConnection() async {
        if wizard.isBusy { return }
        let cables = (try? flasher.listProgrammingCables()) ?? []
        if cables.isEmpty {
            if client != nil {
                disconnect()
                wizard.identitySupported = false
                status = "Waiting for programming cable…"
            }
            return
        }
        if client != nil { return }
        do {
            let connected = try flasher.connect()
            client = connected.client
            identity = connected.identity
            portPath = connected.port.path
            sambaVersion = connected.client.version
            wizard.identitySupported = connected.identity.isSupported15C
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
        } catch {
            disconnect()
            wizard.identitySupported = false
            status = error.localizedDescription
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
