import Foundation

/// Reads the system's own list of VPN services. Authoritative for whether a
/// tunnel is up, and works with the app closed.
public enum Scutil {
    public struct Service: Equatable {
        public var name: String
        /// As scutil words it: "Connected", "Disconnected", "Connecting"…
        public var status: String
    }

    /// Tunl's services from `scutil --nc list`. Other apps' VPNs are on the
    /// same list and are left out.
    public static func tunlServices(fromList output: String, bundleID: String = LiveSystem.appBundleID) -> [Service] {
        output.split(separator: "\n").compactMap { line -> Service? in
            let line = String(line)
            guard line.contains("VPN (\(bundleID))"),
                  let open = line.firstIndex(of: "("),
                  let close = line[open...].firstIndex(of: ")") else { return nil }
            let status = String(line[line.index(after: open)..<close])
            // The name is the quoted field before the trailing [VPN:…] tag.
            // It may itself contain quotes, so take the outermost pair.
            guard let tag = line.range(of: "[VPN:", options: .backwards),
                  let first = line[close..<tag.lowerBound].firstIndex(of: "\""),
                  let last = line[..<tag.lowerBound].lastIndex(of: "\""),
                  first < last else { return nil }
            return Service(name: String(line[line.index(after: first)..<last]), status: status)
        }
    }

    /// scutil's word for a state, in the vocabulary the app uses.
    public static func normalized(_ status: String) -> String {
        switch status.lowercased() {
        case "connected": return "connected"
        case "connecting": return "connecting"
        case "disconnecting": return "disconnecting"
        case "disconnected": return "disconnected"
        case "reasserting": return "reasserting"
        default: return "invalid"
        }
    }
}
