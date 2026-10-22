import Foundation

/// Everything the CLI asks of the Mac, behind one seam so the logic is tested
/// without a VPN, an app or a clock.
public protocol System {
    /// Runs a program and returns its standard output.
    func run(_ executable: String, _ arguments: [String]) throws -> String
    /// The status file the app writes, if there is one.
    func readStatusFile() -> Data?
    func isAppRunning() -> Bool
    func sleep(seconds: Double)
    func now() -> Date
}

public struct SystemError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// The real Mac.
public struct LiveSystem: System {
    public static let appBundleID = "works.kalle.tunl"

    public init() {}

    public func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SystemError("\(executable) exited with status \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func readStatusFile() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(Self.appBundleID)/Data/Library/Application Support/Tunl/status.json")
        return try? Data(contentsOf: url)
    }

    public func isAppRunning() -> Bool {
        (try? run("/usr/bin/pgrep", ["-x", "Tunl"])).map { !$0.isEmpty } ?? false
    }

    public func sleep(seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    public func now() -> Date { Date() }
}
