import Foundation

struct MatchProfile: Sendable {
    var functionTitle: [String]     // words that, in the TITLE, mark a relevant function
    var functionBody: [String]      // words that, anywhere, mark a relevant function
    var skills: [String: Int]       // atomic skill terms -> weight
    var excludes: [String]          // junk terms that disqualify a title outright
    var minScore: Int

    /// Build a scorer from the resume analysis. Level and location are handled as display
    /// filters (see AppStore), so this only judges function + skill relevance.
    static func make(profile: ExtractedProfile) -> MatchProfile {
        guard !(profile.targetTitles.isEmpty && profile.skills.isEmpty) else { return builtinDefault }
        let titleTokens = tokenize(profile.targetTitles)
        let skillTokens = tokenizeSkills(profile.skills)
        return MatchProfile(
            functionTitle: titleTokens,
            functionBody: titleTokens + Array(skillTokens.keys),
            skills: skillTokens,
            excludes: baseExcludes,
            minScore: 30)
    }

    /// Generic junk only; role-specific excludes are NOT applied to a derived profile.
    static let baseExcludes = ["intern", "internship", "new grad", "co-op", "apprentice", "student"]

    /// Significant words from target titles (drops filler + seniority words scored separately).
    static func tokenize(_ titles: [String]) -> [String] {
        let stop: Set<String> = ["of", "and", "the", "for", "senior", "junior", "lead", "principal",
                                 "staff", "director", "manager", "head", "vice", "president", "chief"]
        var seen = Set<String>(); var out: [String] = []
        for t in titles {
            for w in t.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            where w.count >= 3 && !stop.contains(w) && !seen.contains(w) {
                seen.insert(w); out.append(w)
            }
        }
        return out
    }

    /// Break AI skill entries (often phrases like "Cloud & Platform Engineering (AWS, Azure, GCP)")
    /// into atomic, matchable terms. Without this, whole-phrase matching finds nothing and every
    /// role scores near zero.
    static func tokenizeSkills(_ skills: [String]) -> [String: Int] {
        let stop: Set<String> = ["of", "and", "the", "for", "with", "to", "a", "an", "or", "in", "on"]
        var out: [String: Int] = [:]
        for raw in skills {
            let lowered = raw.lowercased()
            let phrases = lowered.split(whereSeparator: { "&/,()|;:-".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for p in phrases {
                let words = p.split(separator: " ").map(String.init).filter { !$0.isEmpty }
                if words.count >= 1 && words.count <= 3 {
                    let term = words.filter { !stop.contains($0) }.joined(separator: " ")
                    if term.count >= 2 { out[term] = max(out[term] ?? 0, 3) }
                }
                for w in words where w.count >= 3 && !stop.contains(w) {
                    out[w] = max(out[w] ?? 0, 2)
                }
            }
        }
        return out
    }

    /// Fallback for users who haven't analyzed a resume yet (senior-infra bias, curated atomic skills).
    static let builtinDefault = MatchProfile(
        functionTitle: ["engineering", "infrastructure", "platform", "sre", "site reliability",
                        "reliability", "cloud", "devops", "systems", "data", "security", "software"],
        functionBody: ["engineering", "infrastructure", "platform", "sre", "reliability", "cloud",
                       "devops", "kubernetes", "observability", "software", "backend"],
        skills: ["kubernetes": 4, "sre": 5, "reliability": 3, "platform": 4, "infrastructure": 4,
                 "aws": 2, "azure": 2, "gcp": 2, "terraform": 2, "observability": 3, "python": 2,
                 "go": 2, "docker": 2, "ci/cd": 2, "microservices": 2, "distributed systems": 3,
                 "react": 2, "typescript": 2, "sql": 2, "api": 2, "security": 2],
        excludes: ["intern", "new grad", "co-op", "apprentice", "student"],
        minScore: 30)

    // MARK: level ranking (1 = junior ... 8 = C-level); used by scoring + the level filter.
    // Word-set membership only - NO regex, because this runs per-job inside the render path.
    static func levelRank(_ text: String) -> Int {
        let t = text.lowercased()
        let words = Set(t.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func w(_ s: String) -> Bool { words.contains(s) }
        if !words.isDisjoint(with: ["chief", "cxo", "cto", "cfo", "coo", "ceo", "svp", "evp"]) { return 8 }
        if w("vp") || t.contains("vice president") || t.contains("head of") { return 7 }
        if t.contains("senior director") || t.contains("sr director") || w("director") { return 6 }
        if w("principal") || w("distinguished") || w("fellow") || t.contains("senior manager") { return 5 }
        if w("staff") || w("manager") || w("lead") { return 4 }
        if w("senior") || w("sr") { return 3 }
        if w("junior") || w("jr") || w("associate") || w("intern") || t.contains("new grad") || w("entry") || w("apprentice") { return 1 }
        return 2  // mid / unspecified
    }
    static func levelPoints(_ rank: Int) -> Int {
        switch rank {
        case 8: return 30; case 7: return 28; case 6: return 24; case 5: return 20
        case 4: return 14; case 3: return 10; case 1: return 3; default: return 6
        }
    }
}

enum KeywordScorer {
    /// Function + skill relevance score (0-100), or nil if the role isn't in the candidate's field.
    /// Level and location are NOT gated here - they are instant display filters in AppStore.
    /// Word-set membership (single words) + substring (multiword terms); no regex.
    static func score(_ job: Job, profile: MatchProfile) -> Int? {
        let title = job.title.lowercased()
        let body = (job.title + " " + job.department + " " + job.descriptionText).lowercased()

        for bad in profile.excludes where title.contains(bad) { return nil }

        let titleWords = Set(title.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let bodyWords = Set(body.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func inTitle(_ t: String) -> Bool { t.contains(" ") ? title.contains(t) : titleWords.contains(t) }
        func inBody(_ t: String) -> Bool { t.contains(" ") ? body.contains(t) : bodyWords.contains(t) }

        let fnTitle = profile.functionTitle.contains(where: inTitle)
        let fnBody = profile.functionBody.contains(where: inBody)
        if !fnTitle && !fnBody { return nil }
        let fnPts = fnTitle ? 25 : 8

        let levelPts = MatchProfile.levelPoints(MatchProfile.levelRank(job.title))

        var skillPts = 0
        for (skill, w) in profile.skills where inBody(skill) { skillPts += w }
        skillPts = min(skillPts, 42)

        let total = min(levelPts + fnPts + skillPts, 100)
        return total >= profile.minScore ? total : nil
    }
}
