import AVFoundation
import Combine
import SwiftUI

struct CaptureView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var locationService = LocationService()

    @State private var showConfirmSheet = false
    @State private var candidatePlates: [PlateOCRService.Candidate] = []
    @State private var isProcessing = false
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                if camera.isConfigured {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white)
                }

                VStack {
                    Spacer()
                    if isProcessing {
                        ProgressView("Reading plate…")
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button(action: capture) {
                        Circle()
                            .fill(.white)
                            .frame(width: 74, height: 74)
                            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 2))
                    }
                    .padding(.bottom, 32)
                    .disabled(isProcessing || !camera.isConfigured)
                }
            }
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: requestPermissions)
            .onDisappear { camera.stop() }
            .onReceive(camera.$capturedImage.compactMap { $0 }) { image in
                PlateOCRService.recognizePlates(in: image) { candidates in
                    DispatchQueue.main.async {
                        candidatePlates = candidates
                        isProcessing = false
                        showConfirmSheet = true
                    }
                }
            }
            .alert("Camera Access Needed", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable camera access in Settings to capture plates.")
            }
            .sheet(isPresented: $showConfirmSheet) {
                ConfirmEntryView(
                    image: camera.capturedImage,
                    candidates: candidatePlates,
                    location: locationService.lastLocation
                )
            }
        }
    }

    private func requestPermissions() {
        locationService.requestPermission()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        camera.configure()
                    } else {
                        showPermissionAlert = true
                    }
                }
            }
        default:
            showPermissionAlert = true
        }
    }

    private func capture() {
        isProcessing = true
        locationService.requestOneShotLocation()
        camera.capturePhoto()
    }
}
