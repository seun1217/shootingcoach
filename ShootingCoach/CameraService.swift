import AVFoundation
import CoreMedia

/// Owns the AVCaptureSession: back wide camera, 1080p @ 60 fps when the
/// hardware supports it, video frames delivered on a dedicated queue.
final class CameraService: NSObject {
    enum CameraError: LocalizedError {
        case cameraUnavailable
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "카메라를 찾을 수 없어요."
            case .cannotAddInput: return "카메라 입력을 설정할 수 없어요."
            case .cannotAddOutput: return "카메라 출력을 설정할 수 없어요."
            }
        }
    }

    let session = AVCaptureSession()

    /// Preview rotation angle (degrees) pushed in by the preview view; frames
    /// stay in the sensor's native orientation and Vision compensates.
    let rotationAngle = Locked<CGFloat>(0)

    /// Called on the video queue for every captured frame.
    var onFrame: ((CMSampleBuffer, CGFloat) -> Void)?
    /// Called on the main queue when configuration fails.
    var onError: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "shootingcoach.camera.session")
    private let videoQueue = DispatchQueue(label: "shootingcoach.camera.video", qos: .userInitiated)
    private var configured = false

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() {
        sessionQueue.async {
            do {
                try self.configureIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.onError?(message) }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: - Configuration

    private func configureIfNeeded() throws {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        Self.selectHighFrameRateFormat(for: device)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)

        configured = true
    }

    /// Prefer 1920x1080 420f at 60 fps; silently keep the default format
    /// (usually 30 fps) when no matching format exists.
    private static func selectHighFrameRateFormat(for device: AVCaptureDevice) {
        let targetFPS: Double = 60
        var chosen: AVCaptureDevice.Format?

        for format in device.formats {
            let description = format.formatDescription
            guard CMFormatDescriptionGetMediaSubType(description) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { continue }
            let dims = CMVideoFormatDescriptionGetDimensions(description)
            guard dims.width == 1920, dims.height == 1080 else { continue }
            guard format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= targetFPS }) else { continue }
            chosen = format
            break
        }

        guard let format = chosen else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            // Keep the default format; analysis still works at 30 fps.
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer, rotationAngle.value)
    }
}
