import SwiftUI

/// Full-screen editor for the rim bounding box: drag the box to move it,
/// drag the corner handle to resize.
struct RimEditorOverlay: View {
    @Binding var rim: CGRect      // Vision space
    let geometry: VideoGeometry

    @State private var initialRim: CGRect?

    var body: some View {
        let viewRect = geometry.viewRect(fromVision: rim)

        ZStack {
            Color.black.opacity(0.25)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.yellow.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow, lineWidth: 3))
                .frame(width: max(viewRect.width, 1), height: max(viewRect.height, 1))
                .position(x: viewRect.midX, y: viewRect.midY)
                .gesture(moveGesture)

            Circle()
                .fill(Color.yellow)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .frame(width: 22, height: 22)
                .position(x: viewRect.maxX, y: viewRect.maxY)
                .gesture(resizeGesture)

            VStack {
                Text("골대 림(그물 바로 위 고리)에 노란 박스를 맞춰주세요")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.yellow)
                Spacer()
            }
            .padding(.top, 24)
            .allowsHitTesting(false)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if initialRim == nil { initialRim = rim }
                guard let start = initialRim else { return }
                let delta = geometry.visionDelta(fromViewDelta: value.translation)
                var rect = start
                rect.origin.x += delta.width
                rect.origin.y += delta.height
                rim = Self.clamp(rect)
            }
            .onEnded { _ in initialRim = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if initialRim == nil { initialRim = rim }
                guard let start = initialRim else { return }
                let delta = geometry.visionDelta(fromViewDelta: value.translation)
                var rect = start
                // Keep the top edge fixed; grow width right and height down.
                rect.size.width = start.width + delta.width
                rect.origin.y = start.origin.y + delta.height
                rect.size.height = start.height - delta.height
                rim = Self.clamp(rect)
            }
            .onEnded { _ in initialRim = nil }
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(max(result.size.width, 0.02), 0.5)
        result.size.height = min(max(result.size.height, 0.015), 0.5)
        result.origin.x = min(max(result.origin.x, 0), 1 - result.size.width)
        result.origin.y = min(max(result.origin.y, 0), 1 - result.size.height)
        return result
    }
}
