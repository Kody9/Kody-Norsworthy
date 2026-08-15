import SwiftUI
import UIKit

/// Fast triage for everything auto-scan has queued up, instead of stepping
/// through the full Read screen one at a time.
///
/// DONE logs that one detection immediately, exactly as read (top OCR
/// candidate, BOLO tag, GPS + photo already attached) — for the common case
/// where the thumbnail and reading are obviously correct at a glance. It's
/// still a deliberate, per-plate human decision, just made from this list
/// instead of the full screen; nothing is ever saved without this or
/// REVIEW's LOG PLATE being tapped for that specific entry. REVIEW opens
/// the full Read screen instead, for anything that needs a correction, a
/// different tag, or a second look. DISCARD drops it without saving.
struct AutoScanQueueView: View {
    let detections: [PendingDetection]
    let onQuickLog: (PendingDetection) -> Void
    let onReview: (PendingDetection) -> Void
    let onDiscard: (PendingDetection) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("QUEUE · \(detections.count)")
                    .plType(PLTypeStyle(.heavy, 13, trackingEm: 0.06))
                    .foregroundStyle(PLColor.accentOnDark)
                Spacer()
                Button("CLOSE", action: onClose)
                    .buttonStyle(.plain)
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.ink)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }

            if detections.isEmpty {
                Spacer()
                Text("QUEUE EMPTY")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                    .foregroundStyle(PLColor.inkTertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(detections) { detection in
                            row(for: detection)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PLColor.ground)
    }

    private func row(for detection: PendingDetection) -> some View {
        HStack(spacing: PLSpacing.md) {
            Group {
                if let image = detection.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .grayscale(1.0)
                } else {
                    PLColor.surface
                }
            }
            .frame(width: 60, height: 60)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(detection.candidates.first?.text ?? "—")
                    .plType(PLTypeStyle(.heavy, 18, trackingEm: 0.02))
                    .foregroundStyle(PLColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let confidence = detection.candidates.first?.confidence {
                    Text("\(Int(confidence * 100))% CONFIDENCE")
                        .plType(PLTypeStyle(.bold, 10, trackingEm: 0.06))
                        .foregroundStyle(PLColor.inkTertiary)
                }
            }

            Spacer(minLength: PLSpacing.sm)

            VStack(alignment: .trailing, spacing: 6) {
                Button { onQuickLog(detection) } label: {
                    Text("DONE")
                        .plType(PLTypeStyle(.bold, 11, trackingEm: 0.06))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PLColor.accent)
                }
                .buttonStyle(.plain)
                .disabled(detection.candidates.first == nil)
                .opacity(detection.candidates.first == nil ? 0.4 : 1)

                Button { onReview(detection) } label: {
                    Text("REVIEW")
                        .plType(PLTypeStyle(.bold, 11, trackingEm: 0.06))
                        .foregroundStyle(PLColor.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(PLColor.fieldBorderStrong, lineWidth: PLSpacing.ruleWidth))
                }
                .buttonStyle(.plain)

                Button { onDiscard(detection) } label: {
                    Text("DISCARD")
                        .underline()
                        .plType(PLTypeStyle(.bold, 10, trackingEm: 0.06))
                        .foregroundStyle(PLColor.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.vertical, PLSpacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }
}
