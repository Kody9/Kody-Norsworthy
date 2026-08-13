import Foundation

enum CSVExporter {
    static func export(_ entries: [PlateEntry]) -> URL? {
        var csv = "Plate Number,State,VIN,Captured At,Latitude,Longitude,Tag,Notes\n"
        let formatter = ISO8601DateFormatter()

        for entry in entries {
            let latitudeText: String = entry.latitude.map { String($0) } ?? ""
            let longitudeText: String = entry.longitude.map { String($0) } ?? ""
            let capturedAtText: String = formatter.string(from: entry.capturedAt)
            let rawFields: [String] = [
                entry.plateNumber,
                entry.state,
                entry.vin ?? "",
                capturedAtText,
                latitudeText,
                longitudeText,
                entry.tag,
                entry.notes
            ]
            let escapedFields: [String] = rawFields.map(escape)
            csv += escapedFields.joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plate_log_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private nonisolated static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
