import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class Database {
    private var db: OpaquePointer?
    // ISO8601DateFormatter is costly to allocate and thread-safe to reuse.
    private static let iso = ISO8601DateFormatter()

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobHunter", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("jobhunter.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("DB open failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        exec("PRAGMA journal_mode=WAL;")   // concurrent read while writing; faster commits
        exec("PRAGMA synchronous=NORMAL;")
        createSchema()
        migrate()
    }

    /// Additive migrations for DBs created before a column/index existed.
    private func migrate() {
        exec("ALTER TABLE jobs ADD COLUMN favorite INTEGER DEFAULT 0")  // no-op (logged) if it exists
        exec("ALTER TABLE jobs ADD COLUMN interview_date TEXT")
        exec("ALTER TABLE jobs ADD COLUMN ai_subscores TEXT")
        exec("CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status)")
        exec("CREATE INDEX IF NOT EXISTS idx_jobs_favorite ON jobs(favorite)")
        exec("CREATE INDEX IF NOT EXISTS idx_jobs_score ON jobs(ai_score, keyword_score)")
        exec("CREATE INDEX IF NOT EXISTS idx_jobs_lastseen ON jobs(last_seen)")
        // Per-scan snapshots power the 'new matches / week' chart and the fit trend arrow.
        exec("""
        CREATE TABLE IF NOT EXISTS scan_history(
            ts TEXT PRIMARY KEY, day TEXT, new_count INTEGER, match_count INTEGER, avg_fit INTEGER
        )
        """)
    }

    deinit { if let db { sqlite3_close(db) } }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err { print("SQL error: \(String(cString: err))"); sqlite3_free(err) }
            return false
        }
        return true
    }

    /// Wrap many writes in a single transaction so a scan does one commit, not N fsyncs.
    /// If BEGIN fails we bail (so the body never runs in autocommit); if COMMIT fails we roll back.
    func transaction(_ body: () -> Void) {
        guard exec("BEGIN") else { return }
        body()
        if !exec("COMMIT") { exec("ROLLBACK") }
    }

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS companies(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL, ats TEXT NOT NULL, token TEXT NOT NULL,
            tier TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
            UNIQUE(ats, token)
        );
        CREATE TABLE IF NOT EXISTS jobs(
            job_id TEXT PRIMARY KEY, company TEXT, tier TEXT, ats TEXT,
            title TEXT, location TEXT, url TEXT, department TEXT,
            description TEXT, posted_at TEXT,
            keyword_score INTEGER DEFAULT 0, ai_score INTEGER,
            ai_verdict TEXT, ai_reasons TEXT, ai_gaps TEXT, constraints TEXT,
            status TEXT DEFAULT 'active', applied_stage TEXT DEFAULT 'none',
            applied_date TEXT, follow_up_date TEXT, notes TEXT DEFAULT '',
            first_seen TEXT, last_seen TEXT, is_new INTEGER DEFAULT 1,
            favorite INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS company_cache(
            ats TEXT NOT NULL, token TEXT NOT NULL,
            etag TEXT, last_modified TEXT, fetched_at TEXT,
            PRIMARY KEY(ats, token)
        );
        CREATE TABLE IF NOT EXISTS resume(
            id INTEGER PRIMARY KEY CHECK(id=1), text TEXT, profile TEXT, updated_at TEXT
        );
        """)
    }

    // MARK: helpers
    private func bind(_ stmt: OpaquePointer?, _ i: Int32, _ s: String?) {
        if let s { sqlite3_bind_text(stmt, i, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, i) }
    }
    private func bind(_ stmt: OpaquePointer?, _ i: Int32, _ n: Int?) {
        if let n { sqlite3_bind_int(stmt, i, Int32(n)) } else { sqlite3_bind_null(stmt, i) }
    }
    private func text(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }
    private func textOpt(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
    private func intOpt(_ stmt: OpaquePointer?, _ i: Int32) -> Int? {
        sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, i))
    }
    private func encode<T: Encodable>(_ v: T) -> String {
        (try? String(data: JSONEncoder().encode(v), encoding: .utf8) ?? "") ?? ""
    }
    private func decodeArr(_ s: String?) -> [String] {
        guard let s, let d = s.data(using: .utf8), let a = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return a
    }
    private func decodeConstraints(_ s: String?) -> JobConstraints {
        guard let s, let d = s.data(using: .utf8), let c = try? JSONDecoder().decode(JobConstraints.self, from: d) else { return .empty }
        return c
    }
    private func decodeIntMap(_ s: String?) -> [String: Int] {
        guard let s, let d = s.data(using: .utf8), let m = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
        return m
    }

    // MARK: companies
    func allCompanies() -> [Company] {
        var out: [Company] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id,name,ats,token,tier,enabled FROM companies ORDER BY name COLLATE NOCASE", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(Company(
                    id: sqlite3_column_int64(stmt, 0),
                    name: text(stmt, 1),
                    ats: ATSKind(rawValue: text(stmt, 2)) ?? .greenhouse,
                    token: text(stmt, 3),
                    tier: Tier(rawValue: text(stmt, 4)) ?? .startup,
                    enabled: sqlite3_column_int(stmt, 5) == 1))
            }
        }
        sqlite3_finalize(stmt)
        return out
    }

    func upsertCompany(name: String, ats: ATSKind, token: String, tier: Tier, enabled: Bool = true) {
        var stmt: OpaquePointer?
        let sql = "INSERT INTO companies(name,ats,token,tier,enabled) VALUES(?,?,?,?,?) ON CONFLICT(ats,token) DO UPDATE SET name=excluded.name,tier=excluded.tier,enabled=excluded.enabled"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, name); bind(stmt, 2, ats.rawValue); bind(stmt, 3, token)
            bind(stmt, 4, tier.rawValue); sqlite3_bind_int(stmt, 5, enabled ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func setCompanyEnabled(_ id: Int64, _ enabled: Bool) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE companies SET enabled=? WHERE id=?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, enabled ? 1 : 0); sqlite3_bind_int64(stmt, 2, id); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func updateCompany(id: Int64, name: String, ats: ATSKind, token: String, tier: Tier) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE companies SET name=?,ats=?,token=?,tier=? WHERE id=?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, name); bind(stmt, 2, ats.rawValue); bind(stmt, 3, token)
            bind(stmt, 4, tier.rawValue); sqlite3_bind_int64(stmt, 5, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func deleteCompany(_ id: Int64) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM companies WHERE id=?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, id); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func companyCount() -> Int {
        var stmt: OpaquePointer?; var n = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM companies", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW { n = Int(sqlite3_column_int(stmt, 0)) }
        sqlite3_finalize(stmt); return n
    }

    // MARK: jobs
    /// Insert or update scan-derived fields, preserving user status/notes and AI results' first_seen.
    func upsertScannedJob(_ j: Job, runDate: String) {
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO jobs(job_id,company,tier,ats,title,location,url,department,description,posted_at,
            keyword_score,constraints,status,applied_stage,notes,first_seen,last_seen,is_new)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,'active','none','',?,?,1)
        ON CONFLICT(job_id) DO UPDATE SET
            title=excluded.title, location=excluded.location, url=excluded.url,
            department=excluded.department, description=excluded.description,
            posted_at=excluded.posted_at, keyword_score=excluded.keyword_score,
            constraints=excluded.constraints, last_seen=excluded.last_seen, is_new=0
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, j.id); bind(stmt, 2, j.company); bind(stmt, 3, j.tier?.rawValue)
            bind(stmt, 4, j.ats.rawValue); bind(stmt, 5, j.title); bind(stmt, 6, j.location)
            bind(stmt, 7, j.url); bind(stmt, 8, j.department); bind(stmt, 9, j.descriptionText)
            bind(stmt, 10, j.postedAt); sqlite3_bind_int(stmt, 11, Int32(j.keywordScore))
            bind(stmt, 12, encode(j.constraints)); bind(stmt, 13, runDate); bind(stmt, 14, runDate)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// Insert a fully-specified job (e.g. a manually tracked application from a company portal).
    /// Upserts on job_id so re-adding the same row updates the user-visible fields.
    func insertJob(_ j: Job) {
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO jobs(job_id,company,tier,ats,title,location,url,department,description,posted_at,
            keyword_score,status,applied_stage,applied_date,notes,first_seen,last_seen,is_new,favorite)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?)
        ON CONFLICT(job_id) DO UPDATE SET
            company=excluded.company, title=excluded.title, location=excluded.location,
            url=excluded.url, status=excluded.status, applied_stage=excluded.applied_stage,
            applied_date=excluded.applied_date, notes=excluded.notes, last_seen=excluded.last_seen
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, j.id); bind(stmt, 2, j.company); bind(stmt, 3, j.tier?.rawValue)
            bind(stmt, 4, j.ats.rawValue); bind(stmt, 5, j.title); bind(stmt, 6, j.location)
            bind(stmt, 7, j.url); bind(stmt, 8, j.department); bind(stmt, 9, j.descriptionText)
            bind(stmt, 10, j.postedAt); sqlite3_bind_int(stmt, 11, Int32(j.keywordScore))
            bind(stmt, 12, j.status.rawValue); bind(stmt, 13, j.appliedStage.rawValue)
            bind(stmt, 14, j.appliedDate); bind(stmt, 15, j.notes)
            bind(stmt, 16, j.firstSeen); bind(stmt, 17, j.lastSeen)
            sqlite3_bind_int(stmt, 18, j.favorite ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func setAI(_ jobID: String, _ eval: AIEvaluation) {
        var stmt: OpaquePointer?
        let sql = "UPDATE jobs SET ai_score=?, ai_verdict=?, ai_reasons=?, ai_gaps=?, ai_subscores=?, constraints=COALESCE(?,constraints) WHERE job_id=?"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(eval.score))
            bind(stmt, 2, eval.verdict); bind(stmt, 3, encode(eval.reasons)); bind(stmt, 4, encode(eval.gaps))
            bind(stmt, 5, eval.subscores.map { encode($0) })
            bind(stmt, 6, eval.constraints.map { encode($0) }); bind(stmt, 7, jobID)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func setInterviewDate(_ jobID: String, _ date: String?) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE jobs SET interview_date=? WHERE job_id=?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, date); bind(stmt, 2, jobID); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func setStatus(_ jobID: String, _ status: JobStatus) {
        run("UPDATE jobs SET status=? WHERE job_id=?", status.rawValue, jobID)
    }
    func setAppliedStage(_ jobID: String, _ stage: AppliedStage, date: String?) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE jobs SET applied_stage=?, applied_date=?, status=? WHERE job_id=?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, stage.rawValue); bind(stmt, 2, date)
            bind(stmt, 3, stage == .none ? JobStatus.active.rawValue : JobStatus.applied.rawValue)
            bind(stmt, 4, jobID); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    func setNotes(_ jobID: String, _ notes: String) { run("UPDATE jobs SET notes=? WHERE job_id=?", notes, jobID) }
    func setFavorite(_ jobID: String, _ on: Bool) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE jobs SET favorite=? WHERE job_id=?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, on ? 1 : 0); bind(stmt, 2, jobID); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// Delete stale active postings no longer worth keeping. Never touches applied/ignored/favorite.
    @discardableResult
    func purgeStale(cutoff: String) -> Int {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM jobs WHERE status='active' AND favorite=0 AND last_seen < ?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, cutoff); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return Int(sqlite3_changes(db))
    }

    /// Keep only the highest-scoring `max` active, non-favorite postings; delete the rest.
    /// Applied / ignored / favorite are always retained.
    @discardableResult
    func capActive(max: Int) -> Int {
        var stmt: OpaquePointer?
        let sql = """
        DELETE FROM jobs WHERE status='active' AND favorite=0 AND job_id NOT IN (
            SELECT job_id FROM jobs WHERE status='active' AND favorite=0
            ORDER BY COALESCE(ai_score, keyword_score) DESC LIMIT ?)
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(max)); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return Int(sqlite3_changes(db))
    }
    func setFollowUp(_ jobID: String, _ date: String?) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE jobs SET follow_up_date=? WHERE job_id=?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, date); bind(stmt, 2, jobID); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func run(_ sql: String, _ a: String, _ b: String) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, a); bind(stmt, 2, b); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func allJobs() -> [Job] {
        var out: [Job] = []
        var stmt: OpaquePointer?
        let sql = "SELECT job_id,company,tier,ats,title,location,url,department,description,posted_at,keyword_score,ai_score,ai_verdict,ai_reasons,ai_gaps,constraints,status,applied_stage,applied_date,follow_up_date,notes,first_seen,last_seen,is_new,favorite,interview_date,ai_subscores FROM jobs"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(Job(
                    id: text(stmt, 0), company: text(stmt, 1),
                    tier: Tier(rawValue: text(stmt, 2)), ats: ATSKind(rawValue: text(stmt, 3)) ?? .greenhouse,
                    title: text(stmt, 4), location: text(stmt, 5), url: text(stmt, 6),
                    department: text(stmt, 7), descriptionText: text(stmt, 8), postedAt: text(stmt, 9),
                    keywordScore: Int(sqlite3_column_int(stmt, 10)), aiScore: intOpt(stmt, 11),
                    aiVerdict: textOpt(stmt, 12), aiReasons: decodeArr(textOpt(stmt, 13)),
                    aiGaps: decodeArr(textOpt(stmt, 14)), aiSubscores: decodeIntMap(textOpt(stmt, 26)),
                    constraints: decodeConstraints(textOpt(stmt, 15)),
                    status: JobStatus(rawValue: text(stmt, 16)) ?? .active,
                    appliedStage: AppliedStage(rawValue: text(stmt, 17)) ?? .none,
                    appliedDate: textOpt(stmt, 18), followUpDate: textOpt(stmt, 19),
                    interviewDate: textOpt(stmt, 25),
                    notes: text(stmt, 20), firstSeen: text(stmt, 21), lastSeen: text(stmt, 22),
                    isNew: sqlite3_column_int(stmt, 23) == 1,
                    favorite: sqlite3_column_int(stmt, 24) == 1))
            }
        }
        sqlite3_finalize(stmt)
        return out
    }

    // MARK: scan history (snapshots for the weekly chart + fit trend)
    func recordScan(newCount: Int, matchCount: Int, avgFit: Int) {
        var stmt: OpaquePointer?
        let sql = "INSERT INTO scan_history(ts,day,new_count,match_count,avg_fit) VALUES(?,?,?,?,?)"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, Self.iso.string(from: Date()))
            bind(stmt, 2, AppStore.today)
            sqlite3_bind_int(stmt, 3, Int32(newCount)); sqlite3_bind_int(stmt, 4, Int32(matchCount))
            sqlite3_bind_int(stmt, 5, Int32(avgFit)); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    /// Newest-first scan snapshots (most recent `limit`).
    func scanHistory(limit: Int = 30) -> [(day: String, new: Int, matches: Int, avgFit: Int)] {
        var out: [(String, Int, Int, Int)] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT day,new_count,match_count,avg_fit FROM scan_history ORDER BY ts DESC LIMIT ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((text(stmt, 0), Int(sqlite3_column_int(stmt, 1)),
                            Int(sqlite3_column_int(stmt, 2)), Int(sqlite3_column_int(stmt, 3))))
            }
        }
        sqlite3_finalize(stmt); return out
    }

    // MARK: meta & resume
    func meta(_ key: String) -> String? {
        var stmt: OpaquePointer?; var v: String?
        if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key=?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, key)
            if sqlite3_step(stmt) == SQLITE_ROW { v = textOpt(stmt, 0) }
        }
        sqlite3_finalize(stmt); return v
    }
    func setMeta(_ key: String, _ value: String) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, key); bind(stmt, 2, value); sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func saveResume(text t: String, profile: ExtractedProfile) {
        var stmt: OpaquePointer?
        let p = (try? String(data: JSONEncoder().encode(profile), encoding: .utf8) ?? "") ?? ""
        if sqlite3_prepare_v2(db, "INSERT INTO resume(id,text,profile,updated_at) VALUES(1,?,?,?) ON CONFLICT(id) DO UPDATE SET text=excluded.text,profile=excluded.profile,updated_at=excluded.updated_at", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, t); bind(stmt, 2, p); bind(stmt, 3, Self.iso.string(from: Date()))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    func loadResume() -> (text: String, profile: ExtractedProfile)? {
        var stmt: OpaquePointer?; var result: (String, ExtractedProfile)?
        if sqlite3_prepare_v2(db, "SELECT text,profile FROM resume WHERE id=1", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            let t = text(stmt, 0)
            let pj = textOpt(stmt, 1)
            var prof = ExtractedProfile.empty
            if let pj, let d = pj.data(using: .utf8), let p = try? JSONDecoder().decode(ExtractedProfile.self, from: d) { prof = p }
            result = (t, prof)
        }
        sqlite3_finalize(stmt); return result
    }
    // MARK: HTTP conditional cache (avoid re-downloading unchanged boards)
    func cacheValidators(ats: ATSKind, token: String) -> (etag: String?, lastModified: String?) {
        var stmt: OpaquePointer?
        var out: (String?, String?) = (nil, nil)
        if sqlite3_prepare_v2(db, "SELECT etag,last_modified FROM company_cache WHERE ats=? AND token=?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, ats.rawValue); bind(stmt, 2, token)
            if sqlite3_step(stmt) == SQLITE_ROW { out = (textOpt(stmt, 0), textOpt(stmt, 1)) }
        }
        sqlite3_finalize(stmt); return out
    }
    func setCache(ats: ATSKind, token: String, etag: String?, lastModified: String?) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO company_cache(ats,token,etag,last_modified,fetched_at) VALUES(?,?,?,?,?) ON CONFLICT(ats,token) DO UPDATE SET etag=excluded.etag,last_modified=excluded.last_modified,fetched_at=excluded.fetched_at", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, ats.rawValue); bind(stmt, 2, token); bind(stmt, 3, etag); bind(stmt, 4, lastModified)
            bind(stmt, 5, Self.iso.string(from: Date()))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
}

