import Foundation

/// Calls NHTSA's vPIC API (https://vpic.nhtsa.dot.gov) — a free, public, official
/// US government API for decoding a VIN into vehicle facts (make/model/year/body
/// type). It returns nothing about ownership; that data doesn't exist in vPIC.
enum NHTSAVinDecoder {
    struct Result {
        let make: String?
        let model: String?
        let year: String?
        let bodyClass: String?
    }

    enum DecodeError: LocalizedError {
        case invalidVIN
        case parsing

        var errorDescription: String? {
            switch self {
            case .invalidVIN: return "Enter a VIN first."
            case .parsing: return "NHTSA didn't return usable data for that VIN."
            }
        }
    }

    static func decode(vin: String) async throws -> Result {
        let trimmed = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw DecodeError.invalidVIN }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw DecodeError.invalidVIN
        }

        guard let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(trimmed)?format=json") else {
            throw DecodeError.invalidVIN
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        struct Response: Decodable {
            struct ResultItem: Decodable {
                let Make: String?
                let Model: String?
                let ModelYear: String?
                let BodyClass: String?
            }
            let Results: [ResultItem]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let first = decoded.Results.first else { throw DecodeError.parsing }

        return Result(
            make: nonEmpty(first.Make),
            model: nonEmpty(first.Model),
            year: nonEmpty(first.ModelYear),
            bodyClass: nonEmpty(first.BodyClass)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
