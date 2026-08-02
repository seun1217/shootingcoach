import SwiftUI

/// Main (and only) screen: full-bleed camera preview with the analysis
/// overlays, session HUD, and rim setup.
struct CoachSessionView: View {
    @EnvironmentObject private var viewModel: SessionViewModel

    var body: some View {
        ZStack {
            videoLayer
            hudLayer
            if !viewModel.isRunning && !viewModel.isEditingRim {
                introCard
            }
            if viewModel.cameraPermissionDenied {
                permissionOverlay
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: Video + overlays (full screen, geometry-matched)

    private var videoLayer: some View {
        GeometryReader { geo in
            let geometry = VideoGeometry(uprightSize: viewModel.frameSize, viewSize: geo.size)
            ZStack {
                CameraPreviewView(camera: viewModel.camera)
                TrajectoryOverlayView(
                    live: viewModel.liveTrajectory,
                    ghost: viewModel.lastShotPath,
                    rim: viewModel.rimRect,
                    isEditingRim: viewModel.isEditingRim,
                    geometry: geometry)
                if viewModel.isEditingRim {
                    RimEditorOverlay(rim: $viewModel.rimRect, geometry: geometry)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                statChips
                Spacer()
                WatchBadge(bridge: viewModel.watch)
                recordToggle
                rimButton
            }

            HStack {
                recentShotDots
                Spacer()
            }
            .padding(.top, 6)

            Spacer()

            HStack(alignment: .bottom) {
                if let feedback = viewModel.lastFeedback {
                    FeedbackBanner(feedback: feedback)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer()
                startStopButton
            }
        }
        .padding(16)
        .overlay(alignment: .top) { statusToast }
    }

    private var statChips: some View {
        HStack(spacing: 6) {
            StatChip(label: "시도", value: "\(viewModel.stats.attempts)")
            StatChip(label: "성공", value: "\(viewModel.stats.made)")
            StatChip(label: "성공률", value: "\(viewModel.stats.percentage)%")
            if viewModel.stats.currentStreak >= 2 {
                StatChip(label: "연속", value: "🔥\(viewModel.stats.currentStreak)")
            }
        }
    }

    private var recentShotDots: some View {
        HStack(spacing: 5) {
            ForEach(viewModel.shots.suffix(12)) { shot in
                Circle()
                    .fill(shot.outcome == .made ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var recordToggle: some View {
        Button {
            viewModel.recordingEnabled.toggle()
        } label: {
            Image(systemName: viewModel.recordingEnabled ? "record.circle.fill" : "record.circle")
                .font(.title3)
                .foregroundStyle(viewModel.recordingEnabled ? .red : .white)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(viewModel.isRunning)
        .opacity(viewModel.isRunning ? 0.4 : 1)
    }

    private var rimButton: some View {
        Button {
            viewModel.toggleRimEditing()
        } label: {
            if viewModel.isEditingRim {
                Text("완료")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.yellow, in: Capsule())
                    .foregroundStyle(.black)
            } else {
                Label("림 위치", systemImage: "target")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var startStopButton: some View {
        Button {
            if viewModel.isRunning {
                viewModel.stopSession()
            } else {
                viewModel.startSession()
            }
        } label: {
            Label(viewModel.isRunning ? "세션 종료" : "세션 시작",
                  systemImage: viewModel.isRunning ? "stop.fill" : "play.fill")
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(viewModel.isRunning ? Color.red : Color.green, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var statusToast: some View {
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.footnote.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 4)
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if viewModel.statusMessage == message {
                        viewModel.statusMessage = nil
                    }
                }
        }
    }

    // MARK: Intro / permission

    private var introCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "basketball.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("슈팅 코치")
                .font(.title2.bold())
            Text("1. 코트 측면, 슈터와 골대가 한 화면에 들어오게 휴대폰을 고정하세요\n2. '림 위치' 버튼으로 골대 림에 박스를 맞추세요\n3. 세션을 시작하면 슛 하나가 끝날 때마다 애플워치로 피드백이 갑니다")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("카메라 권한이 필요해요")
                .font(.headline)
            Text("슈팅 궤적을 분석하려면 카메라 접근을 허용해주세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .ignoresSafeArea()
    }
}

// MARK: - Components

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct WatchBadge: View {
    @ObservedObject var bridge: WatchBridge

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "applewatch")
            Circle()
                .fill(bridge.isReachable ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(bridge.isReachable ? .white : .secondary)
    }
}

private struct FeedbackBanner: View {
    let feedback: ShotFeedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.outcome == .made ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(feedback.outcome == .made ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feedback.outcome == .made ? "성공!" : (feedback.missReason?.koreanLabel ?? "실패"))
                        .font(.headline)
                    Text("#\(feedback.shotNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(feedback.tip)
                    .font(.subheadline)
                if let angles = angleLine {
                    Text(angles)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
