import Foundation

enum ResolutionPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case fast
    case balanced
    case native

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "极速"
        case .balanced: "均衡"
        case .native: "清晰"
        }
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .fast: (2048, 858)
        case .balanced: (3072, 1288)
        case .native: (4096, 1716)
        }
    }

    var detail: String {
        let size = dimensions
        return "\(size.width) × \(size.height)"
    }

    /// Keep Windows UI at roughly the same logical size while increasing the
    /// number of remote pixels. Unlike smart-sizing a 2K bitmap to a Retina
    /// panel, server-side desktop scaling keeps text and charts sharp.
    var desktopScalePercent: Int {
        switch self {
        case .fast: 100
        case .balanced: 150
        case .native: 200
        }
    }

    var deviceScalePercent: Int {
        switch self {
        case .fast: 100
        case .balanced: 140
        case .native: 180
        }
    }
}

enum GraphicsMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case avc420
    case avc444
    case video
    case automatic

    var id: String { rawValue }

    static let userFacingCases: [GraphicsMode] = [.avc420, .avc444, .automatic]

    var title: String {
        switch self {
        case .avc420: "禁用 AVC444（低延迟）"
        case .avc444: "允许 AVC444v2（清晰文字）"
        case .video: "AVC420 + 视频通道（实验）"
        case .automatic: "自动协商"
        }
    }
}

enum SessionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case desktop
    case remoteApp
    case appLauncher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "完整桌面（推荐）"
        case .remoteApp: "RemoteApp（仅 Windows Server/RDS）"
        case .appLauncher: "应用启动（实验，完整会话）"
        }
    }
}

enum NetworkProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case lan
    case auto
    case wan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lan: "局域网"
        case .auto: "自动"
        case .wan: "外网"
        }
    }

    var freeRDPValue: String { rawValue }
}

enum FrameAcknowledgement: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case one
    case two
    case four

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "默认（2）"
        case .one: "1 · 最低排队"
        case .two: "2 · 均衡"
        case .four: "4 · 视频吞吐"
        }
    }

    var value: Int? {
        switch self {
        case .automatic: nil
        case .one: 1
        case .two: 2
        case .four: 4
        }
    }
}

enum ExperiencePreset: String, CaseIterable, Identifiable, Sendable {
    case fastest
    case balanced
    case video
    case quality

    var id: String { rawValue }

    /// Only expose presets that produced a material difference in user A/B
    /// testing. The legacy 4K low-latency and video cases remain decodable for
    /// saved configurations and regression tests.
    static let userFacingCases: [ExperiencePreset] = [.quality, .balanced]

    var title: String {
        switch self {
        case .fastest: "4K 旧低延迟（已合并）"
        case .balanced: "3K 流畅 / 外网"
        case .video: "3K 旧视频模式（已合并）"
        case .quality: "4K 日常（推荐）"
        }
    }

    var subtitle: String {
        switch self {
        case .fastest: "与 4K 日常实测无可见差异"
        case .balanced: "像素减少约 44% · 唯一实测可减负的路线"
        case .video: "4K 视频仍请使用 Windows App"
        case .quality: "AVC444v2 · 清晰文字与交互动画"
        }
    }
}

struct ConnectionConfiguration: Codable, Equatable, Sendable {
    var host = "windows-host.example"
    var port = 3389
    var username = ""
    var domain = ""
    var resolution = ResolutionPreset.balanced
    var graphicsMode = GraphicsMode.avc420
    var sessionMode = SessionMode.desktop
    var remoteAppProgram = ""
    var remoteAppCommandLine = ""
    var remoteAppWorkingDirectory = ""
    var networkProfile = NetworkProfile.lan
    var fullscreen = true
    var dynamicResolution = false
    var clipboard = true
    var audio = true
    var microphone = false
    var visualEffects = false
    var allowUDP = false
    var autoReconnect = true
    var asynchronousUpdate = false
    var asynchronousChannels = true
    var verticalSync = false
    var frameAcknowledgement = FrameAcknowledgement.one

    static let defaultsKey = "connection-configuration-v1"

    var credentialAccount: String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(user)@\(host):\(port)"
    }

    mutating func apply(_ preset: ExperiencePreset) {
        switch preset {
        case .fastest:
            resolution = .native
            graphicsMode = .avc420
            audio = false
            microphone = false
            visualEffects = false
            asynchronousUpdate = false
            asynchronousChannels = true
            verticalSync = false
            frameAcknowledgement = .one
        case .balanced:
            resolution = .balanced
            graphicsMode = .avc420
            audio = true
            microphone = false
            visualEffects = false
            asynchronousUpdate = false
            asynchronousChannels = true
            verticalSync = true
            frameAcknowledgement = .two
        case .video:
            resolution = .balanced
            graphicsMode = .avc420
            audio = true
            microphone = false
            visualEffects = false
            asynchronousUpdate = false
            asynchronousChannels = true
            verticalSync = true
            frameAcknowledgement = .four
        case .quality:
            resolution = .native
            graphicsMode = .avc444
            audio = true
            microphone = false
            visualEffects = false
            asynchronousUpdate = false
            asynchronousChannels = true
            verticalSync = true
            frameAcknowledgement = .two
        }
    }

    mutating func migrateLatencyTuningToVersion4() {
        asynchronousChannels = true
        switch graphicsMode {
        case .video:
            asynchronousUpdate = true
            verticalSync = true
            frameAcknowledgement = .four
        case .avc444:
            asynchronousUpdate = false
            verticalSync = true
            frameAcknowledgement = .two
        case .avc420:
            asynchronousUpdate = true
            verticalSync = !(resolution == .native && !audio)
            frameAcknowledgement = verticalSync ? .two : .one
        case .automatic:
            asynchronousUpdate = true
            verticalSync = true
            frameAcknowledgement = .two
        }
    }

    /// FreeRDP 3.30's SDL client currently forces async-update off. Our A/B
    /// runs also found that the dedicated video channel was not selected for
    /// the desktop workload, while AVC444 negotiated AVC444v2 and used
    /// VideoToolbox. Persist those measured defaults once without overriding
    /// later user choices.
    mutating func migrateMeasuredTuningToVersion5() {
        asynchronousUpdate = false
        if graphicsMode == .video {
            graphicsMode = .avc444
            verticalSync = true
            frameAcknowledgement = .four
        }
    }

    /// User validation found the FreeRDP client smoother for UI animation but
    /// materially worse than Windows App for 4K video. FreeRDP 3.30 also
    /// advertises multitransport while its client callback rejects UDP, and
    /// RemoteApp/alternate-shell sessions were black on this Windows Pro host.
    mutating func migrateValidatedProductProfileToVersion6() {
        allowUDP = false
        sessionMode = .desktop
        if resolution == .native && frameAcknowledgement == .four {
            resolution = .balanced
            graphicsMode = .avc420
            frameAcknowledgement = .two
        }
    }

    /// The user could not distinguish the legacy 4K AVC420/ACK1 profile from
    /// 4K AVC444v2/ACK2, and short-run CPU/RSS samples were effectively equal.
    /// Fold the exact old profile into the clearer 4K daily profile once.
    mutating func migrateRedundant4KPresetToVersion7() {
        if resolution == .native &&
            graphicsMode == .avc420 &&
            frameAcknowledgement == .one &&
            !audio {
            apply(.quality)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, username, domain, resolution, graphicsMode
        case sessionMode, remoteAppProgram, remoteAppCommandLine, remoteAppWorkingDirectory
        case networkProfile, fullscreen, dynamicResolution, clipboard, audio, microphone
        case visualEffects, allowUDP, autoReconnect, asynchronousUpdate, asynchronousChannels
        case verticalSync, frameAcknowledgement
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        host = try values.decodeIfPresent(String.self, forKey: .host) ?? host
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? port
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? username
        domain = try values.decodeIfPresent(String.self, forKey: .domain) ?? domain
        resolution = try values.decodeIfPresent(ResolutionPreset.self, forKey: .resolution) ?? resolution
        graphicsMode = try values.decodeIfPresent(GraphicsMode.self, forKey: .graphicsMode) ?? graphicsMode
        sessionMode = try values.decodeIfPresent(SessionMode.self, forKey: .sessionMode) ?? sessionMode
        remoteAppProgram = try values.decodeIfPresent(String.self, forKey: .remoteAppProgram) ?? remoteAppProgram
        remoteAppCommandLine = try values.decodeIfPresent(String.self, forKey: .remoteAppCommandLine) ?? remoteAppCommandLine
        remoteAppWorkingDirectory = try values.decodeIfPresent(String.self, forKey: .remoteAppWorkingDirectory) ?? remoteAppWorkingDirectory
        networkProfile = try values.decodeIfPresent(NetworkProfile.self, forKey: .networkProfile) ?? networkProfile
        fullscreen = try values.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? fullscreen
        dynamicResolution = try values.decodeIfPresent(Bool.self, forKey: .dynamicResolution) ?? dynamicResolution
        clipboard = try values.decodeIfPresent(Bool.self, forKey: .clipboard) ?? clipboard
        audio = try values.decodeIfPresent(Bool.self, forKey: .audio) ?? audio
        microphone = try values.decodeIfPresent(Bool.self, forKey: .microphone) ?? microphone
        visualEffects = try values.decodeIfPresent(Bool.self, forKey: .visualEffects) ?? visualEffects
        allowUDP = try values.decodeIfPresent(Bool.self, forKey: .allowUDP) ?? allowUDP
        autoReconnect = try values.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? autoReconnect
        asynchronousUpdate = try values.decodeIfPresent(Bool.self, forKey: .asynchronousUpdate) ?? asynchronousUpdate
        asynchronousChannels = try values.decodeIfPresent(Bool.self, forKey: .asynchronousChannels) ?? asynchronousChannels
        verticalSync = try values.decodeIfPresent(Bool.self, forKey: .verticalSync) ?? verticalSync
        frameAcknowledgement = try values.decodeIfPresent(FrameAcknowledgement.self, forKey: .frameAcknowledgement) ?? frameAcknowledgement
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let value = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return Self()
        }
        return value
    }
}
