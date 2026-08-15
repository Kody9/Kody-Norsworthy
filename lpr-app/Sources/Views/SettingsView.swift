import SwiftData
import SwiftUI
import UIKit

/// "Setup" tab. Not pixel-specced in the redesign handoff (no Setup screen
/// exists in the design canvas yet) — kept functional and restyled just
/// enough to sit comfortably next to the rest of the dark UI.
struct SettingsView: View {
    @Query private var entries: [PlateEntry]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = true
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("autoScanFastMode") private var autoScanFastMode = true

    @State private var shareFile: ShareableFile?
    @State private var showClearConfirmation = false

    private let retentionOptions = [7, 14, 30, 60, 90, 0]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Setup")
                    .plType(.screenTitle)
                    .foregroundStyle(PLColor.ink)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, PLSpacing.gutter)

                sectionLabel("DATA")
                row { LabeledRow(label: "Total Entries", value: "\(entries.count)") }
                actionRow("Export as CSV") {
                    if let url = CSVExporter.export(entries, label: "All Entries") {
                        shareFile = ShareableFile(url: url)
                    }
                }
                actionRow("Clear All Data", destructive: true, showRule: false) {
                    showClearConfirmation = true
                }

                sectionLabel("RETENTION")
                row {
                    HStack {
                        Text("Auto-delete after").plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
                        Spacer()
                        Picker("", selection: $retentionDays) {
                            ForEach(retentionOptions, id: \.self) { days in
                                Text(days == 0 ? "Never" : "\(days) days").tag(days)
                            }
                        }
                        .tint(PLColor.accentOnDark)
                    }
                }
                Text("Entries older than the chosen window are deleted from this phone automatically on launch — DPPA hygiene by default, not by discipline.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, PLSpacing.gutter)

                sectionLabel("AUTO-SCAN")
                row {
                    HStack {
                        Text("Mode").plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
                        Spacer()
                        Picker("", selection: $autoScanFastMode) {
                            Text("Fast").tag(true)
                            Text("Accurate").tag(false)
                        }
                        .tint(PLColor.accentOnDark)
                    }
                }
                Text(autoScanFastMode
                    ? "Trusts a single frame's read immediately — catches more cars, including fast-moving ones, at the cost of more wrong reads to correct."
                    : "Waits for the same reading twice within a few seconds before queuing it — fewer wrong reads, but a car only in frame briefly may not get caught at all.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, PLSpacing.gutter)

                sectionLabel("ABOUT")
                actionRow("View Usage Disclaimer") {
                    hasAcceptedDisclaimer = false
                }
                Text("All data is stored only on this device. Nothing is uploaded to any server.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
            }
        }
        .background(PLColor.ground)
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Clear All Data?", isPresented: $showClearConfirmation) {
            Button("Delete Everything", role: .destructive, action: clearAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all captured plate entries from this device. This cannot be undone.")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .plType(.sectionLabel)
            .foregroundStyle(PLColor.inkTertiary)
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.top, PLSpacing.lg)
            .padding(.bottom, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
            }
    }

    private func actionRow(_ title: String, destructive: Bool = false, showRule: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .plType(.rowLabel)
                .foregroundStyle(destructive ? PLColor.accentOnDark : PLColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showRule {
                Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
            }
        }
    }

    private func clearAll() {
        for entry in entries {
            modelContext.delete(entry)
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
            Spacer()
            Text(value).plType(PLTypeStyle(.semibold, 14)).foregroundStyle(PLColor.ink)
        }
    }
}

/// Wraps a URL so it can drive `.sheet(item:)`, which — unlike
/// `.sheet(isPresented:)` paired with a separately-tracked optional — is
/// guaranteed to have the value available when its content closure runs.
/// (isPresented + a sibling @State optional can present before that
/// optional is visible to the closure, rendering an empty sheet.)
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
