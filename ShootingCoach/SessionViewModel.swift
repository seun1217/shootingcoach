import AVFoundation
import Combine
import SwiftUI

/// Central glue: camera → analyzer → (stats, overlay, feedback) → watch.
@MainActor
final class SessionViewModel: ObservableObject {
    // MARK: Published UI state

    @Published var isRunning = false
    @Published var isEditingRim = false {
        didSet { analyzer.setPaused(isEditingRim) }
    }
    @Published var cameraPermissionDenied = false
    @Published var recordingEnabled = false
    @Published var stats = SessionStats.empty
    @Published var shots: [ShotRecord] = []
    @Published var lastFeedback: ShotFeedback?
    @Published var liveTrajectory: [CGPoint] = []
    @Published var lastShotPath: [CGPoint] = []
    @Published var statusMessage: String?
    @Published var frameSize = CGSize(width: 1920, height: 1080)
    @Published var rimRect: CGRect {
        didSet {
            analyzer.updateRim(rimRect)
            Self.persistRim(rimRect)
        }
    }

    let camera = CameraService()
    let watch = WatchBridge()

    private let analyzer: ShotAnalyzer
    private let recorder = SessionRecorder()
    private static let rimDefaultsKey = "rimRect.v1"

    init() {
        let rim = Self.loadPersistedRim()
            ?? CGRect(x: 0.46, y: 0.58, width: 0.09, height: 0.06)
        rimRect = rim
        analyzer = ShotAnalyzer(rim: rim)
        analyzer.delegate = self

        camera.onFrame = { [weak self] sampleBuffer, angle in
            // Runs on the camera's video queue.
            guard let self else { return }
            self.recorder.append(sampleBuffer)
            self.analyzer.process(sampleBuffer, rotationAngle: angle)
        }
        camera.onError = { [weak self] message in
            self?.statusMessage = message
        }
    }

    // MARK: Session control

    func startSession() {
        Task {
            guard await CameraService.requestAccess() else {
                cameraPermissionDenied = true
                return
            }
            cameraPermissionDenied = false
            stats = .empty
            shots = []
            lastFeedback = nil
            liveTrajectory = []
            lastShotPath = []
            analyzer.reset(rim: rimRect)
            if recordingEnabled {
                recorder.begin(rotationAngle: camera.rotationAngle.value)
            }
            camera.start()
            isRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            watch.sendSessionState(active: true)
        }
    }

    func stopSession() {
        camera.stop()
        isRunning = false
        isEditingRim = false
        UIApplication.shared.isIdleTimerDisabled = false
        watch.sendSessionState(active: false)

        if recorder.isActive {
            recorder.finish { [weak self] url in
                guard let url else { return }
                SessionRecorder.saveToPhotos(url: url) { saved in
                    Task { @MainActor in
                        self?.statusMessage = saved
                            ? "세션 영상을 사진 앱에 저장했어요 🎥"
                            : "영상 저장 실패 — 사진 접근 권한을 확인하세요"
                    }
                }
            }
        }

        if stats.attempts > 0 {
            statusMessage = "세션 종료 · \(stats.made)/\(stats.attempts) (\(stats.percentage)%)"
        }
    }

    func toggleRimEditing() {
        isEditingRim.toggle()
        if !isEditingRim {
            statusMessage = "림 위치 저장 완료"
        }
    }

    // MARK: Rim persistence

    private static func loadPersistedRim() -> CGRect? {
        guard let values = UserDefaults.standard.array(forKey: rimDefaultsKey) as? [Double],
              values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private static func persistRim(_ rect: CGRect) {
        UserDefaults.standard.set(
            [rect.origin.x, rect.origin.y, rect.width, rect.height].map(Double.init),
            forKey: rimDefaultsKey)
    }
}

// MARK: - ShotAnalyzerDelegate (called on the analyzer queue)

extension SessionViewModel: ShotAnalyzerDelegate {
    nonisolated func analyzer(_ analyzer: ShotAnalyzer, didUpdateLiveTrajectory points: [CGPoint]) {
        Task { @MainActor in
            self.liveTrajectory = points
        }
    }

    nonisolated func analyzer(_ analyzer: ShotAnalyzer, didFinalizeShot shot: ShotRawResult) {
        Task { @MainActor in
            var newStats = self.stats
            newStats.register(shot.outcome)
            self.stats = newStats

            let record = ShotRecord(
                shotNumber: newStats.attempts,
                outcome: shot.outcome,
                missReason: shot.missReason,
                releaseAngle: shot.releaseAngle,
                entryAngle: shot.entryAngle,
                elbowAngle: shot.elbowAngle,
                kneeAngle: shot.kneeAngle,
                points: shot.points,
                timestamp: Date())
            self.shots.append(record)
            self.lastShotPath = shot.points
            self.liveTrajectory = []

            let feedback = FeedbackEngine.feedback(for: record, stats: newStats)
            withAnimation(.snappy) {
                self.lastFeedback = feedback
            }
            self.watch.send(feedback: feedback)
        }
    }

    nonisolated func analyzer(_ analyzer: ShotAnalyzer, didChangeFrameSize size: CGSize) {
        Task { @MainActor in
            self.frameSize = size
        }
    }
}
