import CoreGraphics

/// Maps between Vision's normalized space (origin bottom-left, y-up) and the
/// on-screen coordinates of an aspect-fit video preview.
struct VideoGeometry {
    let uprightSize: CGSize   // video dimensions after rotation
    let viewSize: CGSize

    var fittedRect: CGRect {
        guard uprightSize.width > 0, uprightSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / uprightSize.width,
                        viewSize.height / uprightSize.height)
        let size = CGSize(width: uprightSize.width * scale,
                          height: uprightSize.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2,
            y: (viewSize.height - size.height) / 2,
            width: size.width,
            height: size.height)
    }

    func viewPoint(fromVision point: CGPoint) -> CGPoint {
        let fitted = fittedRect
        return CGPoint(
            x: fitted.minX + point.x * fitted.width,
            y: fitted.minY + (1 - point.y) * fitted.height)
    }

    func viewRect(fromVision rect: CGRect) -> CGRect {
        let fitted = fittedRect
        return CGRect(
            x: fitted.minX + rect.minX * fitted.width,
            y: fitted.minY + (1 - rect.maxY) * fitted.height,
            width: rect.width * fitted.width,
            height: rect.height * fitted.height)
    }

    /// Converts a drag translation in view points to Vision units
    /// (note the y-flip: dragging down decreases Vision y).
    func visionDelta(fromViewDelta delta: CGSize) -> CGSize {
        let fitted = fittedRect
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        return CGSize(width: delta.width / fitted.width,
                      height: -delta.height / fitted.height)
    }
}
