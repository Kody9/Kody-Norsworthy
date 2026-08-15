import AVFoundation
import Combine
import CoreLocation
import SwiftData
import SwiftUI
import UIKit
import Vision

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
struct PendingDetection: Identifiable {
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
    /// Only for the BOLO watch-list check on the queue's quick-log path,
    /// which bypasses the Read screen (and its own BOLO check) entirely.
    @Query(sort: \PlateEntry.capturedAt, order: .reverse) private var allEntries: [PlateEntry]

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
    @StateObject private var photoZoomState = PhotoZoomState()

    @State private var previewSize: CGSize = .zero
    @State private var zoomGestureBaseline: CGFloat = 1.0
    @State private var isAutoScanEnabled = false
    @State private var autoScanTask: Task<Void, Never>?
    @State private var showQueueList = false
    /// Plate text -> when it was last queued. Suppresses re-queuing the same
    /// still-parked car on every 2s tick while scanning past it, without
    /// permanently blocking that plate for the rest of the session.
    @State private var recentAutoScanPlates: [String: Date] = [:]
    /// Plate text -> timestamps of recent (not-yet-queued) sightings, used
    /// only in ACCURATE mode -- see `autoScanFastMode`.
    @State private var recentSightings: [String: [Date]] = [:]
    @State private var pendingDetections: [PendingDetection] = []
    private let autoScanDedupWindow: TimeInterval = 60
    private let autoScanConsensusCount = 2
    private let autoScanConsensusWindow: TimeInterval = 3
    /// FAST trusts a single frame immediately (low confidence floor, `.fast`
    /// recognizer) so a car only in frame briefly still gets queued, at the
    /// cost of more wrong reads to correct. ACCURATE requires the same
    /// reading twice within `autoScanConsensusWindow` seconds and uses the
    /// slower, more careful recognizer -- fewer wrong reads, but a fast
    /// pass-by may not get caught at all. Set from Setup; which one is
    /// actually better depends on whether the phone is parked and watching
    /// or scanning while moving, so it's a toggle rather than a fixed choice.
    @AppStorage("autoScanFastMode") private var autoScanFastMode = true
    private var autoScanConfidenceThreshold: Float { autoScanFastMode ? 0.4 : 0.6 }

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
                    photoZoomState: photoZoomState,
                    onSave: saveEntry,
                    onRetake: { advanceReviewOrReset() }
                )
            case .saved:
                SavedConfirmationView(plateText: savedPlateText)
            case .manualEntry:
                ManualEntryView(
                    image: capturedImage,
                    photoZoomState: photoZoomState,
                    onLog: { text in beginRead(withManualText: text) },
                    onCancel: { phase = .camera }
                )
            case .noPlateFound:
                NoPlateFoundView(
                    image: capturedImage,
                    photoZoomState: photoZoomState,
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
            Task { await handleManualCapture(image: image) }
        }
        .fullScreenCover(isPresented: $showQueueList) {
            AutoScanQueueView(
                detections: pendingDetections,
                onQuickLog: quickLog,
                onReview: beginReviewing,
                onDiscard: { detection in pendingDetections.removeAll { $0.id == detection.id } },
                onClose: { showQueueList = false }
            )
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
                    let box = PlateFrameGeometry.boxRect(in: geo.size)
                    FramingBrackets()
                        .frame(width: box.width, height: box.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .onAppear { previewSize = geo.size }
                        .onChange(of: geo.size) { _, newSize in previewSize = newSize }
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

    /// Only appears once auto-scan has queued something. Tapping it opens a
    /// scrollable triage list of everything queued — nothing in it is ever
    /// saved without going through the Read screen.
    @ViewBuilder
    private var reviewQueueButton: some View {
        if !pendingDetections.isEmpty {
            Button { showQueueList = true } label: {
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
        // Capped at 6 so the row doesn't overcrowd/clip next to the caption
        // text sharing the same corner.
        [1, 2, 5, 10, 20, 30].filter { $0 <= camera.maxZoomFactor }
    }

    private func requestPermissions() {
        locationService.requestPermission()
        // Get a location fix in flight as soon as the camera appears,
        // not just at the moment of capture -- otherwise the very first
        // plate logged in a session can beat a cold GPS fix to the save
        // and end up with no coordinates (no map pin) even though every
        // capture after it has one.
        locationService.requestOneShotLocation()
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
        Haptics.capture()
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

    /// Grabs a silent frame and OCRs it, back-to-back with no fixed delay
    /// between attempts — the only throttle is however long "grab a frame +
    /// run OCR" actually takes, which is what lets this keep up with a
    /// moving vehicle instead of sampling once every couple of seconds and
    /// missing anything that passed through in between. A human reviews
    /// every result before anything saves regardless.
    ///
    /// A single confident-enough frame is trusted immediately — see
    /// `handleAutoScanFrame` — favoring catch-rate over precision, since a wrong
    /// read is a quick correction on the Read screen but a car that was
    /// never queued at all can't be corrected. Queuing does NOT interrupt
    /// what you're doing; review (and explicitly save or discard) happens
    /// later, via the REVIEW button.
    private func startAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = Task {
            var lastLocationRequest = Date.distantPast
            while !Task.isCancelled {
                guard isAutoScanEnabled, phase == .camera, camera.isConfigured else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                guard !isReading else {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }
                isReading = true
                // GPS doesn't update meaningfully faster than ~1/sec anyway
                // -- avoid hammering CLLocationManager every single pass.
                if Date.now.timeIntervalSince(lastLocationRequest) > 2 {
                    lastLocationRequest = Date.now
                    locationService.requestOneShotLocation()
                }
                guard let frame = await camera.captureFrameSilently() else {
                    isReading = false
                    continue
                }
                await handleAutoScanFrame(frame)
            }
        }
    }

    private func stopAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = nil
    }

    /// The framing-box region as a fraction of the live preview, or the
    /// whole frame if the preview's size hasn't been recorded yet.
    private var ocrFractionalBox: CGRect {
        guard previewSize != .zero else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return PlateFrameGeometry.fractionalBoxRect(in: previewSize)
    }

    /// Auto-scan's hot path: renders only the cropped framing-box region
    /// for OCR (cheap — see `CapturedVideoFrame`), and only renders the
    /// full frame if a detection actually clears the bar to be queued.
    private func handleAutoScanFrame(_ frame: CapturedVideoFrame) async {
        guard let ocrInput = frame.cropped(previewSize: previewSize, fractionalRect: ocrFractionalBox) else {
            isReading = false
            return
        }

        // Auto-scan's recognizer depends on the FAST/ACCURATE mode chosen
        // in Setup (`autoScanFastMode`).
        let recognitionLevel: VNRequestTextRecognitionLevel = autoScanFastMode ? .fast : .accurate
        let result = await withCheckedContinuation { continuation in
            PlateOCRService.recognizePlates(in: ocrInput, recognitionLevel: recognitionLevel) { result in
                continuation.resume(returning: result)
            }
        }

        isReading = false

        let now = Date.now
        guard
            let best = result.candidates.first,
            best.confidence >= autoScanConfidenceThreshold
        else {
            return
        }

        if !autoScanFastMode {
            var sightings = (recentSightings[best.text] ?? []).filter { now.timeIntervalSince($0) < autoScanConsensusWindow }
            sightings.append(now)
            recentSightings[best.text] = sightings
            recentSightings = recentSightings.filter { !$0.value.isEmpty }
            guard sightings.count >= autoScanConsensusCount else { return }
            recentSightings[best.text] = nil
        }

        if let lastSeen = recentAutoScanPlates[best.text], now.timeIntervalSince(lastSeen) < autoScanDedupWindow {
            return
        }
        recentAutoScanPlates[best.text] = now
        recentAutoScanPlates = recentAutoScanPlates.filter { now.timeIntervalSince($0.value) < autoScanDedupWindow }
        Haptics.queued()
        pendingDetections.append(PendingDetection(
            candidates: result.candidates,
            image: frame.fullImage(),
            location: locationService.lastLocation,
            detectedState: result.detectedState
        ))
        if pendingDetections.count > 20 {
            pendingDetections.removeFirst()
        }
    }

    /// The manual "READ PLATE" path: not time-pressured the way auto-scan
    /// is, so it always uses `.accurate` and always renders the full frame
    /// (there's no queue here — it goes straight to the Read screen).
    private func handleManualCapture(image: UIImage) async {
        let ocrInput = image.croppedToPreviewRegion(previewSize: previewSize, fractionalRect: ocrFractionalBox)
        let result = await withCheckedContinuation { continuation in
            PlateOCRService.recognizePlates(in: ocrInput, recognitionLevel: .accurate) { result in
                continuation.resume(returning: result)
            }
        }

        isReading = false
        capturedImage = image
        capturedLocation = locationService.lastLocation
        photoZoomState.reset()
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

    /// Logs a queued detection straight to history exactly as read — the
    /// triage list's fast path for a thumbnail + reading that's obviously
    /// right at a glance. Still a deliberate, per-plate human decision (the
    /// DONE tap for that specific row), just made from the list instead of
    /// the full Read screen; nothing here bypasses that.
    private func quickLog(_ detection: PendingDetection) {
        guard let text = detection.candidates.first?.text, !text.isEmpty else { return }
        let plateNumber = text.uppercased()
        pendingDetections.removeAll { $0.id == detection.id }
        // Checked before inserting, since this path never shows the Read
        // screen (and its own BOLO banner) at all -- a haptic warning here
        // is the only signal this plate matched a watch-listed one.
        let matchesBOLO = allEntries.contains { $0.plateNumber == plateNumber && $0.tag == "BOLO" }
        let entry = PlateEntry(
            plateNumber: plateNumber,
            state: detection.detectedState ?? "Unknown",
            latitude: detection.location?.coordinate.latitude,
            longitude: detection.location?.coordinate.longitude,
            tag: "BOLO",
            photoData: detection.image?.jpegData(compressionQuality: 0.7)
        )
        modelContext.insert(entry)
        matchesBOLO ? Haptics.boloMatch() : Haptics.logged()
    }

    /// Pulls one specific queued detection (picked from the triage list)
    /// into the Read screen for review.
    private func beginReviewing(_ detection: PendingDetection) {
        pendingDetections.removeAll { $0.id == detection.id }
        candidates = detection.candidates
        selectedIndex = 0
        selectedTag = "BOLO"
        isManualEntry = false
        capturedImage = detection.image
        capturedLocation = detection.location
        photoZoomState.reset()
        detectedState = detection.detectedState
        showQueueList = false
        phase = .read
    }

    /// Called after saving or discarding a Read-screen entry: back to the
    /// triage list if there's more queued, otherwise back to the camera.
    private func advanceReviewOrReset() {
        resetToCamera()
        if !pendingDetections.isEmpty {
            showQueueList = true
        }
    }

    private func beginRead(withManualText text: String) {
        candidates = [PlateOCRService.Candidate(text: text, confidence: 1.0)]
        selectedIndex = 0
        selectedTag = "BOLO"
        isManualEntry = true
        // If this came from "No plate found" -> "Type the plate," a real
        // photo of the vehicle already exists from that failed OCR attempt
        // -- keep it instead of discarding it just because OCR couldn't
        // read the plate off it. Only reaching manual entry with no prior
        // capture (straight from the camera's TYPE IT IN button, or
        // camera-denied) has nothing to preserve.
        if capturedImage == nil {
            capturedLocation = locationService.lastLocation
        }
        detectedState = nil
        phase = .read
    }

    private func saveEntry(plateText: String, tag: String, state: String, driverName: String) {
        let entry = PlateEntry(
            plateNumber: plateText.uppercased(),
            state: state,
            latitude: capturedLocation?.coordinate.latitude,
            longitude: capturedLocation?.coordinate.longitude,
            tag: tag,
            driverName: driverName.trimmingCharacters(in: .whitespaces),
            photoData: capturedImage?.jpegData(compressionQuality: 0.7)
        )
        modelContext.insert(entry)
        Haptics.logged()

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
        photoZoomState.reset()
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
