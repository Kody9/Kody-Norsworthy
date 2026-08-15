import AVFoundation
import Combine
import CoreImage
import SwiftUI
import UIKit

/// Thin wrapper around AVFoundation for a single-purpose "point and capture" flow.
/// No video is recorded or streamed anywhere off-device.
///
/// Two distinct capture paths:
/// - `capturePhoto()` — the full photo pipeline (used for manual "READ PLATE"
///   taps). Plays the normal system shutter sound, which is appropriate for
///   a deliberate, in-the-moment capture, and Apple deliberately does not
///   allow that sound to be suppressed via public API (it's an anti-covert-
///   photography measure, by design).
/// - `captureFrameSilently(completion:)` — grabs a single frame from the
///   live video stream instead. This is not a "photo capture" in the formal
///   sense, so no shutter plays; used for auto-scan's periodic background
///   checks so it doesn't click every couple of seconds.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.platelog.camera.session")
    private let videoDataQueue = DispatchQueue(label: "com.platelog.camera.videodata")
    private let ciContext = CIContext()
    private var videoDevice: AVCaptureDevice?
    private var pendingFrameCompletion: ((CapturedVideoFrame?) -> Void)?
    private var pendingFrameRequestID: UUID?

    @Published var capturedImage: UIImage?
    @Published var isConfigured = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 1.0

    func configure() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        sessionQueue.async { [weak self] in
            self?.setUp()
        }
    }

    private func setUp() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)

        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()
        session.startRunning()

        // Some devices report absurd triple-digit "max" digital zoom that's
        // pure noise by the time you get there — cap well below that, but
        // high enough to be genuinely useful on a Pro-class telephoto lens.
        let cappedMax = min(device.maxAvailableVideoZoomFactor, 30.0)

        DispatchQueue.main.async { [weak self] in
            self?.videoDevice = device
            self?.isConfigured = true
            self?.minZoomFactor = device.minAvailableVideoZoomFactor
            self?.maxZoomFactor = cappedMax
        }
    }

    /// Sets the lens zoom, clamped to the device's (capped) supported range.
    /// Safe to call from gesture handlers or button taps on the main thread.
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            // Non-fatal: zoom just won't change this time.
        }
    }

    func stop() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto() {
        applyCurrentOrientationToOutputs()
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
        }
    }

    /// Grabs the next live video frame without triggering the photo pipeline
    /// (no shutter sound). Slightly lower fidelity than `capturePhoto()`,
    /// an acceptable tradeoff since auto-scan calls this back-to-back —
    /// there's no fixed interval between attempts anymore, so this is the
    /// throttle: a new grab only starts once the previous one (frame +
    /// OCR) has fully finished.
    ///
    /// Returns a `CapturedVideoFrame` wrapping the raw pixel buffer rather
    /// than a rendered `UIImage` — the session runs at full photo
    /// resolution (so the video feed is 12MP+, not a typical low-res video
    /// preview stream), and rendering that entire frame to a `CGImage` on
    /// every single scan pass was the dominant per-frame cost in the
    /// auto-scan loop, slow enough to miss vehicles passing quickly through
    /// frame. The caller renders only the small cropped region it actually
    /// needs for OCR, and only pays for a full-frame render on the rare
    /// pass that actually queues a detection.
    ///
    /// Always calls `completion` exactly once, even if no frame ever
    /// arrives (e.g. the video data output failed to attach on this
    /// device) — a `nil` after ~0.75s rather than silently hanging
    /// forever, which previously left the caller's "is a capture in
    /// flight" state stuck true and permanently blocked all further
    /// auto-scan attempts.
    func captureFrameSilently(completion: @escaping (CapturedVideoFrame?) -> Void) {
        applyCurrentOrientationToOutputs()
        let requestID = UUID()
        videoDataQueue.async { [weak self] in
            self?.pendingFrameRequestID = requestID
            self?.pendingFrameCompletion = completion
        }
        videoDataQueue.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.pendingFrameRequestID == requestID else { return }
            self.pendingFrameRequestID = nil
            self.pendingFrameCompletion = nil
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Async convenience over the completion-based grab, for use in a
    /// tight `while` loop (auto-scan) without nested closures.
    func captureFrameSilently() async -> CapturedVideoFrame? {
        await withCheckedContinuation { continuation in
            captureFrameSilently { frame in
                continuation.resume(returning: frame)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let completion = pendingFrameCompletion else { return }
        pendingFrameCompletion = nil
        pendingFrameRequestID = nil

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let frame = CapturedVideoFrame(ciImage: CIImage(cvPixelBuffer: pixelBuffer), context: ciContext)
        DispatchQueue.main.async { completion(frame) }
    }

    /// Both outputs need to be told the device's current physical rotation
    /// right before a capture, or photos/frames taken while the phone is
    /// held sideways come out rotated 90°. Uses the older `videoOrientation`
    /// API rather than iOS 17's newer rotation-angle APIs — deprecated, but
    /// thoroughly proven, which matters more than avoiding a warning when
    /// there's no way to test this on real hardware ahead of time.
    private func applyCurrentOrientationToOutputs() {
        guard let orientation = Self.videoOrientation(for: UIDevice.current.orientation) else { return }
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }

    /// UIDeviceOrientation and AVCaptureVideoOrientation define landscape
    /// left/right oppositely from each other for the back camera — this
    /// swap is intentional, not a bug.
    fileprivate static func videoOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }
}

/// A grabbed video frame that hasn't been rendered to a `UIImage` yet.
/// Rendering the full frame (`fullImage()`) is expensive at photo-preset
/// resolution; `cropped(previewSize:fractionalRect:)` renders only the
/// requested region directly from the source `CIImage`, which is what
/// makes it cheap enough to call on every auto-scan pass.
struct CapturedVideoFrame {
    let ciImage: CIImage
    let context: CIContext

    /// Renders the entire frame. Call only when a detection is actually
    /// being queued or saved, not on every scan pass.
    func fullImage() -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Renders only the region behind `fractionalRect` (0...1, origin
    /// top-left) of a preview shown at `previewSize` with
    /// `.resizeAspectFill` — the same aspect-fill mapping
    /// `UIImage.croppedToPreviewRegion` uses, applied before rasterizing
    /// instead of after, which is what avoids the full-frame render cost.
    func cropped(previewSize: CGSize, fractionalRect: CGRect) -> UIImage? {
        guard previewSize.width > 0, previewSize.height > 0 else { return fullImage() }
        let imageSize = ciImage.extent.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let scale = max(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let visibleSize = CGSize(width: previewSize.width / scale, height: previewSize.height / scale)
        let visibleOriginTopLeft = CGPoint(
            x: (imageSize.width - visibleSize.width) / 2,
            y: (imageSize.height - visibleSize.height) / 2
        )

        let cropTopLeft = CGRect(
            x: visibleOriginTopLeft.x + fractionalRect.minX * visibleSize.width,
            y: visibleOriginTopLeft.y + fractionalRect.minY * visibleSize.height,
            width: fractionalRect.width * visibleSize.width,
            height: fractionalRect.height * visibleSize.height
        )

        // CIImage uses a bottom-left origin (Y increases upward), unlike
        // the top-left-origin rect computed above -- flip Y to match.
        let cropInCIImageSpace = CGRect(
            x: ciImage.extent.origin.x + cropTopLeft.origin.x,
            y: ciImage.extent.origin.y + (imageSize.height - cropTopLeft.maxY),
            width: cropTopLeft.width,
            height: cropTopLeft.height
        ).intersection(ciImage.extent)

        guard !cropInCIImageSpace.isEmpty else { return nil }
        let croppedCI = ciImage.cropped(to: cropInCIImageSpace)
        guard let cgImage = context.createCGImage(croppedCI, from: croppedCI.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        // Reliably fires on rotation (the view's bounds change), so the
        // live preview stays upright without needing a separate observer.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard
                let connection = videoPreviewLayer.connection,
                connection.isVideoOrientationSupported,
                let orientation = CameraController.videoOrientation(for: UIDevice.current.orientation)
            else {
                return
            }
            connection.videoOrientation = orientation
        }
    }
}
