import CoreWLAN
import Foundation

struct PingMetrics: Equatable, Sendable {
    let sent: Int
    let received: Int
    let lossPercent: Double
    let averageMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    let standardDeviationMilliseconds: Double

    var isUnstable: Bool {
        lossPercent > 0 || p95Milliseconds >= 35 || maximumMilliseconds >= 80 || standardDeviationMilliseconds >= 10
    }
}

struct WiFiLink: Equatable, Sendable {
    let band: String
    let channel: Int
    let rssi: Int
    let transmitRateMbps: Double
}

struct ProbeResult: Sendable {
    let reachable: Bool
    let latencyMilliseconds: Double
    let detail: String
    let gateway: String?
    let gatewayPing: PingMetrics?
    let targetPing: PingMetrics?
    let wifi: WiFiLink?

    var hasLANQualityIssue: Bool {
        gatewayPing?.isUnstable == true || targetPing?.isUnstable == true
    }

    var shortWarning: String {
        let source = gatewayPing ?? targetPing
        guard let source else { return "局域网质量异常" }
        let band = wifi.map { " · \($0.band)" } ?? ""
        return String(
            format: "局域网抖动%@ · 丢包 %.1f%% · P95 %.0f ms · 峰值 %.0f ms",
            band,
            source.lossPercent,
            source.p95Milliseconds,
            source.maximumMilliseconds
        )
    }

    var detailSummary: String {
        var parts: [String] = []
        if let wifi {
            parts.append(
                String(
                    format: "Wi‑Fi %@ · 信道 %d · RSSI %d dBm · 速率 %.0f Mbps",
                    wifi.band,
                    wifi.channel,
                    wifi.rssi,
                    wifi.transmitRateMbps
                )
            )
        }
        if let gatewayPing {
            parts.append(Self.metricsText("到网关", gatewayPing))
        }
        if let targetPing {
            parts.append(Self.metricsText("到 Windows", targetPing))
        }
        return parts.isEmpty ? "未取得丢包与抖动数据" : parts.joined(separator: "  |  ")
    }

    private static func metricsText(_ label: String, _ metrics: PingMetrics) -> String {
        String(
            format: "%@：丢包 %.1f%% · 均值 %.1f ms · P95 %.1f ms · 峰值 %.1f ms",
            label,
            metrics.lossPercent,
            metrics.averageMilliseconds,
            metrics.p95Milliseconds,
            metrics.maximumMilliseconds
        )
    }
}

enum NetworkProbe {
    static func run(
        host: String,
        port: Int,
        completion: @escaping @Sendable (ProbeResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let wifi = currentWiFiLink()
            let gateway = defaultGateway()
            let start = ContinuousClock.now
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-z", "-v", "-G", "3", host, String(port)]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let elapsed = start.duration(to: .now)
                let components = elapsed.components
                let milliseconds = Double(components.seconds) * 1_000
                    + Double(components.attoseconds) / 1_000_000_000_000_000
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let gatewayPing = gateway.flatMap { ping(host: $0) }
                let targetPing = ping(host: host)
                completion(ProbeResult(
                    reachable: process.terminationStatus == 0,
                    latencyMilliseconds: milliseconds,
                    detail: output,
                    gateway: gateway,
                    gatewayPing: gatewayPing,
                    targetPing: targetPing,
                    wifi: wifi
                ))
            } catch {
                completion(ProbeResult(
                    reachable: false,
                    latencyMilliseconds: 0,
                    detail: error.localizedDescription,
                    gateway: gateway,
                    gatewayPing: gateway.flatMap { ping(host: $0) },
                    targetPing: ping(host: host),
                    wifi: wifi
                ))
            }
        }
    }

    static func parsePingOutput(_ output: String) -> PingMetrics? {
        let packetPattern = #"([0-9]+) packets transmitted, ([0-9]+) packets received, ([0-9.]+)% packet loss"#
        let timingPattern = #"(?:round-trip|rtt) min/avg/max/(?:stddev|mdev) = ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ms"#

        guard
            let packet = captures(packetPattern, in: output), packet.count == 3,
            let timing = captures(timingPattern, in: output), timing.count == 4,
            let sent = Int(packet[0]),
            let received = Int(packet[1]),
            let loss = Double(packet[2]),
            let average = Double(timing[1]),
            let maximum = Double(timing[2]),
            let standardDeviation = Double(timing[3])
        else { return nil }

        return PingMetrics(
            sent: sent,
            received: received,
            lossPercent: loss,
            averageMilliseconds: average,
            p95Milliseconds: percentile95(from: output) ?? maximum,
            maximumMilliseconds: maximum,
            standardDeviationMilliseconds: standardDeviation
        )
    }

    static func gatewayAddress(from output: String) -> String? {
        output
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("gateway:") })?
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ping(host: String) -> PingMetrics? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "20", "-i", "0.2", host]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(
                decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            return parsePingOutput(output)
        } catch {
            return nil
        }
    }

    private static func defaultGateway() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return gatewayAddress(from: output)
    }

    private static func currentWiFiLink() -> WiFiLink? {
        guard
            let interface = CWWiFiClient.shared().interface(),
            let channel = interface.wlanChannel()
        else { return nil }

        let band: String
        switch channel.channelBand.rawValue {
        case 1: band = "2.4 GHz"
        case 2: band = "5 GHz"
        case 3: band = "6 GHz"
        default: band = "Wi‑Fi"
        }

        return WiFiLink(
            band: band,
            channel: channel.channelNumber,
            rssi: interface.rssiValue(),
            transmitRateMbps: interface.transmitRate()
        )
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            )
        else { return nil }

        return (1 ..< match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func percentile95(from output: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: #"time[=<]([0-9.]+) ms"#) else {
            return nil
        }
        let range = NSRange(output.startIndex..., in: output)
        let samples = expression.matches(in: output, range: range).compactMap { match -> Double? in
            guard let valueRange = Range(match.range(at: 1), in: output) else { return nil }
            return Double(output[valueRange])
        }.sorted()
        guard !samples.isEmpty else { return nil }
        let index = max(0, min(samples.count - 1, Int(ceil(Double(samples.count) * 0.95)) - 1))
        return samples[index]
    }
}
