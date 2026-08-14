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

/// A plate auto-scan found but hasn't been reviewed yet. Nothing here is
/// saved — it only becomes a PlateEntry once a human looks at it on the
/// Read screen and taps LOG PLATE, same as any other capture.
private struct PendingDetection: Identifiable {
    let id = UUID()
    let candidates: [PlateOCRService.Candidate]
    let image: UIImage?
    let location: CLLocation?
    let detectedState: String?
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
    @State private var autoScanTask: Task<Void, Never>?
    @State private var recentAutoScanPlates: [String] = []
    @State private var pendingDetections: [PendingDetection] = []

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
                    onRetake: { advanceReviewOrReset() }
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
            handleCaptured(image: image, isAuto: false)
        }
    }

    private var cameraPhase: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    if camera.isConfigured {
                        CameraPreview(session: camera.session)
                    } else {
                        Color.black
                    }
                }
                .ignoresSafeArea(edges: .top)

                GeometryReader { geo in
                    // Based on the shorter screen dimension so the framing
                    // box stays a sensible, plate-shaped size in landscape
                    // too, instead of stretching edge-to-edge on the long
                    // axis the way a naive geo.size.width-based box would.
                    let shortSide = min(geo.size.width, geo.size.height)
                    let width = min(geo.size.width - 96, shortSide * 1.4)
                    let height = min(width * 0.5, geo.size.height - 120)
                    FramingBrackets()
                        .frame(width: max(width, 0), height: max(height, 0))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .ignoresSafeArea(edges: .top)

                // Controls stay inside the normal safe area (below the
                // Dynamic Island / status bar, clear of the Control Center
                // swipe zone at the very top edge) even though the camera
                // feed behind them bleeds full-screen.
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            autoScanToggle
                            reviewQueueButton
                        }
                        .padding(PLSpacing.gutter)
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
    }

    /// Only appears once auto-scan has queued something. Tapping it starts
    /// reviewing the queue one plate at a time on the Read screen — nothing
    /// in the queue is ever saved without going through that screen.
    @ViewBuilder
    private var reviewQueueButton: some View {
        if !pendingDetections.isEmpty {
            Button(action: startReviewingQueue) {
                Text("REVIEW · \(pendingDetections.count)")
                    .plType(PLTypeStyle(.heavy, 11, trackingEm: 0.08))
                    .foregroundStyle(PLColor.ground)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(PLColor.ink)
            }
            .buttonStyle(.plain)
        }
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
        [1, 2, 3, 5, 10].filter { $0 <= camera.maxZoomFactor }
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

    private func toggleAutoScan() {
        isAutoScanEnabled.toggle()
        if isAutoScanEnabled {
            startAutoScan()
        } else {
            stopAutoScan()
        }
    }

    /// Periodically grabs a silent frame and OCRs it in the background, so
    /// you don't have to tap for each passing car (and it doesn't click the
    /// shutter every couple of seconds — see captureFrameSilently). A
    /// confident, not-recently-seen plate goes into `pendingDetections`; it
    /// does NOT interrupt what you're doing. Review (and explicitly save or
    /// discard) happens later, via the REVIEW button. Nothing is ever saved
    /// without that step.
    private func startAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard isAutoScanEnabled, phase == .camera, !isReading, camera.isConfigured else { continue }
                isReading = true
                camera.captureFrameSilently { image in
                    guard let image else {
                        isReading = false
                        return
                    }
                    handleCaptured(image: image, isAuto: true)
                }
            }
        }
    }

    private func stopAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = nil
    }

    private func handleCaptured(image: UIImage, isAuto: Bool) {
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
                    pendingDetections.append(PendingDetection(
                        candidates: result.candidates,
                        image: image,
                        location: locationService.lastLocation,
                        detectedState: result.detectedState
                    ))
                    if pendingDetections.count > 20 {
                        pendingDetections.removeFirst()
                    }
                    return
                }

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

    /// Pops the next queued detection into the Read screen for review.
    private func startReviewingQueue() {
        guard !pendingDetections.isEmpty else { return }
        let next = pendingDetections.removeFirst()
        candidates = next.candidates
        selectedIndex = 0
        selectedTag = "BOLO"
        isManualEntry = false
        capturedImage = next.image
        capturedLocation = next.location
        detectedState = next.detectedState
        phase = .read
    }

    /// Called after saving or discarding a Read-screen entry: keeps working
    /// through the queue if there's more, otherwise returns to the camera.
    private func advanceReviewOrReset() {
        if !pendingDetections.isEmpty {
            startReviewingQueue()
        } else {
            resetToCamera()
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
            advanceReviewOrReset()
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
