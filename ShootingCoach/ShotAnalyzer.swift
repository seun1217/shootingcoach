import CoreGraphics
import CoreMedia
import ImageIO
import Vision

/// Raw result of one resolved shot, produced on the analyzer queue.
struct ShotRawResult {
    let outcome: ShotOutcome
    let missReason: MissReason?
    let releaseAngle: Double?     // degrees above horizontal at launch
    let entryAngle: Double?       // degrees of descent crossing the rim plane
    let elbowAngle: Double?       // shooting-arm extension near release
    let kneeAngle: Double?        // deepest knee bend while loading the shot
    let points: [CGPoint]         // trajectory in Vision space, for overlays
    let releaseTime: Double
}

protocol ShotAnalyzerDelegate: AnyObject {
    /// All callbacks arrive on the analyzer's processing queue.
    func analyzer(_ analyzer: ShotAnalyzer, didUpdateLiveTrajectory points: [CGPoint])
    func analyzer(_ analyzer: ShotAnalyzer, didFinalizeShot shot: ShotRawResult)
    func analyzer(_ analyzer: ShotAnalyzer, didChangeFrameSize size: CGSize)
}

/// Consumes camera frames and turns them into shot events:
/// ball trajectories via VNDetectTrajectoriesRequest, shooter form via
/// VNDetectHumanBodyPoseRequest, make/miss via the user-placed rim box.
/// Thread safety: mutable state is confined to `queue`; cross-thread inputs
/// go through `Locked`.
final class ShotAnalyzer: @unchecked Sendable {
    weak var delegate: ShotAnalyzerDelegate?

    let config: AnalyzerConfig

    /// Rim bounding box in Vision space; updated from the UI at any time.
    private let rimRect: Locked<CGRect>
    /// When paused (rim editing) frames are dropped entirely.
    private let paused = Locked<Bool>(false)
    private let busy = Locked<Bool>(false)

    private let queue = DispatchQueue(label: "shootingcoach.analyzer", qos: .userInitiated)
    private let poseSampler: PoseSampler

    // Queue-confined state.
    private var trajectoryRequest: VNDetectTrajectoriesRequest?
    private var activeTrajectories: [UUID: ActiveTrajectory] = [:]
    private var lastCountedEnd: Double?
    private var frameIndex = 0
    private var uprightSize: CGSize = .zero
    private var publishedLiveCount = -1

    init(config: AnalyzerConfig = AnalyzerConfig(), rim: CGRect) {
        self.config = config
        self.rimRect = Locked(rim)
        self.poseSampler = PoseSampler(minJointConfidence: config.minJointConfidence)
    }

    // MARK: - Control (callable from any thread)

    func updateRim(_ rect: CGRect) {
        rimRect.value = rect
    }

    func setPaused(_ value: Bool) {
        paused.value = value
        if value {
            queue.async { self.clearTransientState() }
        }
    }

    /// Fresh state for a new session. VNDetectTrajectoriesRequest is stateful,
    /// so it must be recreated rather than reused across sessions.
    func reset(rim: CGRect) {
        rimRect.value = rim
        queue.async {
            self.clearTransientState()
            self.lastCountedEnd = nil
            self.frameIndex = 0
            self.poseSampler.reset()
            let request = VNDetectTrajectoriesRequest(
                frameAnalysisSpacing: self.config.frameAnalysisSpacing,
                trajectoryLength: self.config.trajectoryLength)
            request.objectMinimumNormalizedRadius = Float(self.config.minBallRadius)
            request.objectMaximumNormalizedRadius = Float(self.config.maxBallRadius)
            self.trajectoryRequest = request
        }
    }

    /// Entry point from the camera queue. Drops the frame when a previous
    /// frame is still being analyzed so capture never backs up.
    func process(_ sampleBuffer: CMSampleBuffer, rotationAngle: CGFloat) {
        guard !paused.value else { return }
        guard busy.trySetTrue() else { return }
        queue.async {
            defer { self.busy.value = false }
            self.analyze(sampleBuffer, rotationAngle: rotationAngle)
        }
    }

    // MARK: - Frame analysis (queue-confined)

    private func clearTransientState() {
        activeTrajectories.removeAll()
        publishLiveTrajectory(force: true)
    }

    private func analyze(_ sampleBuffer: CMSampleBuffer, rotationAngle: CGFloat) {
        guard let trajectoryRequest else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let orientation = Self.orientation(forRotationAngle: rotationAngle)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let upright = (orientation == .right || orientation == .left)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
        if upright != uprightSize {
            uprightSize = upright
            delegate?.analyzer(self, didChangeFrameSize: upright)
        }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameIndex += 1

        var requests: [VNRequest] = [trajectoryRequest]
        let poseRequest: VNDetectHumanBodyPoseRequest?
        if frameIndex % config.poseFrameInterval == 0 {
            let request = VNDetectHumanBodyPoseRequest()
            requests.append(request)
            poseRequest = request
        } else {
            poseRequest = nil
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            return
        }

        if let observations = trajectoryRequest.results {
            ingest(observations, at: time)
        }
        if let pose = poseRequest?.results?.first {
            poseSampler.record(pose, at: time, aspect: upright.width / max(upright.height, 1))
        }

        finalizeStaleTrajectories(at: time)
        publishLiveTrajectory(force: false)
    }

    private static func orientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch angle {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    private func ingest(_ observations: [VNTrajectoryObservation], at time: Double) {
        for observation in observations {
            guard observation.confidence >= config.minTrajectoryConfidence else { continue }
            let a = CGFloat(observation.equationCoefficients.x)
            guard a < -config.minDownwardCurvature else { continue }

            var trajectory = activeTrajectories[observation.uuid]
                ?? ActiveTrajectory(id: observation.uuid, firstSeen: time)
            trajectory.merge(observation, at: time)
            activeTrajectories[observation.uuid] = trajectory
        }

        // Safety valve: never track more than a handful of arcs at once.
        if activeTrajectories.count > 8 {
            let sorted = activeTrajectories.values.sorted { $0.lastUpdate < $1.lastUpdate }
            for stale in sorted.prefix(activeTrajectories.count - 8) {
                activeTrajectories.removeValue(forKey: stale.id)
            }
        }
    }

    private func finalizeStaleTrajectories(at time: Double) {
        let finished = activeTrajectories.values.filter {
            time - $0.lastUpdate > config.trajectoryGraceSeconds
        }
        for trajectory in finished {
            activeTrajectories.removeValue(forKey: trajectory.id)
            if let result = evaluate(trajectory) {
                lastCountedEnd = trajectory.lastUpdate
                delegate?.analyzer(self, didFinalizeShot: result)
            }
        }
    }

    private func publishLiveTrajectory(force: Bool) {
        let best = activeTrajectories.values.max { $0.points.count < $1.points.count }
        let points = best?.points ?? []
        if force || points.count != publishedLiveCount {
            publishedLiveCount = points.count
            delegate?.analyzer(self, didUpdateLiveTrajectory: points)
        }
    }

    // MARK: - Shot evaluation

    private func evaluate(_ trajectory: ActiveTrajectory) -> ShotRawResult? {
        let rim = rimRect.value
        let points = trajectory.points
        guard points.count >= config.minPointCount,
              let first = points.first,
              let last = points.last else { return nil }

        let span = abs(last.x - first.x)
        guard span >= config.minHorizontalSpan else { return nil }
        let direction: CGFloat = last.x >= first.x ? 1 : -1

        let a = CGFloat(trajectory.coefficients.x)
        let b = CGFloat(trajectory.coefficients.y)
        let c = CGFloat(trajectory.coefficients.z)
        guard a < 0 else { return nil }

        let apexY = max(points.map(\.y).max() ?? 0, c - (b * b) / (4 * a))
        let rimPlane = rim.midY

        // Must be an arc that reaches rim height and travels toward the rim.
        guard apexY >= rim.minY else { return nil }
        let nearestDX = points.map { abs($0.x - rim.midX) }.min() ?? 1
        guard nearestDX <= config.rimApproachMaxDX else { return nil }

        // Rebound/putback filter: real shots do not start at the rim.
        let startsAtRim = abs(first.x - rim.midX) < rim.width * 1.5
            && abs(first.y - rim.midY) < rim.height * 3
        guard !startsAtRim else { return nil }

        // Cooldown: arcs spawned right after a counted shot are rim bounces.
        if let lastEnd = lastCountedEnd, trajectory.firstSeen - lastEnd < config.attemptCooldown {
            return nil
        }

        let crossX = descendingCrossing(points: points, plane: rimPlane)
            ?? parabolaCrossing(a: a, b: b, c: c, plane: rimPlane, direction: direction, points: points)

        let tolerance = rim.width * config.rimToleranceFactor
        let outcome: ShotOutcome
        let missReason: MissReason?
        if let x = crossX, x >= rim.minX - tolerance, x <= rim.maxX + tolerance {
            outcome = .made
            missReason = nil
        } else {
            outcome = .missed
            if let x = crossX {
                let isShort = direction > 0 ? x < rim.minX : x > rim.maxX
                missReason = isShort ? .short : .long
            } else if apexY < rimPlane {
                missReason = .short
            } else {
                let remaining = direction > 0 ? rim.minX - last.x : last.x - rim.maxX
                missReason = remaining > 0 ? .short : .unknown
            }
        }

        // Angles need the physical aspect ratio: slopes measured in normalized
        // space scale by height/width when converted to real-world angles.
        let hw = uprightSize.width > 0 ? uprightSize.height / uprightSize.width : 9.0 / 16.0
        let releaseSlope = (2 * a * first.x + b) * direction * hw
        let releaseAngle = Double(atan(releaseSlope) * 180 / .pi)
        var entryAngle: Double?
        if let x = crossX {
            let slope = (2 * a * x + b) * direction * hw
            entryAngle = abs(Double(atan(slope) * 180 / .pi))
        }

        let releaseTime = trajectory.firstSeen - config.releaseLatencyCompensation
        let elbow = poseSampler.elbowAngle(near: releaseTime)
        let knee = poseSampler.minKneeAngle(in: (releaseTime - 0.9)...(releaseTime + 0.1))

        return ShotRawResult(
            outcome: outcome,
            missReason: missReason,
            releaseAngle: releaseAngle > 0 ? releaseAngle : nil,
            entryAngle: entryAngle,
            elbowAngle: elbow,
            kneeAngle: knee,
            points: points,
            releaseTime: releaseTime)
    }

    /// Interpolated x where measured points descend through the rim plane.
    private func descendingCrossing(points: [CGPoint], plane: CGFloat) -> CGFloat? {
        guard points.count > 1 else { return nil }
        for i in 1..<points.count {
            let p0 = points[i - 1]
            let p1 = points[i]
            if p0.y >= plane, p1.y < plane, p1.y < p0.y {
                let fraction = (p0.y - plane) / (p0.y - p1.y)
                return p0.x + (p1.x - p0.x) * fraction
            }
        }
        return nil
    }

    /// Fallback: solve the fitted parabola for the rim plane. Only trusted
    /// near the observed x-range — the net usually hides the final points.
    private func parabolaCrossing(a: CGFloat, b: CGFloat, c: CGFloat,
                                  plane: CGFloat, direction: CGFloat,
                                  points: [CGPoint]) -> CGFloat? {
        let discriminant = b * b - 4 * a * (c - plane)
        guard discriminant > 0 else { return nil }
        let root = sqrt(discriminant)
        let x1 = (-b + root) / (2 * a)
        let x2 = (-b - root) / (2 * a)
        // Descending branch lies past the vertex along the travel direction.
        let x = direction > 0 ? max(x1, x2) : min(x1, x2)

        let xs = points.map(\.x)
        guard let minX = xs.min(), let maxX = xs.max() else { return nil }
        let slack: CGFloat = 0.15
        guard x >= minX - slack, x <= maxX + slack else { return nil }
        return x
    }
}

// MARK: - ActiveTrajectory

/// Accumulates Vision observations that share a trajectory UUID.
private struct ActiveTrajectory {
    let id: UUID
    let firstSeen: Double
    var lastUpdate: Double
    var coefficients = SIMD3<Float>(0, 0, 0)
    var points: [CGPoint] = []

    init(id: UUID, firstSeen: Double) {
        self.id = id
        self.firstSeen = firstSeen
        self.lastUpdate = firstSeen
    }

    mutating func merge(_ observation: VNTrajectoryObservation, at time: Double) {
        lastUpdate = time
        coefficients = observation.equationCoefficients

        // Observation windows overlap; append only points we have not stored.
        let tail = points.suffix(12)
        for point in observation.projectedPoints {
            let candidate = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
            let isDuplicate = tail.contains {
                abs($0.x - candidate.x) < 0.004 && abs($0.y - candidate.y) < 0.004
            }
            if !isDuplicate {
                points.append(candidate)
            }
        }
        if points.count > 400 {
            points.removeFirst(points.count - 400)
        }
    }
}
