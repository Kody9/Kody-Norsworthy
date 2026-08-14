import Foundation

/// Looks for a US state name or a common plate slogan among the *other*
/// text Vision recognized on the same plate (most US plates print the
/// issuing state, and many print a slogan too). This is a text match, not
/// a plate-design classifier — it only works when that text is legible in
/// the photo. Always treat the result as a starting guess, not a fact: the
/// caller still shows it as an editable field.
enum StateDetector {
    private static let stateNames: [String: String] = [
        "ALABAMA": "Alabama", "ALASKA": "Alaska", "ARIZONA": "Arizona", "ARKANSAS": "Arkansas",
        "CALIFORNIA": "California", "COLORADO": "Colorado", "CONNECTICUT": "Connecticut",
        "DELAWARE": "Delaware", "FLORIDA": "Florida", "GEORGIA": "Georgia", "HAWAII": "Hawaii",
        "IDAHO": "Idaho", "ILLINOIS": "Illinois", "INDIANA": "Indiana", "IOWA": "Iowa",
        "KANSAS": "Kansas", "KENTUCKY": "Kentucky", "LOUISIANA": "Louisiana", "MAINE": "Maine",
        "MARYLAND": "Maryland", "MASSACHUSETTS": "Massachusetts", "MICHIGAN": "Michigan",
        "MINNESOTA": "Minnesota", "MISSISSIPPI": "Mississippi", "MISSOURI": "Missouri",
        "MONTANA": "Montana", "NEBRASKA": "Nebraska", "NEVADA": "Nevada",
        "NEW HAMPSHIRE": "New Hampshire", "NEW JERSEY": "New Jersey", "NEW MEXICO": "New Mexico",
        "NEW YORK": "New York", "NORTH CAROLINA": "North Carolina", "NORTH DAKOTA": "North Dakota",
        "OHIO": "Ohio", "OKLAHOMA": "Oklahoma", "OREGON": "Oregon", "PENNSYLVANIA": "Pennsylvania",
        "RHODE ISLAND": "Rhode Island", "SOUTH CAROLINA": "South Carolina",
        "SOUTH DAKOTA": "South Dakota", "TENNESSEE": "Tennessee", "TEXAS": "Texas", "UTAH": "Utah",
        "VERMONT": "Vermont", "VIRGINIA": "Virginia", "WASHINGTON": "Washington",
        "WEST VIRGINIA": "West Virginia", "WISCONSIN": "Wisconsin", "WYOMING": "Wyoming",
        "DISTRICT OF COLUMBIA": "District of Columbia"
    ]

    /// Slogans/mottos commonly printed on plates, distinctive enough that a
    /// match is a reliable signal (unlike a bare two-letter abbreviation,
    /// which risks matching ordinary OCR noise like "IN" or "OR").
    private static let sloganMap: [String: String] = [
        "SUNSHINE STATE": "Florida",
        "THE GOLDEN STATE": "California",
        "GOLDEN STATE": "California",
        "LONE STAR STATE": "Texas",
        "EMPIRE STATE": "New York",
        "GARDEN STATE": "New Jersey",
        "THE FIRST STATE": "Delaware",
        "LIVE FREE OR DIE": "New Hampshire",
        "GREAT LAKES STATE": "Michigan",
        "PURE MICHIGAN": "Michigan",
        "LAND OF LINCOLN": "Illinois",
        "SHOW-ME STATE": "Missouri",
        "HOOSIER STATE": "Indiana",
        "VACATIONLAND": "Maine",
        "PELICAN STATE": "Louisiana",
        "EVERGREEN STATE": "Washington",
        "GRAND CANYON STATE": "Arizona",
        "ALOHA STATE": "Hawaii",
        "FAMOUS POTATOES": "Idaho",
        "LAND OF ENCHANTMENT": "New Mexico",
        "TREASURE STATE": "Montana",
        "COWBOY STATE": "Wyoming",
        "THE SILVER STATE": "Nevada",
        "OCEAN STATE": "Rhode Island",
        "GREEN MOUNTAIN STATE": "Vermont",
        "LIFE ELEVATED": "Utah",
        "PEACH STATE": "Georgia",
        "NATURAL STATE": "Arkansas",
        "IN GOD WE TRUST": "Ohio",
        "GREAT FACES GREAT PLACES": "South Dakota",
        "WORLD'S WONDERS": "Arkansas"
    ]

    static func detectState(from recognizedTexts: [String]) -> String? {
        let cleanedTexts = recognizedTexts.map {
            $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for text in cleanedTexts {
            if let name = stateNames[text] { return name }
            if let name = sloganMap[text] { return name }
        }

        for text in cleanedTexts {
            for (key, name) in stateNames where text.contains(key) {
                return name
            }
            for (key, name) in sloganMap where text.contains(key) {
                return name
            }
        }

        return nil
    }
}
