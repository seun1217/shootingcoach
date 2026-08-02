import CoreGraphics
import CoreMedia

/// Tuning knobs for the shot detection pipeline.
/// All lengths are in Vision's normalized image space (0...1, origin bottom-left)
/// unless noted otherwise.
struct AnalyzerConfig {
    // MARK: Trajectory detection (VNDetectTrajectoriesRequest)

    /// Analyze every frame. Raise (e.g. 1/30s) if an older phone overheats.
    var frameAnalysisSpacing: CMTime = .zero

    /// Points Vision needs before it reports a trajectory. Lower = earlier
    /// detection but more noise; higher = more robust but later.
    var trajectoryLength = 10

    /// Normalized ball radius bounds. A basketball filmed from the sideline
    /// at 5–10 m lands comfortably inside this window.
    var minBallRadius: CGFloat = 0.004
    var maxBallRadius: CGFloat = 0.09

    /// Drop trajectory observations below this confidence.
    var minTrajectoryConfidence: Float = 0.85

    /// Require a downward-opening parabola (gravity). `a` of y = ax² + bx + c
    /// must be below -minDownwardCurvature.
    var minDownwardCurvature: CGFloat = 0.2

    // MARK: Shot qualification

    /// A trajectory with no update for this long is considered finished.
    var trajectoryGraceSeconds: Double = 0.35

    /// Minimum projected points before a trajectory can count as a shot.
    var minPointCount = 5

    /// Minimum horizontal travel for a real shot (filters dribbles/noise).
    var minHorizontalSpan: CGFloat = 0.08

    /// The ball must come at least this close (horizontally) to the rim
    /// center at some point, otherwise the arc is a pass/dribble.
    var rimApproachMaxDX: CGFloat = 0.30

    /// Ignore a new "shot" starting sooner than this after the previous one
    /// ended — those are rebounds and rim bounces.
    var attemptCooldown: Double = 1.0

    /// Extra horizontal slack (fraction of rim width) when judging a make.
    var rimToleranceFactor: CGFloat = 0.15

    /// Vision first reports a trajectory ~trajectoryLength frames after the
    /// ball left the hand; shift pose lookups earlier by this much.
    var releaseLatencyCompensation: Double = 0.15

    // MARK: Pose sampling

    /// Run body-pose detection every Nth frame (2 → 30 Hz at 60 fps capture).
    var poseFrameInterval = 2

    /// Joint confidence floor.
    var minJointConfidence: Float = 0.3
}
