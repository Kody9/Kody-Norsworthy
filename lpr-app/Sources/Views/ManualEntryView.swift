import SwiftUI

/// Gloved / no-camera fallback. Near-black, oversized keys, 8-character
/// cap, plate echoed at display size. Reused from the capture flow's
/// "TYPE IT IN" path and from the no-read / camera-denied edge states.
struct ManualEntryView: View {
    let onLog: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""

    private let characterLimit = 8
    private let keys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("CANCEL", action: onCancel)
                    .buttonStyle(.plain)
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Text("MANUAL ENTRY")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.accentOnDark)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("PLATE")
                    .plType(.sectionLabel)
                    .foregroundStyle(PLColor.inkTertiary)
                HStack(spacing: 0) {
                    Text(text)
                    Text("|").foregroundStyle(PLColor.accentOnDark)
                }
                .plType(.plateDisplayLarge)
                .foregroundStyle(PLColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.bottom, 18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        if text.count < characterLimit {
                            text.append(key)
                        }
                    } label: {
                        Text(String(key))
                            .plType(PLTypeStyle(.heavy, 20))
                            .foregroundStyle(PLColor.ink)
                            .frame(height: 56)
                            .frame(maxWidth: .infinity)
                            .background(PLColor.surface)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.top, PLSpacing.gutter)
            .padding(.bottom, PLSpacing.sm)

            HStack(spacing: 2) {
                Button {
                    if !text.isEmpty { text.removeLast() }
                } label: {
                    Text("DELETE")
                        .plType(PLTypeStyle(.heavy, 14, trackingEm: 0.06))
                        .foregroundStyle(PLColor.ink)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PLSpacing.gutter)
                        .background(PLColor.surface)
                }
                .buttonStyle(.plain)

                Button {
                    text = ""
                } label: {
                    Text("CLEAR")
                        .plType(PLTypeStyle(.heavy, 14, trackingEm: 0.06))
                        .foregroundStyle(PLColor.ink)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PLSpacing.gutter)
                        .background(PLColor.surface)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PLSpacing.gutter)

            Spacer()

            Text("Screen is held at minimum luminance in this mode; no white fields, no flash.")
                .plType(.body)
                .foregroundStyle(PLColor.inkTertiary.opacity(0.8))
                .padding(PLSpacing.gutter)

            PLPrimaryButton(
                "LOG PLATE",
                subLabel: "GPS + TIMESTAMP ATTACHED",
                isDisabled: text.isEmpty
            ) {
                onLog(text)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.bottom, PLSpacing.gutter)
        }
        .background(PLColor.groundNight)
    }
}
