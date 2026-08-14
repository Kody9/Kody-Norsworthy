import SwiftUI

/// Gloved / no-camera fallback. Near-black, oversized keys, 8-character
/// cap, plate echoed at display size. Reused from the capture flow's
/// "TYPE IT IN" path, the no-read / camera-denied edge states, and as the
/// Read screen's plate-text correction editor (pre-filled, different
/// button copy, doesn't imply logging yet).
struct ManualEntryView: View {
    var initialText: String = ""
    var title: String = "MANUAL ENTRY"
    var primaryLabel: String = "LOG PLATE"
    var primarySubLabel: String? = "GPS + TIMESTAMP ATTACHED"
    let onLog: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(
        initialText: String = "",
        title: String = "MANUAL ENTRY",
        primaryLabel: String = "LOG PLATE",
        primarySubLabel: String? = "GPS + TIMESTAMP ATTACHED",
        onLog: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialText = initialText
        self.title = title
        self.primaryLabel = primaryLabel
        self.primarySubLabel = primarySubLabel
        self.onLog = onLog
        self.onCancel = onCancel
        _text = State(initialValue: initialText.uppercased())
    }

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
                Text(title)
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.accentOnDark)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 12)

            // Scrollable so nothing clips in landscape or on smaller
            // screens — the grid alone is ~340pt tall, which doesn't fit a
            // landscape iPhone's ~375-430pt height alongside everything else.
            ScrollView {
                VStack(spacing: 0) {
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

                    Text("Screen is held at minimum luminance in this mode; no white fields, no flash.")
                        .plType(.body)
                        .foregroundStyle(PLColor.inkTertiary.opacity(0.8))
                        .padding(PLSpacing.gutter)
                }
            }

            PLPrimaryButton(
                primaryLabel,
                subLabel: primarySubLabel,
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
