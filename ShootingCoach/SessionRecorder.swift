import AVFoundation
import Foundation
import Photos

/// Optional full-session recording. Frames are appended on the camera queue;
/// start/stop come from the main thread, so state is lock-protected.
final class SessionRecorder {
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var active = false
    private var rotationAngle: CGFloat = 0

    var isActive: Bool {
        lock.withLock { active }
    }

    /// Arm the recorder; the writer is created lazily on the first frame so
    /// it can adopt the buffer's real dimensions and timestamp.
    func begin(rotationAngle: CGFloat) {
        lock.withLock {
            self.rotationAngle = rotationAngle
            self.active = true
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }

        if writer == nil {
            setupLocked(with: sampleBuffer)
        }
        guard let writer, let input,
              writer.status == .writing,
              input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func setupLocked(with sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shooting-session-\(UUID().uuidString).mov")

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ])
            input.expectsMediaDataInRealTime = true
            // Buffers stay sensor-native; tag playback orientation instead.
            input.transform = CGAffineTransform(rotationAngle: rotationAngle * .pi / 180)
            guard writer.canAdd(input) else { return }
            writer.add(input)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            self.writer = writer
            self.input = input
        } catch {
            self.writer = nil
            self.input = nil
        }
    }

    /// Stops recording and hands back the movie URL (nil when nothing usable
    /// was written). Completion fires on an arbitrary thread.
    func finish(_ completion: @escaping (URL?) -> Void) {
        lock.lock()
        active = false
        guard let writer, let input, writer.status == .writing else {
            self.writer = nil
            self.input = nil
            lock.unlock()
            completion(nil)
            return
        }
        self.writer = nil
        self.input = nil
        lock.unlock()

        input.markAsFinished()
        let url = writer.outputURL
        writer.finishWriting {
            completion(writer.status == .completed ? url : nil)
        }
    }

    static func saveToPhotos(url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                try? FileManager.default.removeItem(at: url)
                completion(false)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                try? FileManager.default.removeItem(at: url)
                completion(success)
            }
        }
    }
}
