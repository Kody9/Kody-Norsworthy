import MapKit
import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Bindable var entry: PlateEntry

    @State private var vinDecodeResult: NHTSAVinDecoder.Result?
    @State private var isDecoding = false
    @State private var decodeError: String?

    var body: some View {
        Form {
            if let data = entry.photoData, let uiImage = UIImage(data: data) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Section("Plate") {
                LabeledContent("Plate Number", value: entry.plateNumber)
                LabeledContent("State", value: entry.state)
                LabeledContent("Captured", value: entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Details") {
                TextField(
                    "VIN",
                    text: Binding(
                        get: { entry.vin ?? "" },
                        set: { entry.vin = $0.isEmpty ? nil : $0.uppercased() }
                    )
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                TextField("Notes", text: $entry.notes, axis: .vertical)
            }

            if let latitude = entry.latitude, let longitude = entry.longitude {
                Section("Location Captured") {
                    Map(initialPosition: .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )) {
                        Marker("Capture Point", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Section {
                Text("These open free, publicly available government or consumer tools in your browser. This app never accesses any government or private owner database directly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: decodeVin) {
                    if isDecoding {
                        ProgressView()
                    } else {
                        Label("Decode VIN (NHTSA, free & public)", systemImage: "number")
                    }
                }
                .disabled((entry.vin ?? "").isEmpty || isDecoding)

                if let result = vinDecodeResult {
                    VStack(alignment: .leading, spacing: 4) {
                        if let make = result.make { LabeledContent("Make", value: make) }
                        if let model = result.model { LabeledContent("Model", value: model) }
                        if let year = result.year { LabeledContent("Year", value: year) }
                        if let bodyClass = result.bodyClass { LabeledContent("Body Type", value: bodyClass) }
                    }
                }
                if let decodeError {
                    Text(decodeError).font(.footnote).foregroundStyle(.red)
                }

                Link(destination: ExternalLookupLinks.nicbVinCheck()) {
                    Label("NICB VINCheck (stolen/salvage, free)", systemImage: "checkmark.shield")
                }

                Link(destination: ExternalLookupLinks.carfaxFreeCheck()) {
                    Label("CARFAX Free Report (service history)", systemImage: "wrench.and.screwdriver")
                }

                Link(destination: ExternalLookupLinks.webSearch(plate: entry.plateNumber, state: entry.state)) {
                    Label("Web Search Plate Number", systemImage: "magnifyingglass")
                }
            } header: {
                Text("Public Lookups")
            }

            Section("Agency Database") {
                Text(OwnerLookupProvider.unconfiguredMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(entry.plateNumber)
        .navigationBarTitleDisplayMode(.inline)
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
