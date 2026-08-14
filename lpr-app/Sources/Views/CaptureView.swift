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

    @State private var zoomGestureBaseline: CGFloat = 1.0
    @State private var isAutoScanEnabled = false
    @State private var isAutoScanCapture = false
    @State private var autoScanTask: Task<Void, Never>?
    @State private var recentAutoScanPlates: [String] = []

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
        .onDisappear {
            camera.stop()
            stopAutoScan()
        }
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
                    HStack {
                        Spacer()
                        autoScanToggle
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text("LIVE CAMERA · REAR WIDE\nHOLD PLATE INSIDE THE MARKS")
                            .plType(.technicalCaption)
                            .foregroundStyle(PLColor.inkTertiary)
                            .lineSpacing(3)
                        Spacer()
                        zoomControls
                    }
                    .padding(PLSpacing.gutter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .top)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        camera.setZoom(zoomGestureBaseline * value)
                    }
                    .onEnded { _ in
                        zoomGestureBaseline = camera.zoomFactor
                    }
            )

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
                    isDisabled: isReading || !camera.isConfigured
                ) {
                    capture()
                }
                PLSecondaryButton(["TYPE", "IT IN"]) {
                    phase = .manualEntry
                }
            }
            .padding(PLSpacing.gutter)
        }
        .background(PLColor.ground)
    }

    private var autoScanToggle: some View {
        Button(action: toggleAutoScan) {
            Text(isAutoScanEnabled ? "AUTO-SCAN · ON" : "AUTO-SCAN")
                .plType(PLTypeStyle(.heavy, 11, trackingEm: 0.08))
                .foregroundStyle(isAutoScanEnabled ? PLColor.ground : PLColor.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isAutoScanEnabled ? PLColor.accentOnDark : PLColor.surface.opacity(0.85))
        }
        .buttonStyle(.plain)
        .padding(PLSpacing.gutter)
    }

    private var zoomControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(String(format: "%.1f×", camera.zoomFactor))
                .plType(PLTypeStyle(.bold, 11, trackingEm: 0.04))
                .foregroundStyle(PLColor.ink)
            HStack(spacing: 2) {
                ForEach(zoomPresets, id: \.self) { level in
                    Button {
                        camera.setZoom(level)
                        zoomGestureBaseline = level
                    } label: {
                        Text("\(Int(level))×")
                            .plType(PLTypeStyle(.bold, 12))
                            .foregroundStyle(PLColor.ink)
                            .frame(width: 34, height: 34)
                            .background(PLColor.surface.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var zoomPresets: [CGFloat] {
        [1, 2, 3].filter { $0 <= camera.maxZoomFactor }
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

    private func capture(auto: Bool = false) {
        isAutoScanCapture = auto
        isReading = true
        locationService.requestOneShotLocation()
        camera.capturePhoto()
    }

    private func toggleAutoScan() {
        isAutoScanEnabled.toggle()
        if isAutoScanEnabled {
            startAutoScan()
        } else {
            stopAutoScan()
        }
    }

    /// Periodically captures and OCRs in the background so you can drive or
    /// walk past plates without tapping for each one. Only interrupts with
    /// the Read screen for a confident, not-recently-seen plate — misses and
    /// repeat reads of the same still-parked car are silently discarded so
    /// scanning doesn't stall. Every surfaced read still requires LOG PLATE
    /// to actually save; nothing is logged automatically.
    private func startAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard isAutoScanEnabled, phase == .camera, !isReading, camera.isConfigured else { continue }
                capture(auto: true)
            }
        }
    }

    private func stopAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = nil
    }

    private func handleCaptured(image: UIImage) {
        let isAuto = isAutoScanCapture
        isAutoScanCapture = false
        PlateOCRService.recognizePlates(in: image) { result in
            DispatchQueue.main.async {
                isReading = false

                if isAuto {
                    guard
                        let best = result.candidates.first,
                        best.confidence >= 0.6,
                        !recentAutoScanPlates.contains(best.text)
                    else {
                        return
                    }
                    recentAutoScanPlates.append(best.text)
                    if recentAutoScanPlates.count > 8 {
                        recentAutoScanPlates.removeFirst()
                    }
                }

                capturedImage = image
                capturedLocation = locationService.lastLocation
                if result.candidates.isEmpty {
                    if !isAuto {
                        phase = .noPlateFound
                    }
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
