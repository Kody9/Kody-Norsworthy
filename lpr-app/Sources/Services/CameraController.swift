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
    private var pendingFrameCompletion: ((UIImage?) -> Void)?

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
        // high enough to be genuinely useful for reading a plate from a
        // parking-lot distance on a device with a telephoto lens.
        let cappedMax = min(device.maxAvailableVideoZoomFactor, 15.0)

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
    /// which is an acceptable tradeoff for a background check every couple
    /// of seconds versus a deliberate capture.
    func captureFrameSilently(completion: @escaping (UIImage?) -> Void) {
        applyCurrentOrientationToOutputs()
        videoDataQueue.async { [weak self] in
            self?.pendingFrameCompletion = completion
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let completion = pendingFrameCompletion else { return }
        pendingFrameCompletion = nil

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let image = UIImage(cgImage: cgImage)
        DispatchQueue.main.async { completion(image) }
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
