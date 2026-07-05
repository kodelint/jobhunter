import Foundation

enum ConstraintParser {
    // Precompiled once, not per job. Recompiling these per posting was the dominant scan-time
    // CPU cost (tens of thousands of regex compiles across a full scan).
    private static let reDays = try! NSRegularExpression(pattern: #"(\d)\s*days?\s*(?:per week|a week|/week|in office|in the office)"#)
    private static let reYoe = try! NSRegularExpression(pattern: #"(\d{1,2})\+?\s*years?\b[^.\n]{0,40}?(?:experience|exp\b|leading|managing|management|leadership|engineering|building)"#)
    private static let reTravel = try! NSRegularExpression(pattern: #"(\d{1,3})\s*%\s*travel"#)
    private static let reSalary = try! NSRegularExpression(pattern: #"\$\s?([0-9]{2,3}(?:,[0-9]{3})?)\s?([kK])?"#)

    static func parse(_ job: Job) -> JobConstraints {
        var c = JobConstraints()
        let text = (job.title + " " + job.location + " " + job.descriptionText)
        let low = text.lowercased()

        // Work authorization (order matters: negatives before positives)
        if matches(low, ["security clearance", "ts/sci", "must have clearance", "active clearance",
                         "clearance required", "secret clearance"]) {
            c.workAuth = .clearanceRequired; c.clearance = true
        } else if matches(low, ["u.s. citizen", "us citizen", "u.s. citizenship", "us citizenship",
                                "must be a citizen", "citizenship required", "citizens only"]) {
            c.workAuth = .citizensOnly
        } else if matches(low, ["not able to sponsor", "unable to sponsor", "cannot sponsor",
                                "no sponsorship", "does not offer sponsorship", "not offer sponsorship",
                                "without sponsorship", "not provide visa", "no visa sponsorship",
                                "not provide immigration"]) {
            c.workAuth = .noSponsorship
        } else if matches(low, ["visa sponsorship", "we sponsor", "will sponsor", "sponsorship available",
                                "offer sponsorship", "immigration support", "relocation and visa"]) {
            c.workAuth = .sponsorOffered
        } else {
            c.workAuth = .notStated
        }

        // Remote policy
        let hasHybrid = matches(low, ["hybrid"])
        let hasOnsite = matches(low, ["on-site", "onsite", "in office", "in-office", "in person", "in-person"])
        let hasRemote = matches(low, ["fully remote", "remote-first", "remote first", "work from home", "wfh", "remote"])
        if hasHybrid { c.remotePolicy = "Hybrid" }
        else if hasRemote && !hasOnsite { c.remotePolicy = "Remote" }
        else if hasOnsite { c.remotePolicy = "Onsite" }
        if let days = firstCapture(reDays, low), let n = Int(days) { c.remotePolicy = "Hybrid · \(n)d/wk" }

        // Years of experience, anchored to an experience/leadership phrase so we don't grab
        // "5 years ago" or "3 years of runway".
        if let y = firstCapture(reYoe, low), let n = Int(y), n >= 3, n <= 40 {
            c.yoeMin = n
        }

        // Manager vs IC
        if matches(low, ["manager of managers", "managers of managers", "lead a team", "lead the team",
                         "manage a team", "build and lead", "people management", "hire and grow",
                         "grow the team", "directly manage"]) {
            c.managerScope = "manager"
        } else if matches(low, ["individual contributor", "ic role", "hands-on ic", "no direct reports"]) {
            c.managerScope = "ic"
        }

        // Travel
        if let t = firstCapture(reTravel, low) { c.travel = "\(t)% travel" }

        // Salary
        let (mn, mx) = parseSalary(text)
        c.salaryMin = mn; c.salaryMax = mx

        return c
    }

    // MARK: helpers
    private static func matches(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func firstCapture(_ re: NSRegularExpression, _ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // Compensation anchors: a "$..." figure is only trusted as pay if it sits near one of these,
    // so "$500k in funding" / "raised $200M" aren't read as salary.
    // ponytail: substring anchors within 40 chars; false hits (e.g. "$180k" beside "database")
    // are possible but unlikely. Tighten the word list if a real posting misreads.
    private static let compWords = ["salary", "compensation", "base", "pay", "comp", "annual"]

    /// Returns (minK, maxK) salary in thousands, if a plausible range/figure is found near a
    /// compensation keyword. Optional k/K is captured so a bare "$500" isn't read as $500k.
    private static func parseSalary(_ text: String) -> (Int?, Int?) {
        let lowStr = text.lowercased()
        let low = lowStr as NSString
        // Integer offsets of comp-keyword occurrences (O(1) proximity checks below).
        var anchors: [Int] = []
        for kw in compWords {
            var from = 0
            while from < low.length {
                let r = low.range(of: kw, range: NSRange(location: from, length: low.length - from))
                if r.location == NSNotFound { break }
                anchors.append(r.location)
                from = r.location + max(r.length, 1)
            }
        }
        guard !anchors.isEmpty else { return (nil, nil) }

        var vals: [Int] = []
        for m in reSalary.matches(in: lowStr, range: NSRange(location: 0, length: low.length)) {
            let loc = m.range(at: 1).location
            guard loc != NSNotFound, anchors.contains(where: { abs($0 - loc) <= 40 }) else { continue }
            let digits = low.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            guard let num = Int(digits) else { continue }
            let hasK = m.range(at: 2).location != NSNotFound
            let k: Int
            if hasK { k = num }                    // "$150k"
            else if num >= 1000 { k = num / 1000 } // "$150,000"
            else { continue }                      // ambiguous bare "$150" -> skip
            if k >= 60 && k <= 2000 { vals.append(k) }   // plausible comp band
        }
        guard let lo = vals.min(), let hi = vals.max() else { return (nil, nil) }
        return (lo, hi == lo ? nil : hi)
    }
}

// MARK: - Eligibility evaluation (shared by UI + filter)

enum Eligibility {
    struct Chip: Identifiable, Hashable {
        enum Kind { case good, warn, bad, info }
        let id = UUID()
        let text: String
        let kind: Kind
    }

    static func chips(_ job: Job, _ p: EligibilityProfile) -> [Chip] {
        var out: [Chip] = []
        let c = job.constraints
        if p.showComp {
            if let mn = c.salaryMin {
                let label = c.salaryMax != nil ? "$\(mn)k–$\(c.salaryMax!)k base" : "$\(mn)k+ base"
                out.append(Chip(text: label, kind: mn >= p.minBase ? .good : .warn))
            } else {
                out.append(Chip(text: "Comp not stated", kind: .info))
            }
        }
        if p.showAuth { out.append(authChip(c.workAuth, p)) }
        if p.showRemote, !c.remotePolicy.isEmpty {
            let ok = p.workStyles.contains(c.remotePolicy.lowercased().contains("remote") ? "remote"
                     : c.remotePolicy.lowercased().contains("hybrid") ? "hybrid" : "onsite")
            out.append(Chip(text: c.remotePolicy, kind: ok ? .info : .warn))
        }
        if p.showYOE, let y = c.yoeMin { out.append(Chip(text: "\(y)+ yrs", kind: .info)) }
        if p.showScope, c.managerScope == "ic" { out.append(Chip(text: "IC role", kind: .warn)) }
        if p.showScope, c.managerScope == "manager" { out.append(Chip(text: "People leadership", kind: .good)) }
        if p.showTravelOnCall, let t = c.travel { out.append(Chip(text: t, kind: .info)) }
        if p.showClearance, c.clearance { out.append(Chip(text: "Clearance required", kind: .warn)) }
        return out
    }

    private static func authChip(_ a: WorkAuthFinding, _ p: EligibilityProfile) -> Chip {
        let needsSponsor = (p.status == .needsSponsorship)
        switch a {
        case .sponsorOffered: return Chip(text: "Sponsorship offered", kind: needsSponsor ? .good : .info)
        case .noSponsorship:  return Chip(text: "No sponsorship", kind: needsSponsor ? .bad : .info)
        case .citizensOnly:   return Chip(text: "US citizens only", kind: (p.status == .citizen) ? .info : .bad)
        case .clearanceRequired: return Chip(text: "Clearance required", kind: (p.status == .hasClearance) ? .info : .warn)
        case .notStated:      return Chip(text: "Work auth: not stated", kind: .info)
        }
    }

    /// Hard-filter test for "only roles I'm eligible for".
    static func isEligible(_ job: Job, _ p: EligibilityProfile) -> Bool {
        let c = job.constraints
        if p.status != .citizen && c.workAuth == .citizensOnly { return false }
        if p.status == .needsSponsorship && c.workAuth == .noSponsorship { return false }
        if p.status != .hasClearance && c.workAuth == .clearanceRequired { return false }
        if let mn = c.salaryMin, mn < p.minBase { return false }
        return true
    }
}
