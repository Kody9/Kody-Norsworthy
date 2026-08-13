import Foundation

/// Extension point for a *future*, department-authorized owner lookup — e.g. an
/// official RMS/NCIC integration your agency's IT provisions with real
/// credentials and audit logging. This app does not implement one and never
/// will ship a built-in plate-to-owner lookup: that data is protected by the
/// federal Driver's Privacy Protection Act (and most state equivalents), and
/// personal apps are not a lawful access path to it.
protocol OwnerLookupProviding {
    func lookupOwner(plate: String, state: String) async throws -> String
}

enum OwnerLookupProvider {
    static let unconfiguredMessage = """
    No owner-identification lookup is configured, by design. Plate-to-owner \
    records are protected under the federal Driver's Privacy Protection Act. \
    If your department has authorized, audited access to NCIC or your state's \
    DMV system, use your agency's official terminal or RMS for that — not a \
    personal app. If you're later issued a legitimate, authorized API, \
    implement OwnerLookupProviding and wire it in here.
    """
}
