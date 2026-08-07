import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @State private var showAdvanced = false
    // Keep the potentially large live log out of the initial accessibility
    // snapshot.  It remains available on demand from the header button.
    @State private var showLogs = false
    @State private var showFullConfiguration = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showFullConfiguration {
                ScrollView {
                    VStack(spacing: 18) {
                        connectionCard
                        workloadGuide
                        presetCard
                        optionsCard
                        launchCard
                        if showLogs { logCard }
                    }
                    .padding(22)
                }
            } else {
                compactDashboard
            }
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 700, idealHeight: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Mac Low Latency RDP", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: model.configuration.host) { _, _ in model.configurationIdentityChanged() }
        .onChange(of: model.configuration.port) { _, _ in model.configurationIdentityChanged() }
        .onChange(of: model.configuration.username) { _, _ in model.configurationIdentityChanged() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Low Latency RDP")
                    .font(.title2.weight(.semibold))
                Text("清晰办公与外网 RDP · FreeRDP TCP · v0.9.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill(
                model.isRunning ? model.statusText : model.probeText,
                color: model.isRunning
                    ? .blue
                    : (model.networkWarning ? .orange : (model.probeSucceeded == true ? .green : .secondary))
            )
            Button {
                showFullConfiguration.toggle()
            } label: {
                Image(systemName: showFullConfiguration ? "rectangle.compress.vertical" : "slider.horizontal.3")
            }
            .help(showFullConfiguration ? "返回快速连接" : "显示完整设置")
            if showFullConfiguration {
                Button {
                    showLogs.toggle()
                } label: {
                    Image(systemName: showLogs ? "text.alignleft" : "text.badge.plus")
                }
                .help(showLogs ? "隐藏日志" : "显示日志")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private var compactDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("快速连接") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("主机")
                        TextField("windows-host.example", text: $model.configuration.host)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                        Text("会话")
                        Text("完整桌面")
                            .foregroundStyle(.secondary)
                        Text("网络")
                        Picker("网络", selection: $model.configuration.networkProfile) {
                            ForEach(NetworkProfile.allCases) { profile in Text(profile.title).tag(profile) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    HStack(spacing: 12) {
                        Text("用户")
                        TextField("Windows 用户名", text: $model.configuration.username)
                            .textFieldStyle(.roundedBorder)
                        Button(model.isProbing ? "探测中" : "重新探测") { model.probe() }
                            .disabled(model.isProbing)
                    }
                    Text(model.networkDetail)
                        .font(.caption)
                        .foregroundStyle(model.networkWarning ? .orange : .secondary)
                }
                .padding(.top, 7)
            }

            workloadGuide

            GroupBox("有效预设") {
                HStack(spacing: 12) {
                    ForEach(ExperiencePreset.userFacingCases) { preset in
                        Button(preset.title) { model.apply(preset) }
                            .buttonStyle(.bordered)
                            .disabled(model.isRunning)
                    }
                }
                .padding(.top, 7)
                Text(presetApplyHint)
                    .font(.caption)
                    .foregroundStyle(model.isRunning ? .orange : .secondary)
                    .padding(.top, 5)
            }

            GroupBox("当前状态") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        statusPill(model.freeRDPPath == nil ? "FreeRDP 未安装" : "FreeRDP 3.30",
                                   color: model.freeRDPPath == nil ? .red : .green)
                        statusPill(model.usesVideoToolbox ? "VideoToolbox 可用" : "软件解码", color: .blue)
                        statusPill("固定 TCP", color: .orange)
                        statusPill("实际：\(model.signals.graphics)", color: .purple)
                        if let cpu = model.clientCPUPercent, let memory = model.clientMemoryMB {
                            statusPill(String(format: "CPU %.0f%% · %.0f MB", cpu, memory), color: cpu >= 150 ? .orange : .secondary)
                        }
                    }
                    Text(model.redactedCommand)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if let sessionLogPath = model.sessionLogPath {
                        Text("会话日志：\(sessionLogPath)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 7)
            }

            Spacer(minLength: 0)
            HStack {
                Button("完整设置") { showFullConfiguration = true }
                Spacer()
                if model.isRunning {
                    Button("断开", role: .destructive) { model.disconnect() }
                        .controlSize(.large)
                } else {
                    Button("连接", systemImage: "play.fill") { model.connect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canConnect)
                }
            }
        }
        .padding(22)
    }

    private var connectionCard: some View {
        GroupBox("连接") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("主机")
                    TextField("windows-host.example", text: $model.configuration.host)
                        .textFieldStyle(.roundedBorder)
                    Text("端口")
                    TextField("3389", value: $model.configuration.port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Button(model.isProbing ? "探测中" : "探测") { model.probe() }
                        .disabled(model.isProbing)
                }
                GridRow {
                    Text("会话")
                    Text("完整桌面（Windows Pro 已验证）")
                        .foregroundStyle(.secondary)
                    Text("网络")
                    Picker("", selection: $model.configuration.networkProfile) {
                        ForEach(NetworkProfile.allCases) { profile in Text(profile.title).tag(profile) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Color.clear.frame(width: 48)
                }
                GridRow {
                    Text("用户名")
                    TextField("Windows 用户名", text: $model.configuration.username)
                        .textFieldStyle(.roundedBorder)
                    Text("域")
                    TextField("可留空", text: $model.configuration.domain)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Color.clear.frame(width: 48)
                }
                GridRow {
                    Text("密码")
                    SecureField("通过 stdin 安全传递", text: $model.password)
                        .textFieldStyle(.roundedBorder)
                    Toggle("存入 Keychain", isOn: $model.rememberPassword)
                        .gridCellColumns(3)
                }
            }
            .padding(.top, 7)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: model.networkWarning ? "exclamationmark.triangle.fill" : "network")
                    .foregroundStyle(model.networkWarning ? .orange : .secondary)
                Text(model.networkDetail)
                    .font(.caption)
                    .foregroundStyle(model.networkWarning ? .orange : .secondary)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.top, 10)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("RemoteApp 与应用启动已从界面停用：Windows Pro + FreeRDP SDL3 实测均为黑屏。真正 RemoteApp 需要 Windows Server RDS、Azure Virtual Desktop 或 Windows 365。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var workloadGuide: some View {
        GroupBox("按实测选择客户端") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    workloadItem(
                        icon: "cursorarrow.motionlines",
                        title: "交互动画 / 办公",
                        client: "Mac Low Latency RDP",
                        detail: "实测动画略顺；文字清晰可调",
                        color: .green
                    )
                    workloadItem(
                        icon: "4k.tv",
                        title: "4K 视频",
                        client: "Windows App",
                        detail: "实测明显比本客户端流畅",
                        color: .blue
                    )
                    workloadItem(
                        icon: "gamecontroller",
                        title: "游戏 / 高帧率",
                        client: "Moonlight",
                        detail: "低延迟视频管线更合适",
                        color: .purple
                    )
                }
                Text("FreeRDP 3.30 客户端 UDP 尚未实现；本客户端固定使用 TCP。两个旧 4K 模式实测无可见或资源差异，已合并；真正能减负的是 3K 预设。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 7)
        }
    }

    private func workloadItem(
        icon: String,
        title: String,
        client: String,
        detail: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(client).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var presetCard: some View {
        GroupBox("有效预设") {
            HStack(spacing: 12) {
                ForEach(ExperiencePreset.userFacingCases) { preset in
                    Button {
                        model.apply(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title).font(.headline)
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunning)
                }
            }
            .padding(.top, 7)
            Text(presetApplyHint)
                .font(.caption)
                .foregroundStyle(model.isRunning ? .orange : .secondary)
                .padding(.top, 5)
        }
    }

    private var presetApplyHint: String {
        if model.isRunning {
            return "当前会话不会热切换图形模式；请先断开，再选择预设并重新连接。上方紫色标签显示当前会话的实际协议。"
        }
        return "下次连接：\(model.configuration.resolution.detail) · \(model.configuration.graphicsMode.title) · \(model.configuration.frameAcknowledgement.title)。连接后以“实际”标签为准。"
    }

    private var optionsCard: some View {
        GroupBox {
            DisclosureGroup("连接参数", isExpanded: $showAdvanced) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("分辨率")
                        Picker("", selection: $model.configuration.resolution) {
                            ForEach(ResolutionPreset.allCases) { preset in
                                Text("\(preset.title) · \(preset.detail)").tag(preset)
                            }
                        }
                        .labelsHidden()
                        Text("图形")
                        Picker("", selection: $model.configuration.graphicsMode) {
                            ForEach(GraphicsMode.userFacingCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Toggle("异步画面更新（SDL 当前禁用）", isOn: $model.configuration.asynchronousUpdate)
                            .disabled(true)
                        Toggle("异步通道", isOn: $model.configuration.asynchronousChannels)
                        Toggle("VSync 帧同步", isOn: $model.configuration.verticalSync)
                        Picker("Frame ACK", selection: $model.configuration.frameAcknowledgement) {
                            ForEach(FrameAcknowledgement.allCases) { option in Text(option.title).tag(option) }
                        }
                    }
                    GridRow {
                        Toggle("全屏", isOn: $model.configuration.fullscreen)
                        Toggle("动态分辨率", isOn: $model.configuration.dynamicResolution)
                        Toggle("剪贴板", isOn: $model.configuration.clipboard)
                        Toggle("音频", isOn: $model.configuration.audio)
                    }
                    GridRow {
                        Toggle("麦克风", isOn: $model.configuration.microphone)
                        Toggle("完整视觉效果", isOn: $model.configuration.visualEffects)
                        Label("FreeRDP 固定 TCP", systemImage: "network")
                            .foregroundStyle(.orange)
                        Toggle("自动重连", isOn: $model.configuration.autoReconnect)
                    }
                }
                .padding(.top, 12)
                .disabled(model.isRunning)
            }
        }
    }

    private var launchCard: some View {
        GroupBox("会话") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    statusPill(model.freeRDPPath == nil ? "FreeRDP 未安装" : "FreeRDP 3.30",
                               color: model.freeRDPPath == nil ? .red : .green)
                    statusPill(
                        model.signals.hardwareDecode
                            ? "VideoToolbox 硬解中"
                            : (model.usesVideoToolbox ? "VideoToolbox 可用" : "FFmpeg 软件解码"),
                        color: model.signals.hardwareDecode ? .green : (model.usesVideoToolbox ? .blue : .orange)
                    )
                    statusPill("TCP（FreeRDP 固定）", color: .orange)
                    statusPill("实际：\(model.signals.graphics)", color: .purple)
                    if let cpu = model.clientCPUPercent, let memory = model.clientMemoryMB {
                        statusPill(String(format: "CPU %.0f%% · %.0f MB", cpu, memory), color: cpu >= 150 ? .orange : .secondary)
                    }
                    statusPill(
                        "远程 \(model.signals.overriddenDesktopSize ?? model.configuration.resolution.detail)",
                        color: model.signals.overriddenDesktopSize == nil ? .blue : .orange
                    )
                    Spacer()
                    if model.isRunning {
                        Button("断开", role: .destructive) { model.disconnect() }
                    } else {
                        Button("连接", systemImage: "play.fill") { model.connect() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!model.canConnect)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(model.redactedCommand)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Spacer(minLength: 8)
                    Button { model.copyCommand() } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("复制不含密码的启动命令")
                    Button("复制 Windows 诊断") { model.copyWindowsDiagnostic() }
                        .buttonStyle(.plain)
                        .help("复制只读 PowerShell，检查 GPU、RDP 编码事件；UDP 仅供 Windows App 能力核对")
                    Button("复制硬编配置") { model.copyWindowsHardwareEnable() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .help("复制带逐项备份的管理员 PowerShell；不会修改防火墙或自动重启")
                    Button("复制 60 FPS") { model.copyWindows60FPS() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .help("备份并设置微软文档中的 DWMFRAMEINTERVAL=15；重启后生效")
                    Button("复制恢复") { model.copyWindowsHardwareRestore() }
                        .buttonStyle(.plain)
                        .help("复制恢复最近一次 RDP 图形策略备份的 PowerShell")
                }
                if let sessionLogPath = model.sessionLogPath {
                    Text("会话日志：\(sessionLogPath)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 7)
        }
    }

    private var logCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("协商日志").font(.headline)
                    Spacer()
                    Button("清空") { model.clearLogs() }
                        .buttonStyle(.plain)
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(model.logs.isEmpty ? "连接后将在这里显示 TCP、GFX 和 AVC 协商信息。" : model.logs)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(model.logs.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 130, maxHeight: 230)
                .padding(10)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                // Exposing every attributed run from a large FreeRDP log can
                // overwhelm macOS accessibility clients.  Publish a stable
                // summary instead; the visible text remains selectable.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.logs.isEmpty ? "协商日志为空" : "协商日志，\(model.logs.count) 个字符")
            }
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}
