import CoreLocation
import SwiftData
import SwiftUI
import UIKit

/// Confirm-in-place: the same screen shows the read at display size, ranked
/// alternates, tag chips, and a full-width commit bar. Not a sheet — no
/// keyboard, no scrolling to reach Save on a typical device.
struct ReadEntryView: View {
    let image: UIImage?
    let candidates: [PlateOCRService.Candidate]
    @Binding var selectedIndex: Int
    @Binding var selectedTag: String
    let location: CLLocation?
    let detectedState: String?
    let isManualEntry: Bool
    @ObservedObject var photoZoomState: PhotoZoomState
    let onSave: (String, String, String) -> Void
    let onRetake: () -> Void

    @Query(sort: \PlateEntry.capturedAt, order: .reverse) private var allEntries: [PlateEntry]

    @State private var correctedText: String?
    @State private var showCorrectionEditor = false
    @State private var correctedState: String?
    @State private var showStatePicker = false
    @State private var showZoomedPhoto = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private let tags = ["General", "BOLO", "Suspicious", "Parking Complaint", "Follow-up"]

    private var selectedCandidate: PlateOCRService.Candidate? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }

    /// What actually gets displayed and saved — a manual correction wins
    /// over whatever OCR picked.
    private var displayedText: String? {
        correctedText ?? selectedCandidate?.text
    }

    private var confidence: Float { selectedCandidate?.confidence ?? 0 }
    /// A human just verified this by typing it — no more OCR uncertainty.
    private var effectiveConfidence: Float { correctedText != nil ? 1.0 : confidence }
    private var isLowConfidence: Bool { correctedText == nil && !isManualEntry && confidence < 0.80 }
    private var readLabel: String {
        if correctedText != nil { return "CORRECTED" }
        return isManualEntry ? "MANUAL ENTRY" : "ON-DEVICE OCR"
    }

    /// A manual pick wins over whatever (if anything) auto-detection found.
    private var displayedState: String {
        correctedState ?? detectedState ?? "Unknown"
    }

    /// Most recent existing entry for this exact plate text, if any — lets
    /// the Read screen flag a repeat before a second entry for the same car
    /// gets saved, rather than only surfacing it later in History.
    private var priorSighting: PlateEntry? {
        guard let text = displayedText?.uppercased(), !text.isEmpty else { return nil }
        return allEntries.first { $0.plateNumber == text }
    }

    private func priorSightingMessage(_ entry: PlateEntry) -> String {
        let relative = Self.relativeFormatter.localizedString(for: entry.capturedAt, relativeTo: .now)
        return "ALREADY LOGGED \(relative.uppercased()) — TAGGED \(entry.tag.uppercased())"
    }

    /// Once zoomed in on this photo (here or from the correction editor),
    /// show that same zoomed-in crop in the strip instead of the full
    /// un-zoomed frame — no need to re-zoom just to keep looking at it.
    private var previewImage: UIImage? {
        guard let image else { return nil }
        guard let rect = photoZoomState.normalizedVisibleRect else { return image }
        return image.cropped(toNormalizedRect: rect) ?? image
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    capturedFrame
                    readBlock
                    if candidates.count > 1 {
                        alternateReads
                    }
                    tagSection
                }
            }
            actionRow
        }
        .background(PLColor.ground)
        .fullScreenCover(isPresented: $showCorrectionEditor) {
            ManualEntryView(
                initialText: displayedText ?? "",
                title: "CORRECT READ",
                primaryLabel: "USE THIS",
                primarySubLabel: nil,
                image: image,
                photoZoomState: photoZoomState,
                onLog: { text in
                    correctedText = text
                    showCorrectionEditor = false
                },
                onCancel: { showCorrectionEditor = false }
            )
        }
        .fullScreenCover(isPresented: $showStatePicker) {
            StatePickerView(
                onSelect: { state in
                    correctedState = state
                    showStatePicker = false
                },
                onCancel: { showStatePicker = false }
            )
        }
        .fullScreenCover(isPresented: $showZoomedPhoto) {
            if let image {
                PhotoZoomView(image: image, zoomState: photoZoomState, onDone: { showZoomedPhoto = false })
            }
        }
    }

    private var capturedFrame: some View {
        Button {
            if image != nil { showZoomedPhoto = true }
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let previewImage {
                    Color.black
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .grayscale(1.0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Rectangle().fill(PLColor.surface)
                }
                Text("CAPTURED FRAME \(Date.now.formatted(.dateTime.hour().minute().second()))")
                    .plType(.technicalCaption)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(12)
                if image != nil {
                    Text("TAP TO ZOOM")
                        .plType(PLTypeStyle(.bold, 10, trackingEm: 0.08))
                        .foregroundStyle(PLColor.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.6))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var readBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("READ").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Text(readLabel)
                    .plType(PLTypeStyle(.bold, 10, trackingEm: 0.1))
                    .foregroundStyle(PLColor.accentOnDark)
            }

            Text(displayedText ?? "—")
                .plType(.plateDisplay)
                .foregroundStyle(PLColor.ink)
                .padding(.top, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(PLColor.surfaceAlt)
                        Rectangle()
                            .fill(PLColor.accentOnDark)
                            .frame(width: geo.size.width * CGFloat(effectiveConfidence))
                    }
                }
                .frame(height: 6)
                Text("\(Int(effectiveConfidence * 100))%")
                    .plType(PLTypeStyle(.bold, 12))
                    .foregroundStyle(PLColor.ink)
            }
            .padding(.top, 8)

            if isLowConfidence {
                Text("LOW CONFIDENCE — VERIFY AGAINST THE PHOTO BEFORE SAVING")
                    .plType(PLTypeStyle(.bold, 11, trackingEm: 0.04))
                    .foregroundStyle(PLColor.accentOnDark)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(PLColor.accentOnDark, lineWidth: PLSpacing.ruleWidth))
                    .padding(.top, 10)
            }

            if let priorSighting {
                Text(priorSightingMessage(priorSighting))
                    .plType(PLTypeStyle(.bold, 11, trackingEm: 0.04))
                    .foregroundStyle(PLColor.ink)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PLColor.surfaceAlt)
                    .padding(.top, 10)
            }

            manualOverrideButton
                .padding(.top, 12)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.top, PLSpacing.gutter)
        .padding(.bottom, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
        }
    }

    /// Always visible, not just when confidence is low — a tight OCR crop
    /// on the framing box often surfaces exactly one reading with nothing
    /// to pick between in `alternateReads`, so this is the one guaranteed
    /// way to override a wrong read by hand, on every Read screen visit
    /// (a live capture, a queued auto-scan detection, or manual entry).
    private var manualOverrideButton: some View {
        Button {
            showCorrectionEditor = true
        } label: {
            HStack {
                Text("NOT RIGHT? TYPE THE PLATE")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                Spacer()
                Text("→")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
            }
            .foregroundStyle(PLColor.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .overlay(Rectangle().stroke(PLColor.fieldBorderStrong, lineWidth: PLSpacing.ruleWidth))
        }
        .buttonStyle(.plain)
    }

    private var alternateReads: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Text("ALTERNATE READS").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                let isSelected = index == selectedIndex
                Button {
                    selectedIndex = index
                    correctedText = nil
                } label: {
                    HStack {
                        Text(candidate.text).plType(.candidate)
                        Spacer()
                        Text("\(Int(candidate.confidence * 100))%").plType(PLTypeStyle(.semibold, 12, trackingEm: 0.06))
                    }
                    .foregroundStyle(isSelected ? .white : PLColor.ink)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .background(isSelected ? PLColor.accent : Color.clear)
                    .overlay(Rectangle().stroke(isSelected ? PLColor.accent : PLColor.fieldBorder, lineWidth: PLSpacing.ruleWidth))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PLSpacing.md)
        .padding(.horizontal, PLSpacing.xs)
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Text("TAG").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Button {
                    showStatePicker = true
                } label: {
                    Text(locationLabel)
                        .underline()
                        .plType(PLTypeStyle(.bold, 10, trackingEm: 0.1))
                        .foregroundStyle(PLColor.inkTertiary)
                }
                .buttonStyle(.plain)
            }
            FlowLayout(spacing: PLSpacing.sm) {
                ForEach(tags, id: \.self) { tag in
                    let isSelected = tag == selectedTag
                    Button {
                        selectedTag = tag
                    } label: {
                        Text(chipLabel(for: tag))
                            .plType(PLTypeStyle(.bold, 13, trackingEm: 0.03))
                            .foregroundStyle(isSelected ? PLColor.ground : PLColor.inkSecondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(isSelected ? PLColor.ink : Color.clear)
                            .overlay(Rectangle().stroke(isSelected ? Color.clear : PLColor.fieldBorder, lineWidth: PLSpacing.ruleWidth))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(PLSpacing.md)
        .padding(.horizontal, PLSpacing.xs)
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 2) {
            PLPrimaryButton(
                "LOG PLATE",
                subLabel: "GPS + TIMESTAMP ATTACHED",
                isDisabled: displayedText == nil
            ) {
                if let text = displayedText {
                    onSave(text, selectedTag, displayedState)
                }
            }
            PLSecondaryButton(["RE", "SHOOT"], action: onRetake)
        }
        .padding(PLSpacing.gutter)
    }

    private var locationLabel: String {
        let state = displayedState.uppercased()
        guard let location else { return state }
        return String(format: "%@ · %.4f, %.4f", state, location.coordinate.latitude, location.coordinate.longitude)
    }

    private func chipLabel(for tag: String) -> String {
        tag == "Parking Complaint" ? "PARKING" : tag.uppercased()
    }
}

/// Minimal wrapping row layout for tag chips (SwiftUI has no built-in flow
/// layout prior to a custom Layout conformance).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
