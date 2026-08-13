import Foundation

enum CSVExporter {
    static func export(_ entries: [PlateEntry]) -> URL? {
        var csv = "Plate Number,State,VIN,Captured At,Latitude,Longitude,Tag,Notes\n"
        let formatter = ISO8601DateFormatter()

        for entry in entries {
            let fields = [
                entry.plateNumber,
                entry.state,
                entry.vin ?? "",
                formatter.string(from: entry.capturedAt),
                entry.latitude.map(String.init) ?? "",
                entry.longitude.map(String.init) ?? "",
                entry.tag,
                entry.notes
            ].map(escape)
            csv += fields.joined(separator: ",") + "\n"
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

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
