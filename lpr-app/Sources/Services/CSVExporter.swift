import Foundation

enum CSVExporter {
    /// - Parameter label: A short description of what's being exported
    ///   (e.g. "Today," "Aug 14, 2026," "All Entries"), folded into the
    ///   filename so it reads as something you chose rather than a random
    ///   string. Omit for a plain timestamped export.
    static func export(_ entries: [PlateEntry], label: String? = nil) -> URL? {
        var csv = "Plate Number,State,VIN,Driver Name,Logged By,Captured At,Latitude,Longitude,Tag,Notes\n"
        let formatter = ISO8601DateFormatter()

        for entry in entries {
            let latitudeText: String = entry.latitude.map { String($0) } ?? ""
            let longitudeText: String = entry.longitude.map { String($0) } ?? ""
            let capturedAtText: String = formatter.string(from: entry.capturedAt)
            let rawFields: [String] = [
                entry.plateNumber,
                entry.state,
                entry.vin ?? "",
                entry.driverName,
                entry.loggedByName,
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
            .appendingPathComponent(fileName(label: label))
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func fileName(label: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h.mm a"
        let stamp = formatter.string(from: .now)
        let base = label.map { "SAL - \($0) - \(stamp)" } ?? "SAL Export - \(stamp)"
        return sanitized(base) + ".csv"
    }

    /// Strips characters that are invalid (or just awkward) in a filename
    /// on iOS/macOS -- notably `:` and `/`.
    private static func sanitized(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw.components(separatedBy: invalid).joined(separator: "-")
    }

    private nonisolated static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
