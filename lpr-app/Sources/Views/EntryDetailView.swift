import MapKit
import SwiftData
import SwiftUI
import UIKit

struct EntryDetailView: View {
    @Bindable var entry: PlateEntry
    let onBack: () -> Void

    @State private var vinDecodeResult: NHTSAVinDecoder.Result?
    @State private var isDecoding = false
    @State private var decodeError: String?

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
                    lookupsSection
                    fieldsSection
                }
            }
            notAvailablePanel
        }
        .background(PLColor.ground)
    }

    private var backRow: some View {
        Button(action: onBack) {
            Text("‹ HISTORY")
                .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                .foregroundStyle(PLColor.inkTertiary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.plateNumber).plType(.plateDetail).foregroundStyle(PLColor.ink)
            Text("\(entry.state.uppercased()) · \(entry.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.tag.uppercased())")
                .plType(PLTypeStyle(.semibold, 12, trackingEm: 0.08))
                .foregroundStyle(PLColor.inkTertiary)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.bottom, PLSpacing.gutter)
    }

    private var photo: some View {
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
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func map(latitude: Double, longitude: Double) -> some View {
        ZStack {
            Map(initialPosition: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )) {}
            .allowsHitTesting(false)
            Rectangle()
                .fill(PLColor.accentOnDark)
                .frame(width: 10, height: 10)
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private var lookupsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PUBLIC LOOKUPS — OPENS IN BROWSER")
                .plType(.sectionLabel)
                .foregroundStyle(PLColor.inkTertiary)
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                }

            decodeVinRow

            linkRow(title: "Stolen / salvage — NICB") {
                UIApplication.shared.open(ExternalLookupLinks.nicbVinCheck())
            }
            linkRow(title: "Service history — CARFAX", showRule: false) {
                UIApplication.shared.open(ExternalLookupLinks.carfaxFreeCheck())
            }
        }
    }

    private var decodeVinRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: decodeVin) {
                HStack {
                    Text("Decode VIN — NHTSA").plType(.linkRow).foregroundStyle(PLColor.ink)
                    Spacer()
                    if isDecoding {
                        ProgressView()
                    } else {
                        Text("→").plType(.linkRow).foregroundStyle(PLColor.accentOnDark)
                    }
                }
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled((entry.vin ?? "").isEmpty || isDecoding)
            .opacity((entry.vin ?? "").isEmpty ? 0.5 : 1)

            if let result = vinDecodeResult {
                VStack(alignment: .leading, spacing: 4) {
                    if let make = result.make { detailLine("Make", make) }
                    if let model = result.model { detailLine("Model", model) }
                    if let year = result.year { detailLine("Year", year) }
                    if let bodyClass = result.bodyClass { detailLine("Body Type", bodyClass) }
                }
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.bottom, 12)
            }
            if let decodeError {
                Text(decodeError)
                    .plType(.body)
                    .foregroundStyle(PLColor.accentOnDark)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased()).plType(PLTypeStyle(.semibold, 11, trackingEm: 0.06)).foregroundStyle(PLColor.inkTertiary)
            Spacer()
            Text(value).plType(PLTypeStyle(.semibold, 13)).foregroundStyle(PLColor.inkSecondary)
        }
    }

    private func linkRow(title: String, showRule: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).plType(.linkRow).foregroundStyle(PLColor.ink)
                Spacer()
                Text("→").plType(.linkRow).foregroundStyle(PLColor.accentOnDark)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showRule {
                Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
            }
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldRow(label: "STATE", text: Binding(
                get: { entry.state },
                set: { entry.state = $0.isEmpty ? "Unknown" : $0 }
            ))
            fieldRow(label: "VIN", text: Binding(
                get: { entry.vin ?? "" },
                set: { entry.vin = $0.isEmpty ? nil : $0.uppercased() }
            ), autocapitalize: true)
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

    private func decodeVin() {
        guard let vin = entry.vin, !vin.isEmpty else { return }
        isDecoding = true
        decodeError = nil
        Task {
            do {
                let result = try await NHTSAVinDecoder.decode(vin: vin)
                await MainActor.run {
                    vinDecodeResult = result
                    isDecoding = false
                }
            } catch {
                await MainActor.run {
                    decodeError = "Couldn't decode VIN: \(error.localizedDescription)"
                    isDecoding = false
                }
            }
        }
    }
}
