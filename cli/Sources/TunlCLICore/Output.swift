import Foundation

public enum Output {
    public static func json(_ value: any Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    public static func text(_ report: StatusReport) -> String {
        guard !report.tunnels.isEmpty else { return "Tunl has no tunnels." }
        var lines = report.tunnels.map(text)
        if let note = report.note { lines += ["", note] }
        return lines.joined(separator: "\n")
    }

    public static func text(_ tunnel: TunnelReport) -> String {
        var line = "\(tunnel.name): \(tunnel.status)"
        var details: [String] = []
        if let health = tunnel.health { details.append(health) }
        if let latency = tunnel.latencyMs { details.append(String(format: "%.0f ms", latency)) }
        if let age = tunnel.lastHandshakeSecondsAgo { details.append("handshake \(Int(age)) s ago") }
        if tunnel.autoReconnect == true { details.append("auto-reconnect") }
        if !details.isEmpty { line += " (" + details.joined(separator: ", ") + ")" }
        return line
    }

    public static func text(_ events: [EventReport]) -> String {
        guard !events.isEmpty else { return "No history yet." }
        let format = ISO8601DateFormatter()
        return events.map { e in
            "\(format.string(from: e.at))  \(e.tunnel)  \(e.kind)" + (e.detail.map { " (\($0))" } ?? "")
        }.joined(separator: "\n")
    }
}
