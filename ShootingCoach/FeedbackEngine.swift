import CoreGraphics
import Foundation

/// A resolved shot with everything the UI and coach logic need.
struct ShotRecord: Identifiable {
    let shotNumber: Int
    let outcome: ShotOutcome
    let missReason: MissReason?
    let releaseAngle: Double?
    let entryAngle: Double?
    let elbowAngle: Double?
    let kneeAngle: Double?
    let points: [CGPoint]
    let timestamp: Date

    var id: Int { shotNumber }
}

/// Turns shot metrics into one short Korean coaching line for the watch.
enum FeedbackEngine {
    private static let praise = ["나이스 샷!", "굿샷!", "완벽해요!", "그 감각 그대로!"]

    static func feedback(for shot: ShotRecord, stats: SessionStats) -> ShotFeedback {
        var parts: [String] = []

        switch shot.outcome {
        case .made:
            if stats.currentStreak >= 3 {
                parts.append("🔥 \(stats.currentStreak)연속 성공!")
            } else {
                parts.append(praise[shot.shotNumber % praise.count])
            }
            if let entry = shot.entryAngle {
                if entry >= 43, entry <= 50 {
                    parts.append("이상적인 진입각 \(Int(entry.rounded()))°")
                } else if entry < 38 {
                    parts.append("아크를 조금만 높이면 더 편해져요")
                }
            }
        case .missed:
            switch shot.missReason {
            case .short:
                parts.append("짧았어요 — 무릎 반동으로 파워를 더!")
            case .long:
                parts.append("길었어요 — 릴리즈를 부드럽게")
            default:
                parts.append("노골 — 다음 샷에 집중!")
            }
        }

        if let formTip = formTip(for: shot), parts.count < 2 {
            parts.append(formTip)
        }

        return ShotFeedback(
            shotNumber: shot.shotNumber,
            outcome: shot.outcome,
            missReason: shot.missReason,
            releaseAngle: shot.releaseAngle,
            entryAngle: shot.entryAngle,
            tip: parts.joined(separator: " · "),
            stats: stats,
            timestamp: shot.timestamp)
    }

    /// At most one form cue per shot, most impactful first.
    private static func formTip(for shot: ShotRecord) -> String? {
        if let release = shot.releaseAngle, release < 40 {
            return "릴리즈 각도가 낮아요(\(Int(release.rounded()))°) — 더 높은 포물선으로"
        }
        if let elbow = shot.elbowAngle, elbow < 150 {
            return "팔꿈치를 끝까지 펴서 폴로스루"
        }
        if shot.outcome == .missed, shot.missReason == .short,
           let knee = shot.kneeAngle, knee > 155 {
            return "무릎을 더 굽혀 다리 힘을 쓰세요"
        }
        return nil
    }
}
