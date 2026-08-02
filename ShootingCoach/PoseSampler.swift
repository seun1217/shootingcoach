import CoreGraphics
import Vision

/// Keeps a short rolling history of shooter joint angles so the analyzer can
/// look up form metrics at the moment a shot was released.
final class PoseSampler {
    private struct Snapshot {
        let time: Double
        let leftElbow: Double?
        let rightElbow: Double?
        let leftWristY: CGFloat?
        let rightWristY: CGFloat?
        let minKnee: Double?
    }

    private let minJointConfidence: Float
    private var snapshots: [Snapshot] = []

    init(minJointConfidence: Float) {
        self.minJointConfidence = minJointConfidence
    }

    func reset() {
        snapshots.removeAll()
    }

    /// Called on the analyzer queue with the strongest observed body.
    /// `aspect` = upright width / height, used to un-distort normalized space.
    func record(_ observation: VNHumanBodyPoseObservation, at time: Double, aspect: CGFloat) {
        guard let joints = try? observation.recognizedPoints(.all) else { return }

        func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let joint = joints[name], joint.confidence >= minJointConfidence else { return nil }
            return joint.location
        }

        let leftElbow = Self.angle(vertex: point(.leftElbow), a: point(.leftShoulder), b: point(.leftWrist), aspect: aspect)
        let rightElbow = Self.angle(vertex: point(.rightElbow), a: point(.rightShoulder), b: point(.rightWrist), aspect: aspect)
        let leftKnee = Self.angle(vertex: point(.leftKnee), a: point(.leftHip), b: point(.leftAnkle), aspect: aspect)
        let rightKnee = Self.angle(vertex: point(.rightKnee), a: point(.rightHip), b: point(.rightAnkle), aspect: aspect)
        let minKnee = [leftKnee, rightKnee].compactMap { $0 }.min()

        snapshots.append(Snapshot(
            time: time,
            leftElbow: leftElbow,
            rightElbow: rightElbow,
            leftWristY: point(.leftWrist)?.y,
            rightWristY: point(.rightWrist)?.y,
            minKnee: minKnee))

        while let firstSnapshot = snapshots.first, time - firstSnapshot.time > 5 {
            snapshots.removeFirst()
        }
    }

    /// Elbow extension of the shooting arm around the release moment.
    /// The shooting arm is guessed as the one with the higher wrist.
    func elbowAngle(near time: Double) -> Double? {
        let window = snapshots.filter { abs($0.time - time) <= 0.3 }
        guard !window.isEmpty else { return nil }

        let best = window.max { lhs, rhs in
            (Swift.max(lhs.leftWristY ?? -1, lhs.rightWristY ?? -1)) <
            (Swift.max(rhs.leftWristY ?? -1, rhs.rightWristY ?? -1))
        }
        guard let snapshot = best else { return nil }

        let leftY = snapshot.leftWristY ?? -1
        let rightY = snapshot.rightWristY ?? -1
        if rightY >= leftY, let angle = snapshot.rightElbow { return angle }
        if let angle = snapshot.leftElbow { return angle }
        return snapshot.rightElbow
    }

    /// Deepest knee bend inside the load window before release.
    func minKneeAngle(in range: ClosedRange<Double>) -> Double? {
        snapshots
            .filter { range.contains($0.time) }
            .compactMap(\.minKnee)
            .min()
    }

    /// Inner angle (degrees) at `vertex` formed by segments to `a` and `b`,
    /// corrected for the frame's aspect ratio.
    private static func angle(vertex: CGPoint?, a: CGPoint?, b: CGPoint?, aspect: CGFloat) -> Double? {
        guard let vertex, let a, let b else { return nil }
        let v1 = CGVector(dx: (a.x - vertex.x) * aspect, dy: a.y - vertex.y)
        let v2 = CGVector(dx: (b.x - vertex.x) * aspect, dy: b.y - vertex.y)
        let len1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let len2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard len1 > 0.001, len2 > 0.001 else { return nil }
        let cosine = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2)
        let clamped = Swift.min(1, Swift.max(-1, cosine))
        return Double(acos(clamped) * 180 / .pi)
    }
}
