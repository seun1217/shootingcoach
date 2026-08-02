import AVFoundation
import SwiftUI
import UIKit

/// AVCaptureVideoPreviewLayer wrapper. Keeps the preview rotation in sync with
/// the interface orientation and reports the angle back to the camera service
/// so Vision can compensate (capture buffers stay sensor-native).
struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspect
        view.onAngleChange = { [weak camera] angle in
            camera?.rotationAngle.value = angle
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    var onAngleChange: ((CGFloat) -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(orientationChanged),
                           name: UIDevice.orientationDidChangeNotification,
                           object: nil)
        // The preview connection appears only after the session gains inputs.
        center.addObserver(self,
                           selector: #selector(sessionStarted),
                           name: .AVCaptureSessionDidStartRunning,
                           object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotation()
    }

    @objc private func orientationChanged() {
        updateRotation()
    }

    @objc private func sessionStarted() {
        DispatchQueue.main.async { self.updateRotation() }
    }

    private func updateRotation() {
        guard let scene = window?.windowScene else { return }

        let angle: CGFloat
        switch scene.interfaceOrientation {
        case .landscapeLeft: angle = 180
        case .portrait: angle = 90
        case .portraitUpsideDown: angle = 270
        default: angle = 0   // landscapeRight = back camera's native orientation
        }

        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        onAngleChange?(angle)
    }
}
