import CoreLocation
import SwiftData
import SwiftUI

struct ConfirmEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let image: UIImage?
    let candidates: [PlateOCRService.Candidate]
    let location: CLLocation?

    @State private var plateNumber = ""
    @State private var state = "Unknown"
    @State private var vin = ""
    @State private var tag = "General"
    @State private var notes = ""

    private let tags = ["General", "BOLO", "Suspicious", "Parking Complaint", "Follow-up"]

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section("Plate") {
                    if !candidates.isEmpty {
                        Picker("OCR Suggestions", selection: $plateNumber) {
                            ForEach(candidates) { candidate in
                                Text("\(candidate.text)  (\(Int(candidate.confidence * 100))%)")
                                    .tag(candidate.text)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    TextField("Plate Number", text: $plateNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("State", selection: $state) {
                        ForEach(USStates.all, id: \.self) { Text($0) }
                    }
                }

                Section("Optional") {
                    TextField("VIN (if known)", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Tag", selection: $tag) {
                        ForEach(tags, id: \.self) { Text($0) }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                if let location {
                    Section("Location Captured") {
                        Text(String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Confirm Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(plateNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if plateNumber.isEmpty {
                    plateNumber = candidates.first?.text ?? ""
                }
            }
        }
    }

    private func save() {
        let entry = PlateEntry(
            plateNumber: plateNumber.uppercased(),
            state: state,
            vin: vin.isEmpty ? nil : vin.uppercased(),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            notes: notes,
            tag: tag,
            photoData: image?.jpegData(compressionQuality: 0.7)
        )
        modelContext.insert(entry)
        dismiss()
    }
}
