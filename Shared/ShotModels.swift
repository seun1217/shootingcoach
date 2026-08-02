import Foundation

// Models shared between the iPhone app and the Watch app.
// Keep this file Foundation-only so it compiles on both platforms.

enum ShotOutcome: String, Codable {
    case made
    case missed
}

enum MissReason: String, Codable {
    case short      // ball crossed the rim plane in front of the rim
    case long       // ball crossed the rim plane behind the rim
    case unknown    // trajectory ended without a classifiable crossing

    var koreanLabel: String {
        switch self {
        case .short: return "짧음"
        case .long: return "김"
        case .unknown: return "노골"
        }
    }
}

struct SessionStats: Codable, Equatable {
    var attempts: Int
    var made: Int
    var currentStreak: Int
    var bestStreak: Int

    static let empty = SessionStats(attempts: 0, made: 0, currentStreak: 0, bestStreak: 0)

    var percentage: Int {
        guard attempts > 0 else { return 0 }
        return Int((Double(made) / Double(attempts) * 100).rounded())
    }

    mutating func register(_ outcome: ShotOutcome) {
        attempts += 1
        switch outcome {
        case .made:
            made += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        case .missed:
            currentStreak = 0
        }
    }
}

/// One shot's worth of feedback, sent from the phone to the watch
/// right after the shot is resolved.
struct ShotFeedback: Codable, Equatable, Identifiable {
    let shotNumber: Int
    let outcome: ShotOutcome
    let missReason: MissReason?
    let releaseAngle: Double?   // launch angle in degrees, above horizontal
    let entryAngle: Double?     // angle of descent into the rim, degrees
    let tip: String             // short coaching message for the watch screen
    let stats: SessionStats
    let timestamp: Date

    var id: Int { shotNumber }
}

/// Session start/stop notice so the watch can reset its screen.
struct SessionStatePayload: Codable, Equatable {
    let active: Bool
    let timestamp: Date
}

/// Tiny envelope for WatchConnectivity dictionaries.
/// Values must stay property-list friendly, so payloads travel as JSON Data.
enum WatchChannel {
    static let kindKey = "kind"
    static let payloadKey = "payload"

    enum Kind: String {
        case shot
        case stats
        case sessionState
    }

    static func message<T: Encodable>(_ kind: Kind, _ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return [kindKey: kind.rawValue, payloadKey: data]
    }

    static func kind(of message: [String: Any]) -> Kind? {
        guard let raw = message[kindKey] as? String else { return nil }
        return Kind(rawValue: raw)
    }

    static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any]) -> T? {
        guard let data = message[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
