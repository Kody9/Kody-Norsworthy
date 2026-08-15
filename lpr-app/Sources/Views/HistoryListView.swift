import SwiftData
import SwiftUI
import UIKit

private enum HistoryFilter: String, CaseIterable, Hashable {
    case all = "ALL"
    case bolo = "BOLO"
    case followUp = "FOLLOW-UP"
    case map = "MAP"
}

struct HistoryListView: View {
    @Query(sort: \PlateEntry.capturedAt, order: .reverse) private var entries: [PlateEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all
    @State private var selectedEntry: PlateEntry?
    @State private var shareFile: ShareableFile?

    private var filtered: [PlateEntry] {
        var result = entries
        switch filter {
        case .all: break
        case .bolo: result = result.filter { $0.tag == "BOLO" }
        case .followUp: result = result.filter { $0.tag == "Follow-up" }
        case .map: result = result.filter { $0.latitude != nil && $0.longitude != nil }
        }
        guard !searchText.isEmpty else { return result }
        return result.filter {
            $0.plateNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            $0.tag.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if let selectedEntry {
                EntryDetailView(entry: selectedEntry, onBack: { self.selectedEntry = nil })
            } else {
                listView
            }
        }
        .background(PLColor.ground)
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .plType(.screenTitle)
                    .foregroundStyle(PLColor.ink)
                Spacer()
                Button(action: exportFiltered) {
                    Text("EXPORT")
                        .underline()
                        .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                        .foregroundStyle(PLColor.ink)
                }
                .buttonStyle(.plain)
                .disabled(filtered.isEmpty)
                .opacity(filtered.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.bottom, 14)

            TextField("", text: $searchText, prompt: Text("Search plate, tag, notes").foregroundStyle(PLColor.inkTertiary))
                .plType(PLTypeStyle(.medium, 14))
                .foregroundStyle(PLColor.ink)
                .padding(13)
                .overlay(Rectangle().stroke(PLColor.fieldBorderStrong, lineWidth: PLSpacing.ruleWidth))
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                ForEach(HistoryFilter.allCases, id: \.self) { option in
                    let isActive = option == filter
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .plType(PLTypeStyle(isActive ? .heavy : .semibold, 11, trackingEm: 0.1))
                            .foregroundStyle(isActive ? PLColor.ground : PLColor.inkTertiary)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 16)
                            .background(isActive ? PLColor.ink : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .top) { Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth) }
            .overlay(alignment: .bottom) { Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth) }

            HStack {
                Text("ALL ENTRIES").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Text("\(filtered.count) ENTRIES").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if filtered.isEmpty {
                Spacer()
                Text("No entries yet")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                        ForEach(filtered) { entry in
                            EntryRow(entry: entry, repeatCount: repeatCount(for: entry))
                                .contentShape(Rectangle())
                                .onTapGesture { selectedEntry = entry }
                                .swipeActions {
                                    Button(role: .destructive) { delete(entry) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func repeatCount(for entry: PlateEntry) -> Int {
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) else { return 1 }
        return entries.filter { $0.plateNumber == entry.plateNumber && $0.capturedAt >= weekAgo }.count
    }

    private func delete(_ entry: PlateEntry) {
        modelContext.delete(entry)
    }

    /// Exports whatever's currently on screen — the active tag filter and
    /// search text both narrow this, same as the visible list — as CSV.
    private func exportFiltered() {
        guard let url = CSVExporter.export(filtered) else { return }
        shareFile = ShareableFile(url: url)
    }
}

private struct EntryRow: View {
    let entry: PlateEntry
    let repeatCount: Int

    private var meta: String {
        let time = entry.capturedAt.formatted(date: .omitted, time: .shortened)
        let state = entry.state.isEmpty ? "UNKNOWN" : entry.state.uppercased()
        let base = "\(state) · \(time)"
        return repeatCount > 1 ? "\(base) · \(repeatCount)× THIS WEEK" : base
    }

    var body: some View {
        HStack(spacing: PLSpacing.md) {
            Group {
                if let data = entry.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .grayscale(1.0)
                } else {
                    PLColor.surface
                }
            }
            .frame(width: 48, height: 48)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.plateNumber).plType(.plateRow).foregroundStyle(PLColor.ink)
                Text(meta).plType(.meta).foregroundStyle(PLColor.inkTertiary)
            }
            Spacer()
            Text(entry.tag == "Parking Complaint" ? "PARKING" : entry.tag.uppercased())
                .plType(PLTypeStyle(.bold, 11, trackingEm: 0.04))
                .foregroundStyle(entry.tag == "BOLO" ? PLColor.accentOnDark : PLColor.inkTertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, PLSpacing.gutter)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }
}
