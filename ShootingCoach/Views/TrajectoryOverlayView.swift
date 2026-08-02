import SwiftUI

/// Draws the rim box, the last shot's arc (ghost) and the ball's live arc
/// on top of the camera preview.
struct TrajectoryOverlayView: View {
    let live: [CGPoint]
    let ghost: [CGPoint]
    let rim: CGRect
    let isEditingRim: Bool
    let geometry: VideoGeometry

    var body: some View {
        Canvas { context, _ in
            if !isEditingRim {
                let rimRect = geometry.viewRect(fromVision: rim)
                let rimPath = Path(roundedRect: rimRect, cornerRadius: 5)
                context.stroke(
                    rimPath,
                    with: .color(.orange.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }

            if ghost.count > 1 {
                context.stroke(
                    path(for: ghost),
                    with: .color(.white.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if live.count > 1 {
                context.stroke(
                    path(for: live),
                    with: .color(.orange),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let lastPoint = live.last {
                    let p = geometry.viewPoint(fromVision: lastPoint)
                    let dot = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
                    context.fill(Path(ellipseIn: dot), with: .color(.orange))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func path(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: geometry.viewPoint(fromVision: first))
        for point in points.dropFirst() {
            path.addLine(to: geometry.viewPoint(fromVision: point))
        }
        return path
    }
}
