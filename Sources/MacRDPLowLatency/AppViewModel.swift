import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var configuration: ConnectionConfiguration
    @Published var password = ""
    @Published var rememberPassword = true
    @Published private(set) var freeRDPPath: String?
    @Published private(set) var freeRDPVersion = "检查中…"
    @Published private(set) var usesVideoToolbox = false
    @Published private(set) var probeText = "尚未探测"
    @Published private(set) var probeSucceeded: Bool?
    @Published private(set) var networkDetail = "正在检查局域网质量…"
    @Published private(set) var networkWarning = false
    @Published private(set) var isProbing = false
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "就绪"
    @Published private(set) var logs = ""
    @Published private(set) var sessionLogPath: String?
    @Published private(set) var signals = SessionSignals()
    @Published private(set) var clientCPUPercent: Double?
    @Published private(set) var clientMemoryMB: Double?
    @Published var errorMessage: String?

    private var process: Process?
    private var outputPipe: Pipe?
    private var sessionLogHandle: FileHandle?
    private var performanceTimer: Timer?
    private var lastCredentialAccount = ""
    private var lastObservedTransport = TransportState.waiting

    init() {
        var loadedConfiguration = ConnectionConfiguration.load()
        let defaults = UserDefaults.standard
        let latencyProfileVersionKey = "latency-profile-version"
        let latencyProfileVersion = defaults.integer(forKey: latencyProfileVersionKey)
        if latencyProfileVersion < 3 {
            loadedConfiguration.apply(.fastest)
            loadedConfiguration.save(to: defaults)
        }
        if latencyProfileVersion < 4 {
            loadedConfiguration.migrateLatencyTuningToVersion4()
            loadedConfiguration.save(to: defaults)
            defaults.set(4, forKey: latencyProfileVersionKey)
        }
        if latencyProfileVersion < 5 {
            loadedConfiguration.migrateMeasuredTuningToVersion5()
            loadedConfiguration.save(to: defaults)
            defaults.set(5, forKey: latencyProfileVersionKey)
        }
        if latencyProfileVersion < 6 {
            loadedConfiguration.migrateValidatedProductProfileToVersion6()
            loadedConfiguration.save(to: defaults)
            defaults.set(6, forKey: latencyProfileVersionKey)
        }
        if latencyProfileVersion < 7 {
            loadedConfiguration.migrateRedundant4KPresetToVersion7()
            loadedConfiguration.save(to: defaults)
            defaults.set(7, forKey: latencyProfileVersionKey)
        }
        configuration = loadedConfiguration

        refreshFreeRDP()
        loadPassword()
        probe()
    }

    var canConnect: Bool {
        freeRDPPath != nil &&
            !configuration.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !configuration.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            configuration.sessionMode == .desktop &&
            !isRunning
    }

    var redactedCommand: String {
        guard let binary = freeRDPPath else { return "未找到 sdl-freerdp" }
        return FreeRDPCommandBuilder.redactedCommand(
            binary: binary,
            configuration: configuration,
            passwordProvided: !password.isEmpty
        )
    }

    func apply(_ preset: ExperiencePreset) {
        guard !isRunning else {
            statusText = "当前会话不能热切换预设，请先断开"
            return
        }
        configuration.apply(preset)
        signals = SessionSignals()
        clientCPUPercent = nil
        clientMemoryMB = nil
        statusText = "已选择“\(preset.title)”· 下次连接生效"
    }

    func refreshFreeRDP() {
        freeRDPPath = FreeRDPCommandBuilder.findBinary()
        guard let path = freeRDPPath else {
            freeRDPVersion = "未安装"
            return
        }

        let versionProcess = Process()
        let pipe = Pipe()
        versionProcess.executableURL = URL(fileURLWithPath: path)
        versionProcess.arguments = ["/version"]
        versionProcess.standardOutput = pipe
        versionProcess.standardError = pipe
        do {
            try versionProcess.run()
            versionProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            freeRDPVersion = output.isEmpty ? "已安装" : output
        } catch {
            freeRDPVersion = "无法启动"
        }

        let configProcess = Process()
        let configPipe = Pipe()
        configProcess.executableURL = URL(fileURLWithPath: path)
        configProcess.arguments = ["/buildconfig"]
        configProcess.standardOutput = configPipe
        configProcess.standardError = configPipe
        if (try? configProcess.run()) != nil {
            configProcess.waitUntilExit()
            let data = configPipe.fileHandleForReading.readDataToEndOfFile()
            let buildConfig = String(decoding: data, as: UTF8.self)
            usesVideoToolbox = buildConfig.contains("WITH_VIDEOTOOLBOX=ON")
        }
    }

    func configurationIdentityChanged() {
        let account = configuration.credentialAccount
        guard account != lastCredentialAccount else { return }
        loadPassword()
    }

    func loadPassword() {
        lastCredentialAccount = configuration.credentialAccount
        do {
            password = try KeychainStore.readPassword(account: lastCredentialAccount) ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func probe() {
        guard !isProbing else { return }
        isProbing = true
        probeText = "探测中…"
        probeSucceeded = nil
        let host = configuration.host
        let port = configuration.port

        NetworkProbe.run(host: host, port: port) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isProbing = false
                self.probeSucceeded = result.reachable
                self.networkWarning = result.hasLANQualityIssue
                self.networkDetail = result.detailSummary
                if result.reachable {
                    if result.hasLANQualityIssue {
                        self.probeText = result.shortWarning
                    } else {
                        self.probeText = String(
                            format: "RDP 可达 · TCP %.1f ms%@",
                            result.latencyMilliseconds,
                            result.wifi.map { " · \($0.band)" } ?? ""
                        )
                    }
                } else {
                    self.probeText = "RDP 不可达 · \(result.detail)"
                }
            }
        }
    }

    func connect() {
        guard let binary = freeRDPPath else {
            errorMessage = "未找到 sdl-freerdp，请先安装 FreeRDP。"
            return
        }
        guard !isRunning else { return }

        configuration.save()
        do {
            if rememberPassword && !password.isEmpty {
                try KeychainStore.savePassword(password, account: configuration.credentialAccount)
            } else if !rememberPassword {
                try KeychainStore.deletePassword(account: configuration.credentialAccount)
            }
        } catch {
            errorMessage = "保存凭据失败：\(error.localizedDescription)"
            return
        }

        logs = ""
        signals = SessionSignals()
        lastObservedTransport = .waiting
        beginSessionLog()
        statusText = "正在连接 \(configuration.host)…"

        let launchPlan: FreeRDPLaunchPlan
        do {
            launchPlan = try FreeRDPCommandBuilder.launchPlan(
                for: configuration,
                password: password
            )
        } catch {
            errorMessage = error.localizedDescription
            statusText = "启动失败"
            return
        }

        let launchedProcess = Process()
        let pipe = Pipe()
        let input = Pipe()
        launchedProcess.executableURL = URL(fileURLWithPath: binary)
        launchedProcess.arguments = launchPlan.processArguments
        launchedProcess.standardOutput = pipe
        launchedProcess.standardError = pipe
        if launchPlan.standardInput != nil {
            launchedProcess.standardInput = input
        }
        launchedProcess.environment = processEnvironment(for: configuration)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendLog(chunk)
            }
        }

        launchedProcess.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                try? self.sessionLogHandle?.close()
                self.sessionLogHandle = nil
                self.performanceTimer?.invalidate()
                self.performanceTimer = nil
                self.isRunning = false
                self.process = nil
                self.statusText = process.terminationStatus == 0
                    ? "会话已结束"
                    : "会话异常结束（代码 \(process.terminationStatus)）"
            }
        }

        do {
            try launchedProcess.run()
            process = launchedProcess
            outputPipe = pipe
            isRunning = true
            statusText = "FreeRDP 已启动，正在协商…"
            startPerformanceSampling(for: launchedProcess)

            if let standardInput = launchPlan.standardInput {
                input.fileHandleForWriting.write(standardInput)
                try? input.fileHandleForWriting.close()
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? sessionLogHandle?.close()
            sessionLogHandle = nil
            performanceTimer?.invalidate()
            performanceTimer = nil
            errorMessage = "启动失败：\(error.localizedDescription)"
            statusText = "启动失败"
        }
    }

    func disconnect() {
        guard let process, process.isRunning else { return }
        process.terminate()
        statusText = "正在断开…"
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(redactedCommand, forType: .string)
    }

    func copyWindowsDiagnostic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(WindowsRDPDiagnostic.powerShell, forType: .string)
        statusText = "Windows 只读诊断脚本已复制"
    }

    func copyWindowsHardwareEnable() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(WindowsRDPHardware.enablePowerShell, forType: .string)
        statusText = "硬编配置已复制 · 请在管理员 PowerShell 粘贴运行"
    }

    func copyWindowsHardwareRestore() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(WindowsRDPHardware.restoreLatestPowerShell, forType: .string)
        statusText = "最近一次硬编恢复命令已复制"
    }

    func copyWindows60FPS() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(WindowsRDPFrameRate.enable60FPSPowerShell, forType: .string)
        statusText = "60 FPS 配置已复制 · 会先备份原值"
    }

    func clearLogs() {
        logs = ""
        signals = SessionSignals()
    }

    private func appendLog(_ chunk: String) {
        if let data = chunk.data(using: .utf8) {
            try? sessionLogHandle?.write(contentsOf: data)
        }
        logs.append(chunk)
        if logs.count > 120_000 {
            logs.removeFirst(logs.count - 120_000)
        }
        chunk.enumerateLines { line, _ in
            self.signals.consume(line)
        }
        if signals.connected {
            statusText = "已连接"
        }
    }

    private func beginSessionLog() {
        try? sessionLogHandle?.close()
        sessionLogHandle = nil
        sessionLogPath = nil

        let fileManager = FileManager.default
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacLowLatencyRDP", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let safeHost = configuration.host.replacingOccurrences(
                of: #"[^A-Za-z0-9._-]"#,
                with: "_",
                options: .regularExpression
            )
            let url = directory.appendingPathComponent("session-\(safeHost)-\(formatter.string(from: Date())).log")
            let header = """
            Mac Low Latency RDP session
            Started: \(ISO8601DateFormatter().string(from: Date()))
            Command: \(redactedCommand)

            """
            try Data(header.utf8).write(to: url, options: .atomic)
            sessionLogHandle = try FileHandle(forWritingTo: url)
            try sessionLogHandle?.seekToEnd()
            sessionLogPath = url.path
        } catch {
            sessionLogPath = nil
        }
    }

    private func startPerformanceSampling(for launchedProcess: Process) {
        performanceTimer?.invalidate()
        clientCPUPercent = nil
        clientMemoryMB = nil
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self, weak launchedProcess] _ in
            guard let launchedProcess, launchedProcess.isRunning else { return }
            let sampler = Process()
            let pipe = Pipe()
            sampler.executableURL = URL(fileURLWithPath: "/bin/ps")
            sampler.arguments = ["-p", String(launchedProcess.processIdentifier), "-o", "%cpu=,rss="]
            sampler.standardOutput = pipe
            sampler.standardError = FileHandle.nullDevice
            guard (try? sampler.run()) != nil else { return }
            sampler.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let fields = output.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2, let cpu = Double(fields[0]), let rssKB = Double(fields[1]) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.clientCPUPercent = cpu
                self.clientMemoryMB = rssKB / 1024
                self.appendLog(String(format: "[PERF] client_cpu=%.1f%% rss=%.0fMB\n", cpu, rssKB / 1024))
                self.sampleActualTransport(processIdentifier: launchedProcess.processIdentifier)
            }
        }
    }

    private func sampleActualTransport(processIdentifier: Int32) {
        let sampler = Process()
        let pipe = Pipe()
        sampler.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        sampler.arguments = [
            "-nP", "-a", "-p", String(processIdentifier), "-iTCP", "-iUDP"
        ]
        sampler.standardOutput = pipe
        sampler.standardError = FileHandle.nullDevice
        guard (try? sampler.run()) != nil else { return }
        sampler.waitUntilExit()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard let observed = signals.observeSocketTable(output, host: configuration.host) else {
            return
        }
        if observed != lastObservedTransport {
            lastObservedTransport = observed
            appendLog("[PERF] actual_transport=\(observed.rawValue)\n")
        }
    }

    private func processEnvironment(for configuration: ConnectionConfiguration) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"]
        environment["PATH"] = paths.joined(separator: ":")
        environment["WLOG_APPENDER"] = "CONSOLE"
        environment["SDL_APP_ID"] = "com.local.macrdp.lowlatency.session"
        environment["SDL_APP_NAME"] = "Mac Low Latency RDP Session"
        environment["SDL_RENDER_DRIVER"] = "metal"
        environment["SDL_RENDER_VSYNC"] = configuration.verticalSync ? "1" : "0"
        return environment
    }
}
