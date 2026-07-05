import Foundation

// MARK: - Enums

enum ATSKind: String, CaseIterable, Identifiable, Codable {
    case greenhouse, ashby, lever, smartrecruiters, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .greenhouse: return "Greenhouse"
        case .ashby: return "Ashby"
        case .lever: return "Lever"
        case .smartrecruiters: return "SmartRecruiters"
        case .manual: return "Manual"
        }
    }
    /// Scannable job boards. `manual` is a user-entered application origin, not a board, so it is
    /// excluded from source pickers, the scan loop, and the source mix.
    static let sources: [ATSKind] = [.greenhouse, .ashby, .lever, .smartrecruiters]
}

enum Tier: String, CaseIterable, Identifiable, Codable {
    case startup, enterprise
    var id: String { rawValue }
    var label: String { self == .startup ? "Startup" : "Enterprise" }
}

enum JobStatus: String, Codable { case active, applied, ignored, wrongMatch }

enum AppliedStage: String, CaseIterable, Identifiable, Codable {
    case none, applied, interviewing, offer, rejected
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Not applied"
        case .applied: return "Applied"
        case .interviewing: return "Interviewing"
        case .offer: return "Offer"
        case .rejected: return "Rejected"
        }
    }
}

enum JobTab: String, CaseIterable, Identifiable, Hashable {
    case new = "New"
    case all = "All matches"
    case low = "Low matches"
    case favorites = "Favorites"
    case applied = "Applied"
    case ignored = "Ignored"
    case wrong = "Wrong matches"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .new: return "sparkles"
        case .all: return "tray.full"
        case .low: return "arrow.down.circle"
        case .favorites: return "star.fill"
        case .applied: return "checkmark.seal"
        case .ignored: return "archivebox"
        case .wrong: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Eligibility & constraints

enum WorkAuthFinding: String, Codable {
    case sponsorOffered, noSponsorship, citizensOnly, clearanceRequired, notStated
}

enum EligibilityStatus: String, CaseIterable, Identifiable, Codable {
    case citizen, needsSponsorship, greenCard, hasClearance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .citizen: return "US citizen"
        case .needsSponsorship: return "Need sponsorship"
        case .greenCard: return "Green card / PR"
        case .hasClearance: return "Have clearance"
        }
    }
}

struct JobConstraints: Codable, Hashable, Sendable {
    var salaryMin: Int?
    var salaryMax: Int?
    var workAuth: WorkAuthFinding = .notStated
    var remotePolicy: String = ""      // e.g. "Remote (US)", "Hybrid · SF", "Onsite"
    var yoeMin: Int?
    var managerScope: String = ""      // "manager", "ic", ""
    var travel: String?
    var clearance: Bool = false

    static let empty = JobConstraints()
}

struct EligibilityProfile: Codable, Hashable {
    var status: EligibilityStatus = .citizen
    var minBase: Int = 0                // in thousands (USD)
    var workStyles: Set<String> = ["remote", "hybrid", "onsite"]
    var onlyEligible: Bool = false      // hard filter
    // Location filter (country auto-seeded from the resume; user-editable).
    var country: String = ""            // "" = Any country
    var states: [String] = []           // optional narrowing within the country (e.g. ["CA","NY"])
    var includeRemoteGlobal: Bool = true // still show anywhere-remote roles outside the country
    // Level filter: strict (target band and up) unless the candidate opts to see below.
    var includeBelowLevel: Bool = false
    // which constraint chips to show
    var showComp = true
    var showAuth = true
    var showRemote = true
    var showYOE = true
    var showScope = true
    var showTravelOnCall = true
    var showClearance = true

    static let `default` = EligibilityProfile()
}

// MARK: - Value types

struct Company: Identifiable, Hashable {
    var id: Int64
    var name: String
    var ats: ATSKind
    var token: String
    var tier: Tier
    var enabled: Bool
}

struct AIEvaluation: Codable {
    var score: Int
    var verdict: String
    var reasons: [String]
    var gaps: [String]
    var constraints: JobConstraints?
    // Per-signal sub-scores (0-100): leadership, location, technical, domain, compensation.
    var subscores: [String: Int]?
}

/// Ordered fit signals for the per-signal breakdown (key -> display label).
enum FitSignal {
    static let ordered: [(key: String, label: String)] = [
        ("leadership", "Leadership scope"), ("location", "Location & remote"),
        ("technical", "Technical depth"), ("domain", "Domain overlap"),
        ("compensation", "Compensation")
    ]
}

struct Job: Identifiable, Hashable, Sendable {
    var id: String
    var company: String
    var tier: Tier?
    var ats: ATSKind
    var title: String
    var location: String
    var url: String
    var department: String
    var descriptionText: String
    var postedAt: String

    var keywordScore: Int
    var aiScore: Int?
    var aiVerdict: String?
    var aiReasons: [String]
    var aiGaps: [String]
    var aiSubscores: [String: Int] = [:]
    var constraints: JobConstraints

    var status: JobStatus
    var appliedStage: AppliedStage
    var appliedDate: String?
    var followUpDate: String?
    var interviewDate: String? = nil
    var notes: String

    var firstSeen: String
    var lastSeen: String
    var isNew: Bool
    var favorite: Bool = false

    var effectiveScore: Int { aiScore ?? keywordScore }
    var evaluatedByAI: Bool { aiScore != nil }
}

struct ExtractedProfile: Codable {
    var summary: String
    var level: String
    var targetTitles: [String]
    var skills: [String]
    var idealRoles: String
    var country: String = ""            // candidate's country, inferred from the resume

    static let empty = ExtractedProfile(summary: "", level: "", targetTitles: [], skills: [], idealRoles: "", country: "")
}
