import Foundation

struct FreeRDPLaunchPlan: Equatable {
    let processArguments: [String]
    let standardInput: Data?
}

enum FreeRDPCommandBuilderError: LocalizedError, Equatable {
    case unsupportedLineBreak
    case unsupportedRemoteAppSeparator
    case missingRemoteAppProgram

    var errorDescription: String? {
        switch self {
        case .unsupportedLineBreak:
            "连接信息或密码不能包含换行符。"
        case .unsupportedRemoteAppSeparator:
            "RemoteApp 程序、参数和工作目录不能包含逗号。"
        case .missingRemoteAppProgram:
            "请输入 RemoteApp 已发布别名（例如 ||notepad）或程序路径。"
        }
    }
}

enum FreeRDPCommandBuilder {
    static var binaryCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/share/mac-low-latency-rdp/freerdp-3.30.0-videotoolbox/bin/sdl-freerdp",
            "\(home)/Library/Application Support/MacLowLatencyRDP/FreeRDP-3.30.0-VideoToolbox/bin/sdl-freerdp",
            "/opt/homebrew/bin/sdl-freerdp",
            "/usr/local/bin/sdl-freerdp",
            "/opt/local/bin/sdl-freerdp"
        ]
    }

    static func findBinary(fileManager: FileManager = .default) -> String? {
        binaryCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    static func arguments(
        for configuration: ConnectionConfiguration,
        passwordProvided: Bool
    ) -> [String] {
        var arguments = [
            "/v:\(configuration.host):\(configuration.port)",
            "/network:\(configuration.networkProfile.freeRDPValue)",
            "/cert:tofu",
            "/sec:nla",
            "/bpp:32",
            "/gdi:sw",
            "/w:\(configuration.resolution.dimensions.width)",
            "/h:\(configuration.resolution.dimensions.height)",
            "/t:Mac Low Latency RDP — \(configuration.host)",
            "/log-level:INFO",
            "/log-filters:com.freerdp.core.multitransport:DEBUG,com.freerdp.channels.rdpgfx.client:DEBUG,com.freerdp.codec:INFO,com.freerdp.channels.video.client:DEBUG,com.freerdp.channels.rail.client:DEBUG,com.freerdp.channels.drdynvc.client:INFO",
            "+heartbeat"
        ]

        arguments.append(configuration.asynchronousUpdate ? "+async-update" : "-async-update")
        arguments.append(configuration.asynchronousChannels ? "+async-channels" : "-async-channels")

        if let frameAcknowledgement = configuration.frameAcknowledgement.value {
            arguments.append("/frame-ack:\(frameAcknowledgement)")
        }

        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty {
            arguments.append("/u:\(username)")
        }

        let domain = configuration.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty {
            arguments.append("/d:\(domain)")
        }

        if passwordProvided {
            arguments.append("/from-stdin:force")
        } else {
            arguments.append("/p")
        }

        switch configuration.graphicsMode {
        case .avc420:
            arguments.append("/gfx:AVC420")
        case .avc444:
            arguments.append("/gfx:AVC444")
        case .video:
            arguments.append(contentsOf: ["/gfx:AVC420", "+video"])
        case .automatic:
            arguments.append("/gfx")
        }

        if configuration.sessionMode == .remoteApp {
            arguments.append("-f")
            var appComponents = ["program:\(configuration.remoteAppProgram.trimmingCharacters(in: .whitespacesAndNewlines))"]
            let commandLine = configuration.remoteAppCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !commandLine.isEmpty { appComponents.append("cmd:\(commandLine)") }
            let workingDirectory = configuration.remoteAppWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !workingDirectory.isEmpty { appComponents.append("workdir:\(workingDirectory)") }
            appComponents.append("hidef:on")
            arguments.append("/app:\(appComponents.joined(separator: ","))")
        } else {
            arguments.append(configuration.fullscreen ? "+f" : "-f")
            if configuration.sessionMode == .appLauncher {
                let program = configuration.remoteAppProgram.trimmingCharacters(in: .whitespacesAndNewlines)
                let commandLine = configuration.remoteAppCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)
                arguments.append("/shell:\(commandLine.isEmpty ? program : "\(program) \(commandLine)")")
                let workingDirectory = configuration.remoteAppWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
                if !workingDirectory.isEmpty { arguments.append("/shell-dir:\(workingDirectory)") }
            }
        }

        // SDL3 otherwise replaces /w and /h with the physical monitor size
        // during fullscreen pre-connect. Smart sizing keeps the requested
        // remote desktop resolution and scales it to the fullscreen window.
        if configuration.sessionMode != .remoteApp && configuration.fullscreen && !configuration.dynamicResolution {
            let size = configuration.resolution.dimensions
            arguments.append("/smart-sizing:\(size.width)x\(size.height)")
        }

        // Ask Windows to scale UI layout before rendering. At native 4K this
        // produces the same apparent size as 2K at 100%, without scaling a
        // completed 2K bitmap and blurring text.
        arguments.append("/scale-desktop:\(configuration.resolution.desktopScalePercent)")
        arguments.append("/scale-device:\(configuration.resolution.deviceScalePercent)")

        if configuration.sessionMode != .remoteApp && configuration.dynamicResolution {
            arguments.append(contentsOf: ["+disp", "+dynamic-resolution"])
        }

        arguments.append(configuration.clipboard ? "/clipboard" : "-clipboard")

        if configuration.audio {
            arguments.append("/audio-mode:redirect")
        } else {
            arguments.append("/audio-mode:none")
        }

        if configuration.microphone {
            arguments.append("/microphone:sys:mac")
        }

        if configuration.visualEffects {
            arguments.append(contentsOf: ["+wallpaper", "+themes", "+menu-anims", "+window-drag", "+fonts"])
        } else {
            arguments.append(contentsOf: ["-wallpaper", "-themes", "-menu-anims", "-window-drag", "+fonts"])
        }

        // FreeRDP 3.30's client-side multitransport callback responds E_ABORT
        // to the server's UDP request. Do not advertise a capability this
        // client cannot complete; actual UDP remains a Microsoft Windows App
        // path until upstream implements RDP-UDP/DTLS on the client.
        arguments.append("-multitransport")

        if configuration.autoReconnect {
            arguments.append(contentsOf: ["+auto-reconnect", "/auto-reconnect-max-retries:5"])
        } else {
            arguments.append("-auto-reconnect")
        }

        return arguments
    }

    static func launchPlan(
        for configuration: ConnectionConfiguration,
        password: String
    ) throws -> FreeRDPLaunchPlan {
        if configuration.sessionMode != .desktop {
            guard !configuration.remoteAppProgram.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FreeRDPCommandBuilderError.missingRemoteAppProgram
            }
        }
        if configuration.sessionMode == .remoteApp {
            let values = [
                configuration.remoteAppProgram,
                configuration.remoteAppCommandLine,
                configuration.remoteAppWorkingDirectory
            ]
            guard values.allSatisfy({ !$0.contains(",") }) else {
                throw FreeRDPCommandBuilderError.unsupportedRemoteAppSeparator
            }
        }
        let interactiveArguments = arguments(for: configuration, passwordProvided: false)
        guard interactiveArguments.allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }) else {
            throw FreeRDPCommandBuilderError.unsupportedLineBreak
        }

        if password.isEmpty {
            return FreeRDPLaunchPlan(
                processArguments: interactiveArguments,
                standardInput: nil
            )
        }

        var pipedArguments = interactiveArguments
        pipedArguments.removeAll(where: { $0 == "/p" })
        pipedArguments.append("/p:\(password)")

        guard pipedArguments.allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }) else {
            throw FreeRDPCommandBuilderError.unsupportedLineBreak
        }

        // FreeRDP officially supports one argument per stdin line. Only
        // /args-from:stdin appears in the process list; the credential does not.
        let payload = (pipedArguments.joined(separator: "\n") + "\n").data(using: .utf8)
        return FreeRDPLaunchPlan(
            processArguments: ["/args-from:stdin"],
            standardInput: payload
        )
    }

    static func redactedCommand(
        binary: String,
        configuration: ConnectionConfiguration,
        passwordProvided: Bool
    ) -> String {
        ([binary] + arguments(for: configuration, passwordProvided: passwordProvided))
            .map(shellQuoted)
            .joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || "'\"\\$`".contains($0) }) else {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
