import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Thin wrapper around AVFoundation for a single-purpose "point and capture" flow.
/// No video is recorded or streamed anywhere off-device — a still photo is taken,
/// handed to `PlateOCRService`, then discarded from the session (only what the
/// user chooses to save persists, via `PlateEntry`).
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.platelog.camera.session")
    private var videoDevice: AVCaptureDevice?

    @Published var capturedImage: UIImage?
    @Published var isConfigured = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 1.0

    func configure() {
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
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto() {
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
    }
}
