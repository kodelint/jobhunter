import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    struct ScanProgress {
        var running = false
        var phase = ""
        var done = 0
        var total = 0
        var fraction: Double = 0
    }

    let db = Database()
    let settings = Settings()

    var companies: [Company] = []
    var jobs: [Job] = []
    var resumeText = ""
    var profile: ExtractedProfile = .empty
    var search = ""
    var scan = ScanProgress()
    var lastScan = ""
    var toast: String?
    var lastInboxSync = ""
    var inboxSyncing = false

    // Cached AI-key readiness so SwiftUI `body` never hits the Keychain or shells out.
    // Resolved off the main thread by refreshAIState() (launch / provider change / key save).
    var aiReady = false
    var aiKeySource = "none"   // "keychain" | "env" | "none"

    // Below this effective score, a relevant role goes to the "Low matches" tab, not New/All.
    static let lowFit = 55
    // Hard cap on stored active, non-favorite postings (purge keeps the top scorers).
    static let storeCap = 1200

    /// Derived aggregates cached so SwiftUI renders are O(1) instead of re-scanning the whole
    /// jobs array (sidebar counts, dashboard tiles) on every frame. Refreshed on load/mutation/scan.
    struct Stats {
        var counts: [JobTab: Int] = [:]
        var stage: [AppliedStage: Int] = [:]
        var fit = [0, 0, 0, 0]        // strong / good / fair / low
        var followUps: [Job] = []
        var responses: [Job] = []
        var topNew: [Job] = []
    }
    var stats = Stats()

    init() {
        syncSeeds()
        reload()
        EnvKeys.prefetch()
        refreshAIState()
    }

    // MARK: loading
    func reload() {
        companies = db.allCompanies()
        jobs = db.allJobs()
        if let r = db.loadResume() { resumeText = r.text; profile = r.profile }
        lastScan = db.meta("lastScan") ?? ""
        lastInboxSync = db.meta("lastInboxSync") ?? ""
        refreshStats()
    }

    /// Recompute all cached aggregates in one pass. Call after load / mutation / scan / filter change.
    func refreshStats() {
        var c: [JobTab: Int] = [:]; for t in JobTab.allCases { c[t] = 0 }
        var st: [AppliedStage: Int] = [:]
        var fit = [0, 0, 0, 0]
        var fups: [Job] = []; var resp: [Job] = []; var newList: [Job] = []
        let today = Self.today
        for j in jobs {
            for t in JobTab.allCases where visible(j, t) { c[t]! += 1 }
            if j.status == .applied { st[j.appliedStage, default: 0] += 1 }
            if j.status == .active, passesRelevance(j) {
                let s = j.effectiveScore
                if s >= 85 { fit[0] += 1 } else if s >= 70 { fit[1] += 1 } else if s >= 55 { fit[2] += 1 } else { fit[3] += 1 }
            }
            if visible(j, .new) { newList.append(j) }
            if let d = j.followUpDate, !d.isEmpty, d <= today { fups.append(j) }
            if j.status == .applied, [.interviewing, .offer, .rejected].contains(j.appliedStage) { resp.append(j) }
        }
        stats = Stats(
            counts: c, stage: st, fit: fit,
            followUps: fups.sorted { ($0.followUpDate ?? "") < ($1.followUpDate ?? "") },
            responses: resp.sorted { ($0.appliedDate ?? "") > ($1.appliedDate ?? "") },
            topNew: newList.sorted { $0.effectiveScore > $1.effectiveScore })
    }

    /// Append-only seeding: adds seed companies beyond what's already been applied,
    /// so new built-in sources appear on upgrade without re-adding ones you deleted.
    private func syncSeeds() {
        let total = SeedData.companies.count
        let applied: Int
        if let s = db.meta("seedCount"), let n = Int(s) { applied = n }
        else { applied = (db.companyCount() == 0) ? 0 : 49 } // migrate installs seeded before versioning
        if applied < total {
            for entry in SeedData.companies[applied..<total] {
                db.upsertCompany(name: entry.0, ats: entry.1, token: entry.2, tier: entry.3)
            }
        }
        db.setMeta("seedCount", String(total))
    }

    // MARK: filtering
    func count(_ tab: JobTab) -> Int { stats.counts[tab] ?? 0 }

    /// Single source of truth for whether a job belongs in a tab (used by list + cached counts).
    func visible(_ j: Job, _ tab: JobTab) -> Bool {
        let e = settings.eligibility
        switch tab {
        case .favorites: return j.favorite
        case .applied:   return j.status == .applied
        case .ignored:   return j.status == .ignored
        case .wrong:     return j.status == .wrongMatch
        case .new, .all, .low:
            guard j.status == .active, passesRelevance(j) else { return false }
            if e.onlyEligible, !Eligibility.isEligible(j, e) { return false }
            let s = j.effectiveScore
            if tab == .low { return s < Self.lowFit }
            if s < Self.lowFit { return false }
            if settings.showMinFit > 0, s < settings.showMinFit { return false }
            return tab == .all ? true : j.isNew
        }
    }

    func filtered(_ tab: JobTab, ignoreSearch: Bool = false) -> [Job] {
        var list = jobs.filter { visible($0, tab) }
        if !ignoreSearch && !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { $0.title.lowercased().contains(q) || $0.company.lowercased().contains(q) }
        }
        return list.sorted { $0.effectiveScore > $1.effectiveScore }
    }

    /// Location + target-level relevance (instant display filter; no rescan needed on change).
    func passesRelevance(_ job: Job) -> Bool {
        let e = settings.eligibility
        if !Geo.allows(job.location, e) { return false }
        if !e.includeBelowLevel {
            let cand = profile.level.isEmpty ? 0 : MatchProfile.levelRank(profile.level)
            let jobRank = MatchProfile.levelRank(job.title)
            // rank 2 == unspecified seniority: many Greenhouse/Lever titles omit the band, so
            // only hide titles that EXPLICITLY rank below the floor - never the unspecified ones.
            if cand > 0, jobRank != 2, jobRank < max(cand - 2, 1) { return false }
        }
        return true
    }

    // MARK: job actions
    private func mutate(_ id: String, _ change: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { change(&jobs[i]); refreshStats() }
    }
    func toggleFavorite(_ job: Job) { db.setFavorite(job.id, !job.favorite); mutate(job.id) { $0.favorite.toggle() } }
    func markApplied(_ job: Job) { setStage(job, .applied) }
    func setStage(_ job: Job, _ stage: AppliedStage) {
        let date = stage == .none ? nil : Self.today
        db.setAppliedStage(job.id, stage, date: date)
        mutate(job.id) { $0.appliedStage = stage; $0.appliedDate = date
            $0.status = stage == .none ? .active : .applied }
    }
    func ignore(_ job: Job) { db.setStatus(job.id, .ignored); mutate(job.id) { $0.status = .ignored } }

    /// Flag a role as a WRONG match: fundamentally mismatched to the resume (wrong function, domain,
    /// seniority, or location). Distinct from ignore (a personal "not interested"). This is the
    /// signal the AI learns from - the reason is stored and injected into future evaluations so
    /// similar opposite-of-profile roles score low. Always records an entry (title is itself signal).
    func markWrongMatch(_ job: Job, reason: String) {
        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = "\(job.title) at \(job.company): \(r.isEmpty ? "not relevant to my background" : r)"
        var fb = settings.matchFeedback.filter { $0 != entry }
        fb.append(entry)
        settings.matchFeedback = Array(fb.suffix(30))   // bound stored history
        db.setStatus(job.id, .wrongMatch)
        mutate(job.id) { $0.status = .wrongMatch }
    }

    func removeMatchFeedback(_ entry: String) {
        settings.matchFeedback.removeAll { $0 == entry }
    }
    func restore(_ job: Job) { db.setStatus(job.id, .active); mutate(job.id) { $0.status = .active } }
    func setNotes(_ job: Job, _ notes: String) { db.setNotes(job.id, notes); mutate(job.id) { $0.notes = notes } }
    func setFollowUp(_ job: Job, _ date: String?) { db.setFollowUp(job.id, date); mutate(job.id) { $0.followUpDate = date } }
    func setInterviewDate(_ job: Job, _ date: String?) { db.setInterviewDate(job.id, date); mutate(job.id) { $0.interviewDate = date } }

    /// Track an application made outside the scanned sources (e.g. a company's own Workday portal).
    /// Stored like any applied job, so Gmail inbox sync updates its stage automatically; without
    /// Gmail, the candidate sets the stage themselves here and in the job's Tracking card.
    func addManualJob(company: String, title: String, url: String, location: String,
                      stage: AppliedStage, notes: String) {
        let today = Self.today
        let job = Job(
            id: "manual::\(UUID().uuidString)", company: company, tier: nil, ats: .manual,
            title: title, location: location, url: url, department: "", descriptionText: "",
            postedAt: "", keywordScore: 0, aiScore: nil, aiVerdict: nil, aiReasons: [], aiGaps: [],
            constraints: .empty, status: .applied, appliedStage: stage,
            appliedDate: today, followUpDate: nil, notes: notes,
            firstSeen: today, lastSeen: today, isNew: false, favorite: false)
        db.insertJob(job)
        jobs = db.allJobs()
        refreshStats()
        toast = "Tracking \(title) at \(company)."
    }

    // MARK: company actions
    func addCompany(name: String, ats: ATSKind, token: String, tier: Tier) {
        db.upsertCompany(name: name, ats: ats, token: token, tier: tier); companies = db.allCompanies()
    }
    func toggleCompany(_ c: Company) { db.setCompanyEnabled(c.id, !c.enabled); companies = db.allCompanies() }
    func deleteCompany(_ c: Company) { db.deleteCompany(c.id); companies = db.allCompanies() }

    // MARK: resume
    func setResume(text: String) {
        resumeText = text
        db.saveResume(text: text, profile: profile)
    }
    func analyzeResume() async {
        guard !resumeText.isEmpty else { toast = "Import a resume first."; return }
        guard let cfg = aiConfig() else { toast = "Add an API key in AI settings first."; return }
        do {
            profile = try await AIService.analyzeResume(resumeText, cfg: cfg)
            // Seed the location filter from the resume the first time (user can still change it).
            if settings.eligibility.country.isEmpty, Geo.pickable.contains(profile.country) {
                settings.eligibility.country = profile.country
            }
            db.saveResume(text: resumeText, profile: profile)
        } catch { toast = error.localizedDescription }
    }

    // MARK: AI config
    /// Keychain first, then environment variable (ANTHROPIC_API_KEY, etc.).
    func resolvedKey(_ p: AIProvider) -> String {
        if let k = Keychain.get(p.keychainAccount), !k.isEmpty { return k }
        if let e = EnvKeys.value(for: p) { return e }
        return ""
    }

    func aiConfig() -> AIConfig? {
        let p = settings.provider
        let key = resolvedKey(p)
        if p.needsKey && key.isEmpty { return nil }
        return AIConfig(provider: p, model: settings.model, apiKey: key, baseURL: settings.baseURL)
    }

    /// Resolve the current provider's key OFF the render path and cache readiness, so SwiftUI
    /// `body` reads `aiReady`/`aiKeySource` instead of touching the Keychain or spawning a shell.
    /// Call at launch, on provider change, and after a key is saved or removed.
    func refreshAIState() {
        let p = settings.provider
        Task.detached {
            let src: String
            if let k = Keychain.get(p.keychainAccount), !k.isEmpty { src = "keychain" }
            else if EnvKeys.hasValue(for: p) { src = "env" }
            else { src = "none" }
            await MainActor.run {
                self.aiKeySource = src
                self.aiReady = !p.needsKey || src != "none"
            }
        }
    }

    // MARK: pipeline metrics (all read from cached stats -> O(1) in the render path)
    func stageCount(_ stage: AppliedStage) -> Int { stats.stage[stage] ?? 0 }
    var responses: [Job] { stats.responses }
    var responsesCount: Int { stats.responses.count }
    var topNewFit: Job? { stats.topNew.first }
    var followUpsDue: [Job] { stats.followUps }

    // MARK: dashboard metrics (derived; modules hide themselves when there's nothing to show)
    /// Average effective fit across current matches.
    var avgMatchFit: Int {
        let m = filtered(.all, ignoreSearch: true)
        return m.isEmpty ? 0 : m.map(\.effectiveScore).reduce(0, +) / m.count
    }
    /// Change in avg fit vs the previous scan (nil until there are two scans).
    var fitTrend: Int? {
        let h = db.scanHistory(limit: 2)
        return h.count >= 2 ? h[0].avgFit - h[1].avgFit : nil
    }
    /// Heuristic 0-100 completeness of the user's setup.
    var profileStrength: Int {
        var s = 0
        if !resumeText.isEmpty { s += 35 }
        if !profile.summary.isEmpty { s += 15 }
        if !profile.skills.isEmpty { s += 10 }
        if aiReady { s += 15 }
        if !settings.eligibility.country.isEmpty { s += 10 }
        if companies.contains(where: { $0.enabled }) { s += 10 }
        if gmailConfigured() { s += 5 }
        return min(s, 100)
    }
    /// Roles currently in the interviewing stage (interview module is Gmail-gated in the UI).
    var interviewingJobs: [Job] {
        jobs.filter { $0.appliedStage == .interviewing }
            .sorted { ($0.interviewDate ?? "~") < ($1.interviewDate ?? "~") }
    }
    /// Weekly new-match counts for the last 7 calendar days (oldest -> newest).
    func weeklyNewMatches() -> [(label: String, count: Int)] {
        let hist = db.scanHistory(limit: 60)
        var byDay: [String: Int] = [:]
        for row in hist { byDay[row.day, default: 0] += row.new }
        let cal = Calendar.current
        let inits = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).reversed().map { back in
            let date = cal.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let label = inits[cal.component(.weekday, from: date) - 1]
            return (label, byDay[Self.ymd(date)] ?? 0)
        }
    }
    /// Market comp band (in $k) inferred from parsed salaries across current matches.
    var marketBand: (low: Int, high: Int, target: Int)? {
        let sals = filtered(.all, ignoreSearch: true).compactMap { $0.constraints.salaryMin }.sorted()
        guard sals.count >= 3 else { return nil }
        return (sals[sals.count / 10], sals[sals.count * 9 / 10], settings.eligibility.minBase)
    }

    // MARK: Gmail inbox sync
    static let gmailAccount = "gmail.apppassword"

    func gmailConfigured() -> Bool {
        settings.gmailEnabled && !settings.gmailAddress.isEmpty && !(Keychain.get(Self.gmailAccount) ?? "").isEmpty
    }

    func syncInbox() async {
        let email = settings.gmailAddress
        guard settings.gmailEnabled, !email.isEmpty, let pass = Keychain.get(Self.gmailAccount), !pass.isEmpty else {
            toast = "Connect Gmail in the Inbox tab first."; return
        }
        guard !inboxSyncing else { return }
        inboxSyncing = true
        let days = settings.inboxSyncDays
        let result = await Task.detached { GmailService.fetchRecent(email: email, appPassword: pass, days: days) }.value
        inboxSyncing = false
        switch result {
        case .failure(let e): toast = e.localizedDescription
        case .success(let msgs):
            let n = applyInbox(messages: msgs)
            let now = Self.displayNow
            db.setMeta("lastInboxSync", now); lastInboxSync = now
            jobs = db.allJobs()
            toast = n == 0 ? "Inbox synced — no new status changes." : "Inbox synced — \(n) application\(n == 1 ? "" : "s") updated."
        }
    }

    private func applyInbox(messages: [GmailService.Msg]) -> Int {
        let applied = jobs.filter { $0.status == .applied }
        guard !applied.isEmpty, !messages.isEmpty else { return 0 }
        let stop: Set<String> = ["inc","llc","labs","the","corp","technologies","systems","software","group","company","holdings"]
        func tokens(_ name: String) -> [String] {
            name.lowercased()
                .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
                .split(separator: " ").map(String.init)
                .filter { $0.count >= 4 && !stop.contains($0) }
        }
        var changed = 0
        for job in applied {
            let toks = tokens(job.company)
            guard !toks.isEmpty else { continue }
            let cands = messages.filter { m in
                // Word-boundary match (not raw substring) so "notion" doesn't hit "promotions".
                let hay = (m.subject + " " + m.from).lowercased()
                let words = Set(hay.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                return toks.contains { words.contains($0) }
            }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            guard !cands.isEmpty else { continue }
            var detected: GmailService.Detected?; var src: GmailService.Msg?
            for m in cands { if let d = GmailService.classify(subject: m.subject, from: m.from) { detected = d; src = m; break } }
            guard let d = detected, let m = src else { continue }
            let newStage: AppliedStage
            switch d {
            case .received: continue
            case .interviewing: newStage = .interviewing
            case .offer: newStage = .offer
            case .rejected: newStage = .rejected
            }
            if job.appliedStage == newStage { continue }
            if job.appliedStage == .offer && newStage != .offer { continue } // don't downgrade an offer
            db.setAppliedStage(job.id, newStage, date: job.appliedDate ?? Self.today)
            let note = "\u{1F4E7} \(d.rawValue.capitalized) detected from email: \"\(m.subject)\""
            db.setNotes(job.id, job.notes.isEmpty ? note : job.notes + "\n" + note)
            changed += 1
        }
        return changed
    }

    // MARK: scan
    func scanNow() async {
        guard !scan.running else { return }
        toast = nil
        scan = ScanProgress(running: true, phase: "Fetching postings…", done: 0, total: 0, fraction: 0)
        let enabled = companies.filter { $0.enabled }
        scan.total = enabled.count

        var collected: [Job] = []
        var unchanged = 0          // boards that returned 304 (served from cache)
        var fetchErrors = 0
        var firstError: String?    // keep one real message so failures are diagnosable
        // Job IDs we already have per board, so SmartRecruiters only detail-fetches NEW postings.
        var knownByBoard: [String: Set<String>] = [:]
        for j in jobs { knownByBoard["\(j.ats.rawValue)::\(j.company)", default: []].insert(j.id) }
        await withTaskGroup(of: (Company, ATS.FetchResult).self) { group in
            for c in enabled {
                let v = db.cacheValidators(ats: c.ats, token: c.token)   // read validators on main
                let known = knownByBoard["\(c.ats.rawValue)::\(c.name)"] ?? []
                group.addTask { (c, await ATS.fetch(c, etag: v.etag, lastModified: v.lastModified, known: known)) }
            }
            for await (c, r) in group {
                if r.notModified {
                    unchanged += 1
                } else if let err = r.error {
                    fetchErrors += 1
                    if firstError == nil { firstError = "\(c.name): \(err)" }
                } else {
                    db.setCache(ats: c.ats, token: c.token, etag: r.etag, lastModified: r.lastModified)
                    collected += r.jobs
                }
                scan.done += 1
                scan.fraction = Double(scan.done) / Double(max(scan.total, 1)) * 0.5
            }
        }

        scan.phase = "Scoring matches…"
        let mp = MatchProfile.make(profile: profile)
        let snapshot = collected
        // Scoring + constraint parsing is the CPU-heavy part; run it off the main thread so the
        // UI stays responsive during a scan (this was the source of the mid-scan freeze).
        let toStore: [Job] = await Task.detached {
            var map: [String: Job] = [:]
            for var j in snapshot {
                guard let s = KeywordScorer.score(j, profile: mp) else { continue }
                j.keywordScore = s
                j.constraints = ConstraintParser.parse(j)
                if let e = map[j.id] { if s > e.keywordScore { map[j.id] = j } } else { map[j.id] = j }
            }
            return Array(map.values)
        }.value
        let runDate = Self.today
        db.transaction { for j in toStore { db.upsertScannedJob(j, runDate: runDate) } }
        // Retention: drop stale postings now (by age). The score-based cap runs AFTER AI scoring
        // (below) so a high AI-fit role isn't purged on its keyword score alone.
        db.purgeStale(cutoff: Self.cutoff(daysAgo: settings.retentionDays))
        jobs = db.allJobs()
        refreshStats()

        // AI evaluation of the shortlist
        var aiScored = 0
        let canUseResume = !profile.summary.isEmpty || !resumeText.isEmpty
        if settings.useAI, canUseResume, let cfg = aiConfig() {
            let shortlist = Array(jobs.filter { $0.status == .active && $0.aiScore == nil && passesRelevance($0) }
                .sorted { $0.keywordScore > $1.keywordScore }.prefix(settings.topN))
            scan.phase = "Evaluating fit with \(cfg.provider.label)…"
            scan.total = shortlist.count; scan.done = 0
            let prof = profile, resume = resumeText, feedback = settings.matchFeedback
            // Bounded-concurrency eval: keep up to `maxInFlight` calls in flight so the network-bound
            // AI phase runs ~Nx faster without hammering provider rate limits (per-call retry lives in
            // AIService.post). ponytail: fixed cap; expose as a setting if a provider's limits bite.
            let maxInFlight = 4
            await withTaskGroup(of: (String, AIEvaluation?).self) { group in
                var it = shortlist.makeIterator()
                func addNext() {
                    guard let j = it.next() else { return }
                    group.addTask {
                        (j.id, try? await AIService.evaluate(job: j, profile: prof, resume: resume, feedback: feedback, cfg: cfg))
                    }
                }
                for _ in 0..<maxInFlight { addNext() }
                for await (id, eval) in group {
                    if let eval { db.setAI(id, eval) }
                    else if toast == nil { toast = "Some AI evaluations failed (rate limit or network)." }
                    scan.done += 1
                    scan.fraction = 0.5 + Double(scan.done) / Double(max(shortlist.count, 1)) * 0.5
                    addNext()
                }
            }
            jobs = db.allJobs()
            refreshStats()
            aiScored = shortlist.count
            // (score-based cap applied below, after AI scores land)
        } else if settings.useAI && !canUseResume {
            toast = "Add your resume to enable AI fit scoring — showing keyword matches for now."
        }

        // Cap by effective score (AI where present) so we keep the best-fit roles, not the keyword-best.
        if db.capActive(max: Self.storeCap) > 0 {
            jobs = db.allJobs()
            refreshStats()
        }

        // Snapshot this scan for the weekly chart + fit trend arrow.
        let activeMatches = filtered(.all, ignoreSearch: true)
        let avg = activeMatches.isEmpty ? 0 : activeMatches.map(\.effectiveScore).reduce(0, +) / activeMatches.count
        db.recordScan(newCount: jobs.filter { $0.isNew && $0.status == .active }.count,
                      matchCount: activeMatches.count, avgFit: avg)

        let now = Self.displayNow
        db.setMeta("lastScan", now); lastScan = now
        scan = ScanProgress(running: false, phase: "", done: 0, total: 0, fraction: 1)

        // Concise summary so token/fetch savings are visible.
        let newCount = jobs.filter { $0.isNew && $0.status == .active }.count
        var parts: [String] = ["Scanned \(enabled.count) sources"]
        if unchanged > 0 { parts.append("\(unchanged) unchanged (cached)") }
        parts.append("\(newCount) new")
        if aiScored > 0 { parts.append("AI-scored \(aiScored)") }
        else if settings.useAI { parts.append("no new AI calls needed") }
        if fetchErrors > 0 {
            parts.append("\(fetchErrors) errored")
            if let firstError { parts.append("first: \(firstError)") }
        }
        if toast == nil { toast = parts.joined(separator: " · ") }
    }

    // MARK: dates
    // DateFormatter is expensive to allocate and thread-safe to reuse; cache the two we need.
    private static let ymdFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let displayFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    static var today: String { ymd(Date()) }
    static func ymd(_ d: Date) -> String { ymdFormatter.string(from: d) }
    static func parseYMD(_ s: String) -> Date? { ymdFormatter.date(from: s) }
    static func cutoff(daysAgo n: Int) -> String {
        ymd(Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date())
    }
    static var displayNow: String { displayFormatter.string(from: Date()) }
}
