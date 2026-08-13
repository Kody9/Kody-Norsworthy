import Foundation
import SwiftData

@Model
final class PlateEntry {
    var id: UUID
    var plateNumber: String
    var state: String
    var vin: String?
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var notes: String
    var tag: String
    @Attribute(.externalStorage) var photoData: Data?

    init(
        plateNumber: String,
        state: String,
        vin: String? = nil,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        notes: String = "",
        tag: String = "General",
        photoData: Data? = nil
    ) {
        self.id = UUID()
        self.plateNumber = plateNumber
        self.state = state
        self.vin = vin
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.tag = tag
        self.photoData = photoData
    }
}
