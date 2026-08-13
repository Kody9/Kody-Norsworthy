import Foundation

/// Builds deep links to *free, public* third-party pages. These are opened in
/// the user's browser — the app never scrapes, calls a private API, or stores
/// credentials for any of these services. Site URL structures can change over
/// time; if a link stops landing on the right page, it still lands on the
/// service's home page as a safe fallback.
enum ExternalLookupLinks {
    /// NICB's free stolen/salvage VIN check. It's a web form, not a linkable
    /// lookup, so this just opens the tool — paste the VIN in once there.
    static func nicbVinCheck() -> URL {
        URL(string: "https://www.nicb.org/vincheck")!
    }

    /// CARFAX's free VIN check landing page (consumer product, no API key).
    /// CARFAX doesn't offer a documented way to pre-fill a VIN via URL, so
    /// this opens the tool for the user to paste the VIN into.
    static func carfaxFreeCheck() -> URL {
        URL(string: "https://www.carfax.com/vehiclehistory/free-vin-check")!
    }

    /// A generic web search for the plate text. Rarely turns up anything useful
    /// (plates aren't indexed to owners), but it's harmless and sometimes
    /// surfaces things like a stolen-vehicle post or a local classifieds ad.
    static func webSearch(plate: String, state: String) -> URL {
        let query = "\(plate) \(state) license plate"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plate
        return URL(string: "https://www.google.com/search?q=\(encoded)")!
    }
}
