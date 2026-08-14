import CoreLocation
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
    let onSave: (String, String) -> Void
    let onRetake: () -> Void

    @State private var correctedText: String?
    @State private var showCorrectionEditor = false

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
                onLog: { text in
                    correctedText = text
                    showCorrectionEditor = false
                },
                onCancel: { showCorrectionEditor = false }
            )
        }
    }

    private var capturedFrame: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .grayscale(1.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle().fill(PLColor.surface)
            }
            Text("CAPTURED FRAME \(Date.now.formatted(.dateTime.hour().minute().second()))")
                .plType(.technicalCaption)
                .foregroundStyle(PLColor.inkTertiary)
                .padding(12)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var readBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("READ").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Button {
                    showCorrectionEditor = true
                } label: {
                    Text("EDIT")
                        .underline()
                        .plType(PLTypeStyle(.bold, 10, trackingEm: 0.1))
                        .foregroundStyle(PLColor.ink)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
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
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.top, PLSpacing.gutter)
        .padding(.bottom, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
        }
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
                Text(locationLabel)
                    .plType(PLTypeStyle(.bold, 10, trackingEm: 0.1))
                    .foregroundStyle(PLColor.inkTertiary)
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
                    onSave(text, selectedTag)
                }
            }
            PLSecondaryButton(["RE", "SHOOT"], action: onRetake)
        }
        .padding(PLSpacing.gutter)
    }

    private var locationLabel: String {
        let state = (detectedState ?? "Unknown").uppercased()
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
