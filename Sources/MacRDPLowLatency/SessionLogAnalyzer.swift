import Foundation

enum TransportState: String, Sendable {
    case waiting = "等待协商"
    case tcp = "TCP"
    case udp = "UDP 已协商"
}

struct SessionSignals: Equatable, Sendable {
    var transport = TransportState.waiting
    var graphics = "等待协商"
    var connected = false
    var hardwareDecode = false
    var videoChannel = false
    var overriddenDesktopSize: String?
    private var sawClearCodec = false
    private var sawProgressive = false

    @discardableResult
    mutating func observeSocketTable(_ output: String, host: String) -> TransportState? {
        let matchingLines = output.split(whereSeparator: \.isNewline).filter {
            $0.localizedCaseInsensitiveContains(host)
        }
        if matchingLines.contains(where: { $0.localizedCaseInsensitiveContains("UDP") }) {
            transport = .udp
            return .udp
        }
        if matchingLines.contains(where: { $0.localizedCaseInsensitiveContains("TCP") }) {
            transport = .tcp
            return .tcp
        }
        return nil
    }

    mutating func consume(_ line: String) {
        let normalized = line.lowercased()

        if normalized.contains("udp") &&
            (normalized.contains("success") || normalized.contains("connected") || normalized.contains("established")) &&
            !normalized.contains("fail") && !normalized.contains("error") {
            transport = .udp
        } else if normalized.contains("tcp") || normalized.contains("transport_connect") {
            if transport != .udp { transport = .tcp }
        }

        let isSurfaceCodec = normalized.contains("rdpgfx_codecid_") ||
            normalized.contains("got gfx")

        if isSurfaceCodec && normalized.contains("avc444v2") {
            graphics = "AVC444v2"
        } else if isSurfaceCodec && normalized.contains("avc444") {
            graphics = "AVC444"
        } else if isSurfaceCodec && normalized.contains("avc420") {
            graphics = "AVC420 / H.264"
        } else if isSurfaceCodec && normalized.contains("clearcodec") {
            sawClearCodec = true
            updateFallbackGraphicsLabel()
        } else if isSurfaceCodec && normalized.contains("progressive") {
            sawProgressive = true
            updateFallbackGraphicsLabel()
        } else if normalized.contains("rdpgfx") || normalized.contains("gfx") {
            if graphics == "等待协商" { graphics = "RDPGFX" }
        }

        if normalized.contains("using videotoolbox for accelerated h264 decoding") {
            hardwareDecode = true
        }

        if normalized.contains("microsoft::windows::rds::video") ||
            normalized.contains("presentationreq:") ||
            normalized.contains("video_videodata") {
            videoChannel = true
        }

        if let range = normalized.range(
            of: #"update size to [0-9]+x[0-9]+"#,
            options: .regularExpression
        ) {
            overriddenDesktopSize = String(normalized[range])
                .replacingOccurrences(of: "update size to ", with: "")
        }

        if normalized.contains("connected to") ||
            normalized.contains("post_connect") ||
            normalized.contains("connection established") {
            connected = true
            if transport == .waiting { transport = .tcp }
        }
    }

    private mutating func updateFallbackGraphicsLabel() {
        guard !graphics.hasPrefix("AVC") else { return }
        if sawClearCodec && sawProgressive {
            graphics = "ClearCodec + Progressive"
        } else if sawClearCodec {
            graphics = "ClearCodec"
        } else if sawProgressive {
            graphics = "Progressive"
        }
    }
}
