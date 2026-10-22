import Foundation
import TunlCLICore

let version = "0.1.0"

let usage = """
usage: tunl <command> [name] [--json]

  status [name]      tunnels, and whether the connected one carries traffic
  events [name]      recent connects, drops, stalls and repairs
  connect <name>     connect and wait until it is up
  disconnect [name]  disconnect the connected tunnel
  repair [name]      reconnect a tunnel that is up but carrying nothing
  mcp                serve these commands to AI agents (MCP over stdio)
  version

Tunl must be installed from the App Store. Keys, endpoints and addresses are
never shown.
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let asJSON = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard let command = arguments.first else { fail(usage, code: ClientError.Code.usage.rawValue) }
let name = arguments.dropFirst().first
let client = TunlClient()

do {
    switch command {
    case "status", "list":
        let report = try client.status(name: name)
        print(asJSON ? Output.json(report) : Output.text(report))
    case "events":
        let events = try client.events(name: name)
        print(asJSON ? Output.json(events) : Output.text(events))
    case "connect":
        guard let name else { fail("usage: tunl connect <name>", code: ClientError.Code.usage.rawValue) }
        let report = try client.connect(name: name)
        print(asJSON ? Output.json(report) : Output.text(report))
    case "disconnect":
        if let report = try client.disconnect(name: name) {
            print(asJSON ? Output.json(report) : Output.text(report))
        } else if !asJSON {
            print("No tunnel was connected.")
        } else {
            print("null")
        }
    case "repair":
        let report = try client.repair(name: name)
        print(asJSON ? Output.json(report) : Output.text(report))
    case "mcp":
        MCPServer(client: client, version: version).serve()
    case "version", "--version":
        print(version)
    case "help", "--help", "-h":
        print(usage)
    default:
        fail(usage, code: ClientError.Code.usage.rawValue)
    }
} catch let error as ClientError {
    fail(error.description, code: error.code.rawValue)
} catch {
    fail(String(describing: error), code: 1)
}
