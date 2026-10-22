import Foundation

/// `tunl mcp`: the same commands as Model Context Protocol tools over stdio,
/// one JSON-RPC message per line.
public struct MCPServer {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let client: TunlClient
    private let version: String

    public init(client: TunlClient, version: String) {
        self.client = client
        self.version = version
    }

    /// Serves until standard input closes.
    public func serve(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        while let line = readLine(strippingNewline: true) {
            guard let reply = handle(line: line) else { continue }
            output.write(reply + Data("\n".utf8))
        }
    }

    /// One incoming message to its reply, or nil for a notification.
    public func handle(line: String) -> Data? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(),
                                "error": ["code": -32700, "message": "Parse error"]])
        }
        // A message without an id is a notification and gets no reply.
        guard let id = message["id"] else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0]
            return reply(id, [
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "tunl", "version": self.version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return reply(id, [String: Any]())
        case "tools/list":
            return reply(id, ["tools": Self.tools])
        case "tools/call":
            return reply(id, call(params["name"] as? String ?? "",
                                  arguments: params["arguments"] as? [String: Any] ?? [:]))
        default:
            return Self.encode(["jsonrpc": "2.0", "id": id,
                                "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private static let instructions = """
    Controls Tunl, a WireGuard VPN client for macOS. Only one tunnel is connected at a time; \
    connecting one disconnects the other. A tunnel can be "connected" yet carry nothing: check \
    `health` in tunl_status ("noTraffic" or "stalled" means broken) and use tunl_repair. \
    These tools never reveal keys, endpoints or addresses.
    """

    private static let nameProperty: [String: Any] = ["type": "string", "description": "The tunnel's name, as tunl_status lists it."]

    static let tools: [[String: Any]] = [
        tool("tunl_status", "List Tunl's tunnels with whether each is up and, for the connected one, whether it actually carries traffic (health, latency, last handshake).",
             properties: ["name": nameProperty], required: [], readOnly: true),
        tool("tunl_events", "Recent connection history: connects, drops, stalls and repairs, newest first.",
             properties: ["name": nameProperty], required: [], readOnly: true),
        tool("tunl_connect", "Connect a tunnel by name and wait until it is up. Disconnects any other tunnel first.",
             properties: ["name": nameProperty], required: ["name"], readOnly: false),
        tool("tunl_disconnect", "Disconnect the connected tunnel (or the named one, if it is the connected one).",
             properties: ["name": nameProperty], required: [], readOnly: false),
        tool("tunl_repair", "Reconnect a tunnel that is connected but carrying no traffic. Defaults to the connected tunnel.",
             properties: ["name": nameProperty], required: [], readOnly: false),
    ]

    private static func tool(_ name: String, _ description: String, properties: [String: Any],
                             required: [String], readOnly: Bool) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required],
         "annotations": ["readOnlyHint": readOnly, "openWorldHint": false]]
    }

    /// A tool's result. Failures are results with `isError`, not protocol
    /// errors, so the agent sees the message and can act on it.
    private func call(_ name: String, arguments: [String: Any]) -> [String: Any] {
        let tunnel = (arguments["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        do {
            let value: any Encodable
            switch name {
            case "tunl_status": value = try client.status(name: tunnel)
            case "tunl_events": value = try client.events(name: tunnel)
            case "tunl_connect":
                guard let tunnel else { throw ClientError(code: .usage, description: "tunl_connect needs a tunnel name.") }
                value = try client.connect(name: tunnel)
            case "tunl_disconnect":
                value = try client.disconnect(name: tunnel)
                    ?? StatusReport(appRunning: true, note: "No tunnel was connected.", tunnels: [])
            case "tunl_repair": value = try client.repair(name: tunnel)
            default: throw ClientError(code: .usage, description: "Unknown tool: \(name)")
            }
            let json = Output.json(value)
            var result: [String: Any] = ["content": [["type": "text", "text": json]], "isError": false]
            if let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                result["structuredContent"] = object
            }
            return result
        } catch {
            return ["content": [["type": "text", "text": String(describing: error)]], "isError": true]
        }
    }

    private func reply(_ id: Any, _ result: [String: Any]) -> Data? {
        Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
