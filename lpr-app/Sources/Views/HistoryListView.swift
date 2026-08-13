import SwiftData
import SwiftUI
import UIKit

struct HistoryListView: View {
    @Query(sort: \PlateEntry.capturedAt, order: .reverse) private var entries: [PlateEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var filtered: [PlateEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.plateNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            $0.tag.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { entry in
                    NavigationLink(value: entry) {
                        EntryRow(entry: entry)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationDestination(for: PlateEntry.self) { entry in
                EntryDetailView(entry: entry)
            }
            .searchable(text: $searchText, prompt: "Search plate, tag, notes")
            .navigationTitle("History")
            .toolbar { EditButton() }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "car",
                        description: Text("Captured plates will show up here.")
                    )
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filtered[index])
        }
    }
}

private struct EntryRow: View {
    let entry: PlateEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "car.fill"))
            }
            VStack(alignment: .leading) {
                Text(entry.plateNumber).font(.headline)
                Text("\(entry.state) · \(entry.tag)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.capturedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
