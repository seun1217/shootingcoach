import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var connector: PhoneConnector

    var body: some View {
        Group {
            if let feedback = connector.lastFeedback {
                ShotResultView(feedback: feedback)
            } else {
                WaitingView(sessionActive: connector.sessionActive, stats: connector.stats)
            }
        }
        .animation(.snappy, value: connector.lastFeedback)
    }
}

/// Shown before the first shot (or between sessions).
private struct WaitingView: View {
    let sessionActive: Bool
    let stats: SessionStats

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text(sessionActive ? "세션 진행 중" : "슈팅 코치")
                .font(.headline)
            Text(sessionActive
                 ? "첫 슛을 기다리고 있어요"
                 : "아이폰에서 세션을 시작하면\n슛마다 피드백이 도착해요")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if stats.attempts > 0 {
                Divider()
                StatsFooter(stats: stats)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Per-shot feedback screen, refreshed on every shot with a haptic.
private struct ShotResultView: View {
    let feedback: ShotFeedback

    private var made: Bool { feedback.outcome == .made }

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                HStack {
                    Text("#\(feedback.shotNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if feedback.stats.currentStreak >= 2 {
                        Text("🔥\(feedback.stats.currentStreak)")
                            .font(.caption2)
                    }
                }

                Image(systemName: made ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(made ? .green : .red)

                Text(made ? "성공!" : (feedback.missReason?.koreanLabel ?? "실패"))
                    .font(.headline)

                Text(feedback.tip)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let angles = angleLine {
                    Text(angles)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()
                StatsFooter(stats: feedback.stats)
            }
        }
        .id(feedback.shotNumber)
    }

    private var angleLine: String? {
        var parts: [String] = []
        if let release = feedback.releaseAngle {
            parts.append("릴리즈 \(Int(release.rounded()))°")
        }
        if let entry = feedback.entryAngle {
            parts.append("진입 \(Int(entry.rounded()))°")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct StatsFooter: View {
    let stats: SessionStats

    var body: some View {
        Text("\(stats.made)/\(stats.attempts) · \(stats.percentage)%")
            .font(.footnote.bold())
            .foregroundStyle(.orange)
    }
}
