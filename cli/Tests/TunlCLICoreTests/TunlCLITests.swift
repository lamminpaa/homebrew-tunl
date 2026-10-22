import XCTest
@testable import TunlCLICore

/// A Mac with Tunl's services, a status file and a clock, all scripted.
final class FakeSystem: System {
    var services: [(name: String, status: String)] = []
    var statusFile: Data?
    var appRunning = true
    var opened: [String] = []
    var ran: [[String]] = []
    /// What opening a URL does to the services, standing in for the app.
    var onOpen: (String, FakeSystem) -> Void = { _, _ in }
    private var clock = Date(timeIntervalSince1970: 0)

    func run(_ executable: String, _ arguments: [String]) throws -> String {
        ran.append([executable] + arguments)
        switch executable {
        case "/usr/sbin/scutil":
            return "Available network connection services in the current set (*=enabled):\n" + services.map {
                "* (\($0.status))   ABC VPN (works.kalle.tunl) \"\($0.name)\"   [VPN:works.kalle.tunl]"
            }.joined(separator: "\n")
        case "/usr/bin/open":
            opened.append(arguments.last ?? "")
            onOpen(arguments.last ?? "", self)
            return ""
        default:
            return ""
        }
    }

    func readStatusFile() -> Data? { statusFile }
    func isAppRunning() -> Bool { appRunning }
    func sleep(seconds: Double) { clock.addTimeInterval(seconds) }
    func now() -> Date { clock }
}

final class TunlCLITests: XCTestCase {
    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "status-v1", withExtension: "json",
                                                          subdirectory: "Fixtures")))
    }

    // MARK: - Reading the system and the app

    func testOnlyTunlsOwnServicesAreListedWithTheirNamesIntact() {
        let output = """
        Available network connection services in the current set (*=enabled):
        * (Disconnected)   F325 VPN (com.wireguard.macos) "Theirs"       [VPN:com.wireguard.macos]
        * (Connected)      B65B VPN (works.kalle.tunl) "Home "lab" (2)"       [VPN:works.kalle.tunl]
        * (Disconnected)   5DE8 PPP --> Modem "Modem"            [PPP:Modem]
        """
        XCTAssertEqual(Scutil.tunlServices(fromList: output),
                       [Scutil.Service(name: "Home \"lab\" (2)", status: "Connected")])
    }

    func testTheCLIReadsTheDocumentTheAppWrites() throws {
        let status = try XCTUnwrap(AgentStatus.decoded(from: fixture()))
        XCTAssertEqual(status.tunnels.first?.health, "noTraffic")
        XCTAssertEqual(status.tunnels.first?.recentEvents.last?.detail, "attempt 1 of 4")
    }

    func testHealthIsReportedOnlyWhileTheAppIsRunningToMeasureIt() throws {
        let system = FakeSystem()
        system.services = [("Home \"lab\"", "Connected")]
        system.statusFile = try fixture()
        XCTAssertEqual(try TunlClient(system: system).status().tunnels.first?.health, "noTraffic")

        system.appRunning = false
        let report = try TunlClient(system: system).status()
        XCTAssertNil(report.tunnels.first?.health, "a quit app's last reading was reported as current")
        XCTAssertNotNil(report.note, "an agent must be told why health is missing")
        XCTAssertEqual(report.tunnels.first?.status, "connected", "the system's own state still counts")
    }

    // MARK: - Acting goes through the app

    func testConnectAsksTheAppAndWaitsUntilTheTunnelIsUp() throws {
        let system = FakeSystem()
        system.services = [("Office", "Disconnected")]
        system.onOpen = { _, fake in fake.services = [("Office", "Connected")] }
        let report = try TunlClient(system: system).connect(name: "Office")
        XCTAssertEqual(report.status, "connected")
        XCTAssertEqual(system.opened, ["tunl://connect?name=Office"])
        XCTAssertFalse(system.ran.contains { $0.contains("start") },
                       "starting through scutil skips the app's single-tunnel rule and kill switch")
    }

    func testAConnectThatNeverComesUpTimesOutWithAnError() {
        let system = FakeSystem()
        system.services = [("Office", "Disconnected")]
        XCTAssertThrowsError(try TunlClient(system: system).connect(name: "Office", timeout: 5)) {
            XCTAssertEqual(($0 as? ClientError)?.code, .timeout)
        }
    }

    func testRepairRefusesATunnelThatIsNotUp() {
        let system = FakeSystem()
        system.services = [("Office", "Disconnected")]
        XCTAssertThrowsError(try TunlClient(system: system).repair(name: "Office"))
        XCTAssertTrue(system.opened.isEmpty)
    }

    // MARK: - MCP

    private func reply(_ server: MCPServer, _ line: String) throws -> [String: Any] {
        let data = try XCTUnwrap(server.handle(line: line))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMCPNegotiatesTheVersionAndListsTheTools() throws {
        let server = MCPServer(client: TunlClient(system: FakeSystem()), version: "0")
        let initialize = try reply(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        XCTAssertEqual((initialize["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#),
                     "a notification must get no reply")
        let list = try reply(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = ((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(Set(names ?? []), ["tunl_status", "tunl_events", "tunl_connect", "tunl_disconnect", "tunl_repair"])
    }

    func testAFailingToolIsAResultTheAgentCanReadNotAProtocolError() throws {
        let server = MCPServer(client: TunlClient(system: FakeSystem()), version: "0")
        let call = try reply(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tunl_connect","arguments":{"name":"Nope"}}}"#)
        XCTAssertNil(call["error"])
        let result = try XCTUnwrap(call["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("No tunnel called \"Nope\""), text)
    }
}
