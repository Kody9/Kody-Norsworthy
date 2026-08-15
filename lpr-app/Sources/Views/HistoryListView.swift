import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

private enum HistoryFilter: String, CaseIterable, Hashable {
    case all = "ALL"
    case bolo = "BOLO"
    case followUp = "FOLLOW-UP"
    case map = "MAP"
}

private enum HistorySortOption: String, CaseIterable, Hashable {
    case newest = "NEWEST"
    case oldest = "OLDEST"
    case plate = "PLATE A–Z"
}

/// Narrows the list (and what EXPORT sends) to a time window. `.custom`
/// carries whole calendar days — `contains` treats `end` as inclusive
/// through the end of that day, not a specific timestamp.
private enum HistoryDateScope: Hashable {
    case all, today, yesterday, last7Days, last30Days
    case custom(start: Date, end: Date)

    var label: String {
        switch self {
        case .all: return "ALL TIME"
        case .today: return "TODAY"
        case .yesterday: return "YESTERDAY"
        case .last7Days: return "LAST 7 DAYS"
        case .last30Days: return "LAST 30 DAYS"
        case .custom: return "CUSTOM RANGE"
        }
    }

    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .yesterday:
            return calendar.isDateInYesterday(date)
        case .last7Days:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
            return date >= cutoff
        case .last30Days:
            let cutoff = calendar.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
            return date >= cutoff
        case .custom(let start, let end):
            let rangeStart = calendar.startOfDay(for: start)
            let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            return date >= rangeStart && date < rangeEnd
        }
    }
}

private struct DaySection: Identifiable {
    let id: Date
    let label: String
    let entries: [PlateEntry]
}

struct HistoryListView: View {
    @Query(sort: \PlateEntry.capturedAt, order: .reverse) private var entries: [PlateEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all
    @State private var sortOption: HistorySortOption = .newest
    @State private var dateScope: HistoryDateScope = .all
    @State private var showCustomRangeSheet = false
    @State private var customRangeStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var customRangeEnd: Date = .now
    @State private var selectedEntry: PlateEntry?
    @State private var shareFile: ShareableFile?
    @State private var entryPendingDeletion: PlateEntry?

    /// Tag filter, date scope, and search applied — not yet sorted. The
    /// @Query itself is already newest-first, which `sortedFiltered` relies
    /// on for its `.newest`/`.oldest` cases.
    private var filtered: [PlateEntry] {
        var result = entries
        switch filter {
        case .all: break
        case .bolo: result = result.filter { $0.tag == "BOLO" }
        case .followUp: result = result.filter { $0.tag == "Follow-up" }
        case .map: result = result.filter { $0.latitude != nil && $0.longitude != nil }
        }
        result = result.filter { dateScope.contains($0.capturedAt) }
        guard !searchText.isEmpty else { return result }
        return result.filter {
            $0.plateNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            $0.tag.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var sortedFiltered: [PlateEntry] {
        switch sortOption {
        case .newest: return filtered
        case .oldest: return filtered.reversed()
        case .plate: return filtered.sorted { $0.plateNumber < $1.plateNumber }
        }
    }

    /// Only meaningful for the date-ordered sorts — grouping while sorted
    /// alphabetically by plate would scatter each day across the list.
    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var groups: [Date: [PlateEntry]] = [:]
        var order: [Date] = []
        for entry in sortedFiltered {
            let day = calendar.startOfDay(for: entry.capturedAt)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(entry)
        }
        return order.map { day in
            DaySection(id: day, label: dayLabel(for: day), entries: groups[day] ?? [])
        }
    }

    private func dayLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.month(.abbreviated).day().year()).uppercased()
    }

    var body: some View {
        Group {
            if let selectedEntry {
                EntryDetailView(
                    entry: selectedEntry,
                    onBack: { self.selectedEntry = nil },
                    onSelectEntry: { self.selectedEntry = $0 }
                )
            } else {
                listView
            }
        }
        .background(PLColor.ground)
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $showCustomRangeSheet) {
            CustomDateRangeView(
                start: $customRangeStart,
                end: $customRangeEnd,
                onApply: {
                    dateScope = .custom(start: customRangeStart, end: customRangeEnd)
                    showCustomRangeSheet = false
                },
                onCancel: { showCustomRangeSheet = false }
            )
        }
        .alert(
            "Delete This Entry?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) {
                delete(entry)
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
        } message: { entry in
            Text("This permanently deletes \(entry.plateNumber) from this device. This cannot be undone.")
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

            HStack(spacing: PLSpacing.md) {
                dateScopeMenu
                Spacer()
                sortMenu
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
            } else if filter == .map {
                mapView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                        if sortOption == .plate {
                            ForEach(sortedFiltered) { entry in
                                entryRow(entry)
                            }
                        } else {
                            ForEach(daySections) { section in
                                daySectionHeader(section)
                                ForEach(section.entries) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var dateScopeMenu: some View {
        Menu {
            Button("All Time") { dateScope = .all }
            Button("Today") { dateScope = .today }
            Button("Yesterday") { dateScope = .yesterday }
            Button("Last 7 Days") { dateScope = .last7Days }
            Button("Last 30 Days") { dateScope = .last30Days }
            Button("Custom Range…") { showCustomRangeSheet = true }
        } label: {
            HStack(spacing: 4) {
                Text(dateScope.label)
                Text("▾")
            }
            .plType(PLTypeStyle(.heavy, 11, trackingEm: 0.08))
            .foregroundStyle(PLColor.inkTertiary)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(HistorySortOption.allCases, id: \.self) { option in
                Button(option.rawValue) { sortOption = option }
            }
        } label: {
            HStack(spacing: 4) {
                Text("SORT: \(sortOption.rawValue)")
                Text("▾")
            }
            .plType(PLTypeStyle(.heavy, 11, trackingEm: 0.08))
            .foregroundStyle(PLColor.inkTertiary)
        }
    }

    /// All entries currently on screen, as coordinates -- filtered to just
    /// the ones with a location, same set `filter == .map` already narrows
    /// `filtered` to (search/date scope still apply too).
    private var mapEntries: [(entry: PlateEntry, coordinate: CLLocationCoordinate2D)] {
        filtered.compactMap { entry in
            guard let lat = entry.latitude, let lon = entry.longitude else { return nil }
            return (entry, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    /// A region that fits every pin, falling back to a continental-US view
    /// when nothing has a location yet.
    private var mapRegion: MKCoordinateRegion {
        let coordinates = mapEntries.map(\.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
            )
        }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var mapView: some View {
        Map(initialPosition: .region(mapRegion)) {
            ForEach(mapEntries, id: \.entry.id) { item in
                Annotation(item.entry.plateNumber, coordinate: item.coordinate) {
                    Button {
                        selectedEntry = item.entry
                    } label: {
                        VStack(spacing: 3) {
                            Text(item.entry.plateNumber)
                                .plType(PLTypeStyle(.bold, 10, trackingEm: 0.04))
                                .foregroundStyle(PLColor.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(PLColor.surface)
                            Rectangle()
                                .fill(PLColor.accentOnDark)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func daySectionHeader(_ section: DaySection) -> some View {
        HStack {
            Text(section.label).plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
            Text("· \(section.entries.count)").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
            Spacer()
            Button {
                exportEntries(section.entries, label: section.label)
            } label: {
                Text("EXPORT")
                    .underline()
                    .plType(PLTypeStyle(.bold, 10, trackingEm: 0.08))
                    .foregroundStyle(PLColor.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func entryRow(_ entry: PlateEntry) -> some View {
        EntryRow(
            entry: entry,
            repeatCount: repeatCount(for: entry),
            onDelete: { entryPendingDeletion = entry }
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedEntry = entry }
        .swipeActions {
            Button(role: .destructive) { delete(entry) } label: {
                Label("Delete", systemImage: "trash")
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

    private func exportEntries(_ list: [PlateEntry], label: String? = nil) {
        guard let url = CSVExporter.export(list, label: label) else { return }
        shareFile = ShareableFile(url: url)
    }

    /// Exports whatever's currently on screen — tag filter, date scope,
    /// search, and sort all narrow this, same as the visible list.
    private func exportFiltered() {
        exportEntries(sortedFiltered, label: dateScope == .all ? nil : dateScope.label)
    }
}

private struct EntryRow: View {
    let entry: PlateEntry
    let repeatCount: Int
    let onDelete: () -> Void

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

            Button(action: onDelete) {
                Text("DELETE")
                    .underline()
                    .plType(PLTypeStyle(.bold, 10, trackingEm: 0.06))
                    .foregroundStyle(PLColor.inkTertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, PLSpacing.gutter)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }
}

private struct CustomDateRangeView: View {
    @Binding var start: Date
    @Binding var end: Date
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("CANCEL", action: onCancel)
                    .buttonStyle(.plain)
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Text("CUSTOM RANGE")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.accentOnDark)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }

            VStack(alignment: .leading, spacing: PLSpacing.xl) {
                dateRow(label: "FROM", date: $start)
                dateRow(label: "TO", date: $end)
            }
            .padding(PLSpacing.gutter)

            Spacer()

            PLPrimaryButton("APPLY", action: onApply)
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.bottom, PLSpacing.gutter)
        }
        .background(PLColor.ground)
        .colorScheme(.dark)
    }

    private func dateRow(label: String, date: Binding<Date>) -> some View {
        HStack {
            Text(label).plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
            Spacer()
            DatePicker("", selection: date, in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
                .tint(PLColor.accentOnDark)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }
}
