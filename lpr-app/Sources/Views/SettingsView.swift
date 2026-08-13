import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var entries: [PlateEntry]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = true

    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    LabeledContent("Total Entries", value: "\(entries.count)")
                    Button("Export as CSV") {
                        shareURL = CSVExporter.export(entries)
                        showShareSheet = shareURL != nil
                    }
                    Button("Clear All Data", role: .destructive) {
                        showClearConfirmation = true
                    }
                }

                Section("About") {
                    Button("View Usage Disclaimer") {
                        hasAcceptedDisclaimer = false
                    }
                    Text("All data is stored only on this device. Nothing is uploaded to any server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showShareSheet) {
                if let shareURL {
                    ShareSheet(activityItems: [shareURL])
                }
            }
            .alert("Clear All Data?", isPresented: $showClearConfirmation) {
                Button("Delete Everything", role: .destructive, action: clearAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all captured plate entries from this device. This cannot be undone.")
            }
        }
    }

    private func clearAll() {
        for entry in entries {
            modelContext.delete(entry)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
