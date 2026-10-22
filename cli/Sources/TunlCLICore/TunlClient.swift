import Foundation

/// One tunnel as the CLI reports it: the system's word on whether it is up,
/// and, when the app can vouch for it, whether it actually carries traffic.
public struct TunnelReport: Codable, Equatable {
    public var name: String
    public var status: String
    public var autoReconnect: Bool?
    /// "healthy", "connecting", "noTraffic", "recovering", "stalled" or
    /// "unknown". Absent when the tunnel is down or the app is not running.
    public var health: String?
    public var latencyMs: Double?
    public var lastHandshakeSecondsAgo: Double?
    public var receivedBytes: UInt64?
    public var sentBytes: UInt64?
}

public struct StatusReport: Codable, Equatable {
    public var appRunning: Bool
    /// Why health is missing, when it is; written for an agent to relay.
    public var note: String?
    public var tunnels: [TunnelReport]
}

public struct EventReport: Codable, Equatable {
    public var tunnel: String
    public var at: Date
    public var kind: String
    public var detail: String?
}

public struct ClientError: Error, Equatable, CustomStringConvertible {
    public enum Code: Int32 { case usage = 64, notFound = 66, unavailable = 69, timeout = 75 }
    public let code: Code
    public let description: String
}

/// The commands, independent of how they are invoked (terminal or MCP).
public struct TunlClient {
    private let system: System

    public init(system: System = LiveSystem()) {
        self.system = system
    }

    // MARK: - Reading

    public func status(name: String? = nil) throws -> StatusReport {
        let services = try Scutil.tunlServices(fromList: system.run("/usr/sbin/scutil", ["--nc", "list"]))
        let appRunning = system.isAppRunning()
        let file = system.readStatusFile().flatMap(AgentStatus.decoded(from:))
            .flatMap { $0.schema <= AgentStatus.supportedSchema ? $0 : nil }
        var reports = services.map { service -> TunnelReport in
            let status = Scutil.normalized(service.status)
            let known = file?.tunnels.first { $0.name == service.name }
            // Health is only as good as the app that measured it: a file left
            // by an app that has since quit describes a moment that is over.
            let live = appRunning && status == "connected" && known?.status == "connected"
            return TunnelReport(
                name: service.name, status: status, autoReconnect: known?.autoReconnect,
                health: live ? known?.health : nil,
                latencyMs: live ? known?.latencyMs : nil,
                lastHandshakeSecondsAgo: live ? known?.lastHandshakeSecondsAgo : nil,
                receivedBytes: live ? known?.receivedBytes : nil,
                sentBytes: live ? known?.sentBytes : nil)
        }
        if let name {
            reports = reports.filter { $0.name == name }
            if reports.isEmpty { throw notFound(name, among: services) }
        }
        let anyUp = reports.contains { $0.status == "connected" }
        let note: String?
        if anyUp && !appRunning {
            note = "Tunl is not running, so whether the tunnel carries traffic is unknown. Open Tunl to measure it."
        } else if anyUp && file == nil {
            note = "Tunl has not written its status yet. Update Tunl, or open it once."
        } else {
            note = nil
        }
        return StatusReport(appRunning: appRunning, note: note, tunnels: reports)
    }

    public func events(name: String? = nil) throws -> [EventReport] {
        guard let file = system.readStatusFile().flatMap(AgentStatus.decoded(from:)) else {
            throw ClientError(code: .unavailable, description: "No history yet: Tunl has not written its status. Open Tunl once.")
        }
        let tunnels = name.map { n in file.tunnels.filter { $0.name == n } } ?? file.tunnels
        if let name, tunnels.isEmpty {
            throw ClientError(code: .notFound, description: "No tunnel called \"\(name)\".")
        }
        return tunnels
            .flatMap { t in t.recentEvents.map { EventReport(tunnel: t.name, at: $0.at, kind: $0.kind, detail: $0.detail) } }
            .sorted { $0.at > $1.at }
    }

    // MARK: - Acting

    /// Connecting goes through the app, never straight to scutil: the app
    /// stops the other tunnel first, re-applies auto-reconnect and the
    /// network protection, and records the history. A connect that skipped
    /// those would leave two tunnels fighting or a kill switch unapplied.
    public func connect(name: String, timeout: Double = 20) throws -> TunnelReport {
        try requireTunnel(name)
        try open(action: "connect", name: name)
        return try wait(for: name, until: "connected", timeout: timeout)
    }

    public func disconnect(name: String? = nil, timeout: Double = 20) throws -> TunnelReport? {
        let up = try status().tunnels.filter { $0.status != "disconnected" && $0.status != "invalid" }
        let target: String
        if let name {
            guard up.contains(where: { $0.name == name }) else {
                try requireTunnel(name)
                return try status(name: name).tunnels.first
            }
            target = name
        } else {
            guard let active = up.first else { return nil }
            target = active.name
        }
        try open(action: "disconnect", name: nil)
        return try wait(for: target, until: "disconnected", timeout: timeout)
    }

    /// Reconnects a tunnel that is up but carrying nothing.
    public func repair(name: String? = nil) throws -> TunnelReport {
        let connected = try status().tunnels.filter { $0.status == "connected" }
        guard let target = name ?? connected.first?.name else {
            throw ClientError(code: .unavailable, description: "No tunnel is connected, so there is nothing to repair. Connect one instead.")
        }
        guard connected.contains(where: { $0.name == target }) else {
            try requireTunnel(target)
            throw ClientError(code: .unavailable, description: "\"\(target)\" is not connected, so there is nothing to repair. Connect it instead.")
        }
        try open(action: "repair", name: target)
        return try wait(for: target, until: "connected", timeout: 30, settle: 3)
    }

    // MARK: - Helpers

    private func requireTunnel(_ name: String) throws {
        let services = try Scutil.tunlServices(fromList: system.run("/usr/sbin/scutil", ["--nc", "list"]))
        guard services.contains(where: { $0.name == name }) else { throw notFound(name, among: services) }
    }

    private func notFound(_ name: String, among services: [Scutil.Service]) -> ClientError {
        let names = services.map { "\"\($0.name)\"" }.joined(separator: ", ")
        return ClientError(code: .notFound, description: services.isEmpty
            ? "No tunnel called \"\(name)\": Tunl has no tunnels."
            : "No tunnel called \"\(name)\". Tunl has: \(names).")
    }

    /// Hands an action to the app through its URL scheme, in the background so
    /// it never steals focus from whoever is typing.
    private func open(action: String, name: String?) throws {
        var components = URLComponents()
        components.scheme = "tunl"
        components.host = action
        components.queryItems = name.map { [URLQueryItem(name: "name", value: $0)] }
        guard let url = components.url?.absoluteString else {
            throw ClientError(code: .usage, description: "Could not build the request for \(action).")
        }
        do {
            _ = try system.run("/usr/bin/open", ["-g", url])
        } catch {
            throw ClientError(code: .unavailable, description: "Could not reach Tunl. Is it installed from the App Store?")
        }
    }

    /// Polls until the tunnel reaches `target`. `settle` first waits that
    /// long, for actions (repair) whose end state is also their start state.
    private func wait(for name: String, until target: String, timeout: Double, settle: Double = 0) throws -> TunnelReport {
        if settle > 0 { system.sleep(seconds: settle) }
        let deadline = system.now().addingTimeInterval(timeout)
        var last: TunnelReport?
        repeat {
            last = try status(name: name).tunnels.first
            if last?.status == target { return last! }
            system.sleep(seconds: 0.5)
        } while system.now() < deadline
        throw ClientError(code: .timeout, description:
            "\"\(name)\" did not become \(target) within \(Int(timeout)) s (it is \(last?.status ?? "unknown")).")
    }
}
