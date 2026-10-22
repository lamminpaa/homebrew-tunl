import Foundation

/// The CLI's copy of the document the app writes (Shared/AgentStatus.swift in
/// the app). Both are tested against Fixtures/status-v1.json.
public struct AgentStatus: Codable, Equatable {
    public static let supportedSchema = 1

    public var schema: Int
    public var updatedAt: Date
    public var appVersion: String
    public var tunnels: [Tunnel]

    public struct Tunnel: Codable, Equatable {
        public var name: String
        public var status: String
        public var autoReconnect: Bool
        public var health: String?
        public var latencyMs: Double?
        public var lastHandshakeSecondsAgo: Double?
        public var receivedBytes: UInt64?
        public var sentBytes: UInt64?
        public var recentEvents: [Event]
    }

    public struct Event: Codable, Equatable {
        public var at: Date
        public var kind: String
        public var detail: String?
    }

    public static func decoded(from data: Data) -> AgentStatus? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentStatus.self, from: data)
    }
}
