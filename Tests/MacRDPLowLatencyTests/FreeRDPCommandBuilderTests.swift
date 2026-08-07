import XCTest
@testable import MacRDPLowLatency

final class FreeRDPCommandBuilderTests: XCTestCase {
    func testBalancedArgumentsUseSecureStdinAndLowLatencyDefaults() {
        var configuration = ConnectionConfiguration()
        configuration.username = "tester"

        let arguments = FreeRDPCommandBuilder.arguments(
            for: configuration,
            passwordProvided: true
        )

        XCTAssertTrue(arguments.contains("/v:windows-host.example:3389"))
        XCTAssertTrue(arguments.contains("/network:lan"))
        XCTAssertTrue(arguments.contains("/from-stdin:force"))
        XCTAssertTrue(arguments.contains("-async-update"))
        XCTAssertTrue(arguments.contains("+async-channels"))
        XCTAssertTrue(arguments.contains("/frame-ack:1"))
        XCTAssertTrue(arguments.contains("/gfx:AVC420"))
        XCTAssertTrue(arguments.contains("/w:3072"))
        XCTAssertTrue(arguments.contains("/h:1288"))
        XCTAssertTrue(arguments.contains("/smart-sizing:3072x1288"))
        XCTAssertTrue(arguments.contains("/scale-desktop:150"))
        XCTAssertTrue(arguments.contains("/scale-device:140"))
        XCTAssertFalse(arguments.contains(where: { $0.hasPrefix("/p:") }))
        XCTAssertTrue(arguments.contains("-multitransport"))
        XCTAssertFalse(arguments.contains("+multitransport"))
    }

    func testRetinaLowLatencyPresetUsesNativePixelsAtTwoHundredPercent() {
        var configuration = ConnectionConfiguration()
        configuration.apply(.fastest)

        let arguments = FreeRDPCommandBuilder.arguments(
            for: configuration,
            passwordProvided: false
        )

        XCTAssertTrue(arguments.contains("+f"))
        XCTAssertTrue(arguments.contains("/w:4096"))
        XCTAssertTrue(arguments.contains("/h:1716"))
        XCTAssertTrue(arguments.contains("/smart-sizing:4096x1716"))
        XCTAssertTrue(arguments.contains("/scale-desktop:200"))
        XCTAssertTrue(arguments.contains("/scale-device:180"))
    }

    func testDynamicResolutionDoesNotCompeteWithSmartSizing() {
        var configuration = ConnectionConfiguration()
        configuration.dynamicResolution = true

        let arguments = FreeRDPCommandBuilder.arguments(
            for: configuration,
            passwordProvided: false
        )

        XCTAssertTrue(arguments.contains("+dynamic-resolution"))
        XCTAssertFalse(arguments.contains(where: { $0.hasPrefix("/smart-sizing:") }))
    }

    func testSecureLaunchPipesAllArgumentsAndHidesPasswordFromProcessList() throws {
        var configuration = ConnectionConfiguration()
        configuration.username = "tester"
        let password = "a password:$`with symbols"

        let plan = try FreeRDPCommandBuilder.launchPlan(
            for: configuration,
            password: password
        )

        XCTAssertEqual(plan.processArguments, ["/args-from:stdin"])
        XCTAssertFalse(plan.processArguments.joined().contains(password))
        let payload = String(decoding: try XCTUnwrap(plan.standardInput), as: UTF8.self)
        XCTAssertTrue(payload.contains("/p:\(password)\n"))
        XCTAssertTrue(payload.contains("-async-update\n"))
        XCTAssertFalse(payload.contains("/from-stdin"))
    }

    func testSecureLaunchRejectsLineBreakInjection() {
        XCTAssertThrowsError(
            try FreeRDPCommandBuilder.launchPlan(
                for: ConnectionConfiguration(),
                password: "secret\n/inject"
            )
        ) { error in
            XCTAssertEqual(
                error as? FreeRDPCommandBuilderError,
                .unsupportedLineBreak
            )
        }
    }

    func testInteractiveLaunchRejectsLineBreakInjection() {
        var configuration = ConnectionConfiguration()
        configuration.host = "safe.example\n/inject"

        XCTAssertThrowsError(
            try FreeRDPCommandBuilder.launchPlan(for: configuration, password: "")
        ) { error in
            XCTAssertEqual(error as? FreeRDPCommandBuilderError, .unsupportedLineBreak)
        }
    }

    func testEmptyPasswordKeepsInteractivePromptWithoutInputPipe() throws {
        let plan = try FreeRDPCommandBuilder.launchPlan(
            for: ConnectionConfiguration(),
            password: ""
        )

        XCTAssertTrue(plan.processArguments.contains("/p"))
        XCTAssertNil(plan.standardInput)
    }

    func testNoPasswordSilencesPromptWithoutSecretArgument() {
        let arguments = FreeRDPCommandBuilder.arguments(
            for: ConnectionConfiguration(),
            passwordProvided: false
        )

        XCTAssertTrue(arguments.contains("/p"))
        XCTAssertFalse(arguments.contains("/from-stdin:force"))
    }

    func testRetinaLowLatencyPresetKeepsNativeResolutionAndCutsAudio() {
        var configuration = ConnectionConfiguration()
        configuration.apply(.fastest)

        XCTAssertEqual(configuration.resolution, .native)
        XCTAssertEqual(configuration.graphicsMode, .avc420)
        XCTAssertFalse(configuration.audio)
        XCTAssertFalse(configuration.visualEffects)
    }

    func testPingParserFindsPacketLossAndJitter() throws {
        let output = """
        64 bytes from 192.0.2.1: icmp_seq=0 ttl=64 time=2.5 ms
        64 bytes from 192.0.2.1: icmp_seq=1 ttl=64 time=113.269 ms
        100 packets transmitted, 96 packets received, 4.0% packet loss
        round-trip min/avg/max/stddev = 2.585/9.514/113.269/19.411 ms
        """

        let metrics = try XCTUnwrap(NetworkProbe.parsePingOutput(output))
        XCTAssertEqual(metrics.sent, 100)
        XCTAssertEqual(metrics.received, 96)
        XCTAssertEqual(metrics.lossPercent, 4.0)
        XCTAssertEqual(metrics.averageMilliseconds, 9.514)
        XCTAssertEqual(metrics.p95Milliseconds, 113.269)
        XCTAssertEqual(metrics.maximumMilliseconds, 113.269)
        XCTAssertTrue(metrics.isUnstable)
    }

    func testGatewayParserUsesRouteOutput() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.0.2.1
        """

        XCTAssertEqual(NetworkProbe.gatewayAddress(from: output), "192.0.2.1")
    }

    func testQualityPresetUsesNativeAVC444() {
        var configuration = ConnectionConfiguration()
        configuration.apply(.quality)

        XCTAssertEqual(configuration.resolution, .native)
        XCTAssertEqual(configuration.graphicsMode, .avc444)
        XCTAssertFalse(configuration.visualEffects)
    }

    func testVideoCompatibilityPresetReducesSurfaceAndAvoidsExperimentalChannel() {
        var configuration = ConnectionConfiguration()
        configuration.apply(.video)

        let arguments = FreeRDPCommandBuilder.arguments(
            for: configuration,
            passwordProvided: false
        )

        XCTAssertEqual(configuration.resolution, .balanced)
        XCTAssertEqual(configuration.graphicsMode, .avc420)
        XCTAssertTrue(configuration.audio)
        XCTAssertFalse(configuration.visualEffects)
        XCTAssertTrue(arguments.contains("/gfx:AVC420"))
        XCTAssertFalse(arguments.contains("+video"))
        XCTAssertTrue(arguments.contains("/frame-ack:4"))
        XCTAssertTrue(arguments.contains(where: { $0.hasPrefix("/log-filters:") }))
    }

    func testRemoteAppBuildsStandardRailArgumentsWithoutFullscreen() throws {
        var configuration = ConnectionConfiguration()
        configuration.sessionMode = .remoteApp
        configuration.remoteAppProgram = "||notepad"
        configuration.remoteAppCommandLine = "notes.txt"
        configuration.remoteAppWorkingDirectory = "C:\\Users\\Public"

        let plan = try FreeRDPCommandBuilder.launchPlan(for: configuration, password: "")

        XCTAssertTrue(plan.processArguments.contains("-f"))
        XCTAssertFalse(plan.processArguments.contains("+f"))
        XCTAssertFalse(plan.processArguments.contains(where: { $0.hasPrefix("/smart-sizing:") }))
        XCTAssertTrue(plan.processArguments.contains(
            "/app:program:||notepad,cmd:notes.txt,workdir:C:\\Users\\Public,hidef:on"
        ))
    }

    func testRemoteAppRejectsMissingProgramAndCommaInjection() {
        var configuration = ConnectionConfiguration()
        configuration.sessionMode = .remoteApp

        XCTAssertThrowsError(try FreeRDPCommandBuilder.launchPlan(for: configuration, password: "")) {
            XCTAssertEqual($0 as? FreeRDPCommandBuilderError, .missingRemoteAppProgram)
        }

        configuration.remoteAppProgram = "||notepad,cmd:unexpected"
        XCTAssertThrowsError(try FreeRDPCommandBuilder.launchPlan(for: configuration, password: "")) {
            XCTAssertEqual($0 as? FreeRDPCommandBuilderError, .unsupportedRemoteAppSeparator)
        }
    }

    func testWindowsProAppLauncherUsesAlternateShell() throws {
        var configuration = ConnectionConfiguration()
        configuration.sessionMode = .appLauncher
        configuration.remoteAppProgram = "C:\\Windows\\System32\\notepad.exe"
        configuration.remoteAppCommandLine = "C:\\Users\\Public\\notes.txt"
        configuration.remoteAppWorkingDirectory = "C:\\Users\\Public"

        let plan = try FreeRDPCommandBuilder.launchPlan(for: configuration, password: "")

        XCTAssertTrue(plan.processArguments.contains(
            "/shell:C:\\Windows\\System32\\notepad.exe C:\\Users\\Public\\notes.txt"
        ))
        XCTAssertTrue(plan.processArguments.contains("/shell-dir:C:\\Users\\Public"))
        XCTAssertTrue(plan.processArguments.contains("+f"))
        XCTAssertFalse(plan.processArguments.contains(where: { $0.hasPrefix("/app:") }))
    }

    func testExternalNetworkProfileUsesWanHint() {
        var configuration = ConnectionConfiguration()
        configuration.networkProfile = .wan

        let arguments = FreeRDPCommandBuilder.arguments(for: configuration, passwordProvided: false)

        XCTAssertTrue(arguments.contains("/network:wan"))
    }

    func testLegacySavedConfigurationGetsNewLatencyDefaults() throws {
        let legacy = Data(#"{"host":"rdp.example","port":3390,"username":"tester","domain":"","resolution":"native","graphicsMode":"avc420","fullscreen":true,"dynamicResolution":false,"clipboard":true,"audio":false,"microphone":false,"visualEffects":false,"allowUDP":true,"autoReconnect":true}"#.utf8)

        let configuration = try JSONDecoder().decode(ConnectionConfiguration.self, from: legacy)

        XCTAssertEqual(configuration.host, "rdp.example")
        XCTAssertEqual(configuration.port, 3390)
        XCTAssertEqual(configuration.sessionMode, .desktop)
        XCTAssertEqual(configuration.networkProfile, .lan)
        XCTAssertFalse(configuration.asynchronousUpdate)
        XCTAssertTrue(configuration.asynchronousChannels)
        XCTAssertEqual(configuration.frameAcknowledgement, .one)
    }

    func testVideoConfigurationMigratesToSmoothThroughputSettings() {
        var configuration = ConnectionConfiguration()
        configuration.graphicsMode = .video
        configuration.verticalSync = false
        configuration.frameAcknowledgement = .one

        configuration.migrateLatencyTuningToVersion4()

        XCTAssertTrue(configuration.asynchronousUpdate)
        XCTAssertTrue(configuration.asynchronousChannels)
        XCTAssertTrue(configuration.verticalSync)
        XCTAssertEqual(configuration.frameAcknowledgement, .four)
    }

    func testMeasuredTuningMigratesExperimentalVideoToVerifiedAVC444() {
        var configuration = ConnectionConfiguration()
        configuration.graphicsMode = .video
        configuration.asynchronousUpdate = true

        configuration.migrateMeasuredTuningToVersion5()

        XCTAssertEqual(configuration.graphicsMode, .avc444)
        XCTAssertFalse(configuration.asynchronousUpdate)
        XCTAssertTrue(configuration.verticalSync)
        XCTAssertEqual(configuration.frameAcknowledgement, .four)
    }

    func testValidatedProductProfileDisablesUnsupportedFeatures() {
        var configuration = ConnectionConfiguration()
        configuration.allowUDP = true
        configuration.sessionMode = .remoteApp
        configuration.resolution = .native
        configuration.graphicsMode = .avc444
        configuration.frameAcknowledgement = .four

        configuration.migrateValidatedProductProfileToVersion6()

        XCTAssertFalse(configuration.allowUDP)
        XCTAssertEqual(configuration.sessionMode, .desktop)
        XCTAssertEqual(configuration.resolution, .balanced)
        XCTAssertEqual(configuration.graphicsMode, .avc420)
        XCTAssertEqual(configuration.frameAcknowledgement, .two)
    }

    func testRedundantLegacy4KPresetMigratesToDaily4K() {
        var configuration = ConnectionConfiguration()
        configuration.apply(.fastest)

        configuration.migrateRedundant4KPresetToVersion7()

        XCTAssertEqual(configuration.resolution, .native)
        XCTAssertEqual(configuration.graphicsMode, .avc444)
        XCTAssertEqual(configuration.frameAcknowledgement, .two)
        XCTAssertTrue(configuration.audio)
        XCTAssertEqual(ExperiencePreset.userFacingCases, [.quality, .balanced])
    }

    func testWindowsDiagnosticIsReadOnly() {
        let script = WindowsRDPDiagnostic.powerShell.lowercased()

        XCTAssertTrue(script.contains("get-winevent"))
        XCTAssertTrue(script.contains("avchardwareencodepreferred"))
        XCTAssertFalse(script.contains("set-itemproperty"))
        XCTAssertFalse(script.contains("new-netfirewallrule"))
        XCTAssertFalse(script.contains("remove-item"))
    }

    func testWindowsHardwareScriptIsScopedAndRecoverable() {
        let script = WindowsRDPHardware.enablePowerShell
        let lowercased = script.lowercased()

        XCTAssertTrue(script.contains("bEnumerateHWBeforeSW"))
        XCTAssertTrue(script.contains("AVCHardwareEncodePreferred"))
        XCTAssertTrue(script.contains("AVC444ModePreferred"))
        XCTAssertTrue(script.contains("policy-backup.json"))
        XCTAssertTrue(script.contains("Restore-RDPVideoHardware.ps1"))
        XCTAssertTrue(script.contains("reg.exe add"))
        XCTAssertTrue(script.contains("Get-ItemPropertyValue"))
        XCTAssertTrue(script.contains("verification failed"))
        XCTAssertFalse(lowercased.contains("new-netfirewallrule"))
        XCTAssertFalse(lowercased.contains("restart-computer"))
        XCTAssertFalse(lowercased.contains("shutdown.exe"))
    }

    func testWindows60FPSScriptIsScopedAndRecoverable() {
        let script = WindowsRDPFrameRate.enable60FPSPowerShell
        let lowercased = script.lowercased()

        XCTAssertTrue(script.contains("DWMFRAMEINTERVAL"))
        XCTAssertTrue(script.contains("/d 15"))
        XCTAssertTrue(script.contains("frame-rate-backup.json"))
        XCTAssertTrue(script.contains("Restore-RDP60FPS.ps1"))
        XCTAssertFalse(lowercased.contains("new-netfirewallrule"))
        XCTAssertFalse(lowercased.contains("restart-computer"))
        XCTAssertFalse(lowercased.contains("shutdown.exe"))
    }

    func testLogAnalyzerFindsNegotiatedSignals() {
        var signals = SessionSignals()
        signals.consume("transport_connect: TCP connection established")
        signals.consume("Got GFX RDPGFX_CODECID_AVC444")
        signals.consume("multitransport UDP connected successfully")
        signals.consume("Using VideoToolbox for accelerated H264 decoding")
        signals.consume("Microsoft::Windows::RDS::Video::Control::v08.01")

        XCTAssertEqual(signals.transport, .udp)
        XCTAssertEqual(signals.graphics, "AVC444")
        XCTAssertTrue(signals.connected)
        XCTAssertTrue(signals.hardwareDecode)
        XCTAssertTrue(signals.videoChannel)
    }

    func testLogAnalyzerReportsSurfaceCodecInsteadOfDecoderAvailability() {
        var signals = SessionSignals()
        signals.consume("Using VideoToolbox for accelerated H264 decoding")
        XCTAssertEqual(signals.graphics, "等待协商")

        signals.consume("Got GFX RDPGFX_CODECID_CLEARCODEC")
        XCTAssertEqual(signals.graphics, "ClearCodec")

        signals.consume("Got GFX RDPGFX_CODECID_CAPROGRESSIVE")
        XCTAssertEqual(signals.graphics, "ClearCodec + Progressive")
        XCTAssertTrue(signals.hardwareDecode)
    }

    func testLogAnalyzerDoesNotTreatUDPFailureAsSuccess() {
        var signals = SessionSignals()
        signals.consume("multitransport UDP connection failed")

        XCTAssertNotEqual(signals.transport, .udp)
    }

    func testLogAnalyzerExposesFullscreenResolutionOverride() {
        var signals = SessionSignals()
        signals.consume("[INFO][com.freerdp.client.SDL] - [preConnect]: Update size to 4096x1716")

        XCTAssertEqual(signals.overriddenDesktopSize, "4096x1716")
    }

    func testLogAnalyzerPrefersAVC444v2AndActualSocketTransport() {
        var signals = SessionSignals()
        signals.consume("RDPGFX_CODECID_AVC444v2")
        let socketTable = """
        sdl-freed 123 user 20u IPv4 TCP 192.0.2.171:51000->192.0.2.44:3389 (ESTABLISHED)
        """

        let observed = signals.observeSocketTable(socketTable, host: "192.0.2.44")

        XCTAssertEqual(signals.graphics, "AVC444v2")
        XCTAssertEqual(observed, .tcp)
        XCTAssertEqual(signals.transport, .tcp)
    }

    func testActualUDPSocketOverridesTCPTransport() {
        var signals = SessionSignals()
        let socketTable = """
        sdl-freed 123 user 20u IPv4 TCP 192.0.2.171:51000->192.0.2.44:3389 (ESTABLISHED)
        sdl-freed 123 user 21u IPv4 UDP 192.0.2.171:51001->192.0.2.44:3389
        """

        let observed = signals.observeSocketTable(socketTable, host: "192.0.2.44")

        XCTAssertEqual(observed, .udp)
        XCTAssertEqual(signals.transport, .udp)
    }
}
