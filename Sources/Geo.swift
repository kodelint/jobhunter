import Foundation

/// Country / location matching for the location filter. Pragmatic keyword lists, not a full
/// geocoder: enough to keep in-country roles and drop clearly-foreign ones.
enum Geo {
    static let usStates = ["alabama","alaska","arizona","arkansas","california","colorado","connecticut",
        "delaware","florida","georgia","hawaii","idaho","illinois","indiana","iowa","kansas","kentucky",
        "louisiana","maine","maryland","massachusetts","michigan","minnesota","mississippi","missouri",
        "montana","nebraska","nevada","new hampshire","new jersey","new mexico","new york","north carolina",
        "north dakota","ohio","oklahoma","oregon","pennsylvania","rhode island","south carolina",
        "south dakota","tennessee","texas","utah","vermont","virginia","washington","west virginia",
        "wisconsin","wyoming"]
    static let usCities = ["san francisco","new york","seattle","austin","boston","los angeles","san jose",
        "palo alto","mountain view","sunnyvale","cupertino","san mateo","redwood city","menlo park",
        "bellevue","cambridge","brooklyn","chicago","denver","boulder","atlanta","dallas","houston",
        "san diego","portland","phoenix","miami","philadelphia","minneapolis","raleigh","durham",
        "nashville","salt lake city","pittsburgh","san antonio","charlotte","bay area","silicon valley"]

    /// Canonical country -> substrings that indicate it. Order matters (first match wins).
    static let countries: [(name: String, hints: [String])] = [
        ("United States", ["united states","u.s.a","u.s.","(us)","us-based","us based","usa","americas"] + usStates + usCities),
        ("Canada", ["canada","toronto","vancouver","montreal","ottawa","calgary","waterloo"]),
        ("United Kingdom", ["united kingdom"," uk ","(uk)","england","london","manchester","edinburgh","scotland","wales","bristol"]),
        ("Ireland", ["ireland","dublin"]),
        ("India", ["india","bengaluru","bangalore","hyderabad","pune","mumbai","new delhi","delhi","gurgaon","gurugram","noida","chennai","kolkata"]),
        ("Germany", ["germany","berlin","munich","hamburg","frankfurt","cologne"]),
        ("France", ["france","paris","lyon","toulouse"]),
        ("Netherlands", ["netherlands","amsterdam","rotterdam"]),
        ("Spain", ["spain","madrid","barcelona"]),
        ("Portugal", ["portugal","lisbon","porto"]),
        ("Poland", ["poland","warsaw","krakow"]),
        ("Israel", ["israel","tel aviv"]),
        ("Australia", ["australia","sydney","melbourne","brisbane"]),
        ("Singapore", ["singapore"]),
        ("Japan", ["japan","tokyo"]),
        ("Brazil", ["brazil","sao paulo"]),
        ("Mexico", ["mexico","mexico city","guadalajara"]),
    ]

    /// Countries offered in the picker ("Any" plus the known list).
    static var pickable: [String] { ["Any"] + countries.map(\.name) }

    static func isRemote(_ location: String) -> Bool {
        let l = location.lowercased()
        return l.contains("remote") || l.contains("anywhere") || l.contains("distributed")
    }

    /// Best-guess country for a job location, or nil if unknown.
    static func detectCountry(_ location: String) -> String? {
        let l = location.lowercased()
        guard !l.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        for (name, hints) in countries where hints.contains(where: { l.contains($0) }) { return name }
        return nil
    }

    /// Does the location fall within one of the given state/region tokens?
    static func matchesState(_ location: String, _ states: [String]) -> Bool {
        let l = location.lowercased()
        return states.contains { l.contains($0.lowercased()) }
    }

    /// Filter decision for a job location against the candidate's eligibility prefs.
    static func allows(_ location: String, _ p: EligibilityProfile) -> Bool {
        guard !p.country.isEmpty else { return true }                 // Any country
        if p.includeRemoteGlobal && isRemote(location) { return true } // anywhere-remote
        guard let jc = detectCountry(location) else { return true }    // unknown -> don't hide
        guard jc == p.country else { return false }                    // different country -> hide
        if p.states.isEmpty { return true }
        return matchesState(location, p.states) || isRemote(location)  // narrowed by state
    }
}
