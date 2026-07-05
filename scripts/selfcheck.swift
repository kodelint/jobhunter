// Runnable self-check for the pure logic touched by the reliability/sourcing/scoring passes.
// Not part of the app bundle (build-dmg.sh only globs Sources/*.swift). Run with:
//   ./scripts/run-selfcheck.sh
import Foundation

func job(title: String, desc: String = "", loc: String = "Remote (US)") -> Job {
    Job(id: "t::1", company: "Acme", tier: .startup, ats: .greenhouse,
        title: title, location: loc, url: "", department: "Engineering",
        descriptionText: desc, postedAt: "", keywordScore: 0, aiScore: nil,
        aiVerdict: nil, aiReasons: [], aiGaps: [], constraints: .empty,
        status: .active, appliedStage: .none, appliedDate: nil, followUpDate: nil,
        notes: "", firstSeen: "", lastSeen: "", isNew: false)
}

// 1. Deterministic IDs.
assert(ATS.stableHash("https://x/job/1") == ATS.stableHash("https://x/job/1"))
assert(ATS.stableID(42, url: "u", title: "t") == "42")
assert(ATS.stableID("", url: "https://x/1", title: "t").hasPrefix("h"))

// 1b. clean() preserves list/paragraph structure for the description renderer.
let cleaned = ATS.clean("<p>Requirements:</p><ul><li>5y exp</li><li>Go</li></ul>")
assert(cleaned.contains("\n• 5y exp") && cleaned.contains("\n• Go"), "clean must keep bullets: \(cleaned)")
assert(cleaned.contains("Requirements"), "clean must keep heading text")

// 2. YOE anchored; salary "$500" is not $500k.
assert(ConstraintParser.parse(job(title: "Eng", desc: "8+ years of experience leading teams")).yoeMin == 8)
assert(ConstraintParser.parse(job(title: "Eng", desc: "5 years ago; 3 years of runway")).yoeMin == nil)
assert(ConstraintParser.parse(job(title: "Eng", desc: "Get a $500 referral bonus")).salaryMin == nil)
let sal = ConstraintParser.parse(job(title: "Eng", desc: "Base $150k - $200k plus equity"))
assert(sal.salaryMin == 150 && sal.salaryMax == 200)
// M3: a $-figure with no compensation keyword nearby is not read as salary.
assert(ConstraintParser.parse(job(title: "Eng", desc: "We just raised $500k in seed funding.")).salaryMin == nil)

// 3. Skill phrases tokenize into atomic terms (the low-score bug fix).
let toks = MatchProfile.tokenizeSkills(["Cloud & Platform Engineering (AWS, Azure, GCP)"])
assert(toks["aws"] != nil && toks["platform engineering"] != nil, "phrase skills must yield atomic terms")

// 4. Level ranking sanity.
assert(MatchProfile.levelRank("VP of Engineering") == 7)
assert(MatchProfile.levelRank("Director, Engineering") == 6)
assert(MatchProfile.levelRank("Principal Engineer") == 5)
assert(MatchProfile.levelRank("Senior Software Engineer") == 3)
assert(MatchProfile.levelRank("Software Engineer") == 2)

// 5. Country detection + filter.
assert(Geo.detectCountry("Bengaluru, India") == "India")
assert(Geo.detectCountry("Austin, Texas") == "United States")
var us = EligibilityProfile(); us.country = "United States"
assert(!Geo.allows("Bengaluru, India", us))                 // foreign hidden
assert(Geo.allows("Remote - Anywhere", us))                 // anywhere-remote shown (default on)
assert(Geo.allows("Austin, TX", us))                        // in-country shown

// 6. Derived profile now scores a real role whose skills are phrases (was near-zero before).
let fe = ExtractedProfile(summary: "FE", level: "Senior Software Engineer",
    targetTitles: ["Frontend Engineer", "Software Engineer"],
    skills: ["React & TypeScript (Next.js)", "CSS"], idealRoles: "", country: "United States")
let derived = MatchProfile.make(profile: fe)
assert(KeywordScorer.score(job(title: "Frontend Engineer", desc: "We use React, TypeScript and Next.js"),
                           profile: derived) != nil, "derived profile should score a matching role")

print("selfcheck OK")
