import MapKit
import SwiftData
import SwiftUI
import UIKit

struct EntryDetailView: View {
    @Bindable var entry: PlateEntry
    let onBack: () -> Void
    /// Lets tapping a past sighting jump straight to that entry instead of
    /// only being able to view it from History.
    let onSelectEntry: (PlateEntry) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlateEntry.capturedAt, order: .reverse) private var allEntries: [PlateEntry]

    @State private var shareFile: ShareableFile?
    @State private var showDeleteConfirmation = false
    @State private var showZoomedPhoto = false
    @StateObject private var photoZoomState = PhotoZoomState()
    /// Decoded once per entry rather than inline in `photo`/the zoom cover
    /// -- `UIImage(data:)` produces a new object identity every call, and
    /// `ZoomingScrollView` tracks the current image by reference. Since the
    /// zoom cover's body re-evaluates continuously while pinching (it
    /// observes `photoZoomState`, which publishes on every zoom/pan
    /// update), decoding inline there fed the zoomer a "new" image
    /// mid-gesture on every single frame, which reset and corrupted its
    /// zoom state -- the reported "zoomed in and won't let me zoom out" bug.
    @State private var photoImage: UIImage?

    private var displayState: String {
        entry.state.isEmpty ? "UNKNOWN" : entry.state.uppercased()
    }

    /// Every other logged entry for this exact plate, most recent first.
    private var pastSightings: [PlateEntry] {
        allEntries.filter { $0.plateNumber == entry.plateNumber && $0.id != entry.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    backRow
                    header
                    photo
                    if let latitude = entry.latitude, let longitude = entry.longitude {
                        map(latitude: latitude, longitude: longitude)
                    }
                    pastSightingsSection
                    fieldsSection
                }
            }
            notAvailablePanel
        }
        .background(PLColor.ground)
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Delete This Entry?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteEntry)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(entry.plateNumber) from this device. This cannot be undone.")
        }
        .fullScreenCover(isPresented: $showZoomedPhoto) {
            if let photoImage {
                PhotoZoomView(image: photoImage, zoomState: photoZoomState, onDone: { showZoomedPhoto = false })
            }
        }
        .task(id: entry.id) {
            photoImage = entry.photoData.flatMap(UIImage.init(data:))
            photoZoomState.reset()
        }
    }

    private var backRow: some View {
        HStack {
            Button(action: onBack) {
                Text("‹ HISTORY")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                    .foregroundStyle(PLColor.inkTertiary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: shareEntry) {
                Text("SHARE")
                    .underline()
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                    .foregroundStyle(PLColor.ink)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            Button {
                showDeleteConfirmation = true
            } label: {
                Text("DELETE")
                    .underline()
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                    .foregroundStyle(PLColor.accentOnDark)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func shareEntry() {
        guard let url = EntryShareExporter.makePDF(for: entry) else { return }
        shareFile = ShareableFile(url: url)
    }

    private func deleteEntry() {
        modelContext.delete(entry)
        onBack()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.plateNumber).plType(.plateDetail).foregroundStyle(PLColor.ink)
            Text("\(displayState) · \(entry.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.tag.uppercased())")
                .plType(PLTypeStyle(.semibold, 12, trackingEm: 0.08))
                .foregroundStyle(PLColor.inkTertiary)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.bottom, PLSpacing.gutter)
    }

    private var photo: some View {
        Button {
            showZoomedPhoto = true
        } label: {
            Group {
                if let photoImage {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: photoImage)
                            .resizable()
                            .scaledToFit()
                            .grayscale(1.0)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                        Text("TAP TO ZOOM")
                            .plType(PLTypeStyle(.bold, 10, trackingEm: 0.08))
                            .foregroundStyle(PLColor.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .padding(10)
                    }
                } else {
                    PLColor.surface.frame(height: 150)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(photoImage == nil)
        .frame(maxHeight: 220)
        .clipped()
        .contentShape(Rectangle())
    }

    private func map(latitude: Double, longitude: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return Map(initialPosition: .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )) {
            Annotation("", coordinate: coordinate) {
                Rectangle()
                    .fill(PLColor.accentOnDark)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private var pastSightingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PAST SIGHTINGS OF THIS PLATE")
                .plType(.sectionLabel)
                .foregroundStyle(PLColor.inkTertiary)
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                }

            if pastSightings.isEmpty {
                Text("This is the only time this plate has been logged.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.bottom, 14)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
                    }
            } else {
                ForEach(pastSightings) { sighting in
                    sightingRow(sighting)
                }
            }
        }
    }

    private func sightingRow(_ sighting: PlateEntry) -> some View {
        Button {
            onSelectEntry(sighting)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sighting.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .plType(.linkRow)
                        .foregroundStyle(PLColor.ink)
                    Text(sighting.state.isEmpty ? "UNKNOWN" : sighting.state.uppercased())
                        .plType(PLTypeStyle(.bold, 10, trackingEm: 0.06))
                        .foregroundStyle(PLColor.inkTertiary)
                }
                Spacer()
                Text(sighting.tag == "Parking Complaint" ? "PARKING" : sighting.tag.uppercased())
                    .plType(PLTypeStyle(.bold, 11, trackingEm: 0.04))
                    .foregroundStyle(sighting.tag == "BOLO" ? PLColor.accentOnDark : PLColor.inkTertiary)
                Text("→").plType(.linkRow).foregroundStyle(PLColor.accentOnDark).padding(.leading, 10)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldRow(
                label: "STATE",
                text: Binding(
                    get: { entry.state == "Unknown" ? "" : entry.state },
                    set: { entry.state = $0 }
                ),
                autocapitalize: true
            )
            fieldRow(label: "VIN", text: Binding(
                get: { entry.vin ?? "" },
                set: { entry.vin = $0.isEmpty ? nil : $0.uppercased() }
            ), autocapitalize: true)
            fieldRow(label: "DRIVER", text: $entry.driverName)
            fieldRow(label: "NOTES", text: $entry.notes)
        }
        .padding(.top, PLSpacing.sm)
    }

    private func fieldRow(label: String, text: Binding<String>, autocapitalize: Bool = false) -> some View {
        HStack {
            Text(label).plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary).frame(width: 64, alignment: .leading)
            TextField("", text: text)
                .plType(PLTypeStyle(.semibold, 14))
                .foregroundStyle(PLColor.ink)
                .textInputAutocapitalization(autocapitalize ? .characters : .sentences)
                .autocorrectionDisabled(autocapitalize)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private var notAvailablePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOT AVAILABLE HERE")
                .plType(.sectionLabel)
                .foregroundStyle(PLColor.accentOnDark)
            Text("Owner identity, NCIC and DMV records are not reachable from this app. Use your department's audited channel.")
                .plType(.body)
                .foregroundStyle(PLColor.inkSecondary)
        }
        .padding(PLSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PLColor.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.accentOnDark).frame(height: PLSpacing.ruleWidth)
        }
    }
}
