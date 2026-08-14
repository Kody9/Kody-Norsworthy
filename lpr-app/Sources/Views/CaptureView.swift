import AVFoundation
import Combine
import CoreLocation
import SwiftData
import SwiftUI
import UIKit

enum CapturePhase {
    case camera
    case read
    case saved
    case manualEntry
    case noPlateFound
    case cameraDenied
}

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var camera = CameraController()
    @StateObject private var locationService = LocationService()

    @State private var phase: CapturePhase = .camera
    @State private var isReading = false
    @State private var candidates: [PlateOCRService.Candidate] = []
    @State private var selectedIndex = 0
    @State private var selectedTag = "BOLO"
    @State private var isManualEntry = false
    @State private var capturedImage: UIImage?
    @State private var capturedLocation: CLLocation?
    @State private var detectedState: String?
    @State private var savedPlateText = ""

    var body: some View {
        Group {
            switch phase {
            case .camera:
                cameraPhase
            case .read:
                ReadEntryView(
                    image: capturedImage,
                    candidates: candidates,
                    selectedIndex: $selectedIndex,
                    selectedTag: $selectedTag,
                    location: capturedLocation,
                    detectedState: detectedState,
                    isManualEntry: isManualEntry,
                    onSave: saveEntry,
                    onRetake: { resetToCamera() }
                )
            case .saved:
                SavedConfirmationView(plateText: savedPlateText)
            case .manualEntry:
                ManualEntryView(
                    onLog: { text in beginRead(withManualText: text) },
                    onCancel: { phase = .camera }
                )
            case .noPlateFound:
                NoPlateFoundView(
                    image: capturedImage,
                    onReshoot: { resetToCamera() },
                    onTypeIt: { phase = .manualEntry }
                )
            case .cameraDenied:
                CameraDeniedView(
                    locationStatus: locationService.authorizationStatus,
                    onOpenSettings: openSystemSettings,
                    onTypeInstead: { phase = .manualEntry }
                )
            }
        }
        .onAppear(perform: requestPermissions)
        .onDisappear { camera.stop() }
        .onReceive(camera.$capturedImage.compactMap { $0 }) { image in
            handleCaptured(image: image)
        }
    }

    private var cameraPhase: some View {
        VStack(spacing: 0) {
            ZStack {
                if camera.isConfigured {
                    CameraPreview(session: camera.session)
                } else {
                    Color.black
                }

                GeometryReader { geo in
                    let width = geo.size.width - 96
                    let height = width * 0.5
                    FramingBrackets()
                        .frame(width: width, height: height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                VStack {
                    Spacer()
                    HStack {
                        Text("LIVE CAMERA · REAR WIDE\nHOLD PLATE INSIDE THE MARKS")
                            .plType(.technicalCaption)
                            .foregroundStyle(PLColor.inkTertiary)
                            .lineSpacing(3)
                        Spacer()
                    }
                    .padding(PLSpacing.gutter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .top)

            if isReading {
                HStack {
                    Text("READING PLATE…")
                        .plType(PLTypeStyle(.heavy, 13, trackingEm: 0.1))
                        .foregroundStyle(PLColor.accentOnDark)
                    Spacer()
                }
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.vertical, 14)
                .background(PLColor.ground)
                .overlay(alignment: .top) {
                    Rectangle().fill(PLColor.accentOnDark).frame(height: PLSpacing.ruleWidth)
                }
            }

            HStack(spacing: 2) {
                PLPrimaryButton(
                    "READ PLATE",
                    subLabel: "ON DEVICE · NOTHING UPLOADED",
                    isDisabled: isReading || !camera.isConfigured,
                    action: capture
                )
                PLSecondaryButton(["TYPE", "IT IN"]) {
                    phase = .manualEntry
                }
            }
            .padding(PLSpacing.gutter)
        }
        .background(PLColor.ground)
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
                        phase = .cameraDenied
                    }
                }
            }
        default:
            phase = .cameraDenied
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func capture() {
        isReading = true
        locationService.requestOneShotLocation()
        camera.capturePhoto()
    }

    private func handleCaptured(image: UIImage) {
        PlateOCRService.recognizePlates(in: image) { result in
            DispatchQueue.main.async {
                isReading = false
                capturedImage = image
                capturedLocation = locationService.lastLocation
                if result.candidates.isEmpty {
                    phase = .noPlateFound
                } else {
                    candidates = result.candidates
                    selectedIndex = 0
                    selectedTag = "BOLO"
                    isManualEntry = false
                    detectedState = result.detectedState
                    phase = .read
                }
            }
        }
    }

    private func beginRead(withManualText text: String) {
        candidates = [PlateOCRService.Candidate(text: text, confidence: 1.0)]
        selectedIndex = 0
        selectedTag = "BOLO"
        isManualEntry = true
        capturedImage = nil
        capturedLocation = locationService.lastLocation
        detectedState = nil
        phase = .read
    }

    private func saveEntry(plateText: String, tag: String) {
        let entry = PlateEntry(
            plateNumber: plateText.uppercased(),
            state: detectedState ?? "Unknown",
            latitude: capturedLocation?.coordinate.latitude,
            longitude: capturedLocation?.coordinate.longitude,
            tag: tag,
            photoData: capturedImage?.jpegData(compressionQuality: 0.7)
        )
        modelContext.insert(entry)

        savedPlateText = plateText.uppercased()
        phase = .saved
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            resetToCamera()
        }
    }

    private func resetToCamera() {
        candidates = []
        selectedIndex = 0
        isManualEntry = false
        capturedImage = nil
        capturedLocation = nil
        detectedState = nil
        phase = .camera
    }
}

private struct CornerMark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PLColor.accentOnDark).frame(width: 28, height: 3)
            Rectangle().fill(PLColor.accentOnDark).frame(width: 3, height: 24)
        }
    }
}

/// Four L-shaped alignment guides. Purely visual — capture is never gated
/// on the plate actually being inside them.
struct FramingBrackets: View {
    var body: some View {
        ZStack {
            CornerMark()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CornerMark()
                .rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            CornerMark()
                .rotationEffect(.degrees(-90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            CornerMark()
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .allowsHitTesting(false)
    }
}
