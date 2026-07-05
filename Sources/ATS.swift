import Foundation

enum ATS {
    static let timeout: TimeInterval = 25

    struct FetchResult: Sendable {
        var jobs: [Job] = []
        var etag: String? = nil
        var lastModified: String? = nil
        var notModified: Bool = false
        var error: String? = nil
    }
    struct ATSError: Error { let message: String }

    /// Conditional fetch: sends ETag/If-Modified-Since so unchanged boards return 304 (no re-download).
    /// `known` = job IDs already stored for this board; SmartRecruiters uses it to only detail-fetch
    /// descriptions for NEW postings (unchanged jobs are never re-downloaded).
    static func fetch(_ c: Company, etag: String? = nil, lastModified: String? = nil, known: Set<String> = []) async -> FetchResult {
        // SmartRecruiters needs offset pagination + a per-posting call for descriptions,
        // so it can't ride the single-request conditional-GET path the others use.
        if c.ats == .smartrecruiters { return await fetchSmart(c, known: known) }
        do {
            let cond = try await conditionalGet(endpoint(for: c), etag: etag, lastModified: lastModified)
            if cond.notModified { return FetchResult(etag: etag, lastModified: lastModified, notModified: true) }
            guard let json = cond.json else { return FetchResult(error: "empty response") }
            return FetchResult(jobs: parse(c, json: json),
                               etag: cond.etag ?? etag, lastModified: cond.lastModified ?? lastModified)
        } catch let e as ATSError {
            return FetchResult(error: e.message)
        } catch {
            return FetchResult(error: error.localizedDescription)
        }
    }

    // MARK: SmartRecruiters (paginated list + description backfill for new postings)

    private static func fetchSmart(_ c: Company, known: Set<String>) async -> FetchResult {
        var all: [Job] = []
        do {
            var offset = 0
            let limit = 100
            while true {
                let url = "https://api.smartrecruiters.com/v1/companies/\(c.token)/postings?limit=\(limit)&offset=\(offset)"
                guard let json = try await getJSON(url) else { break }
                let page = parseSmart(c, json)
                all += page
                let total = (json as? [String: Any])?["totalFound"] as? Int ?? all.count
                offset += limit
                // ponytail: cap at 1000 postings/board; raise if a board legitimately exceeds it.
                if page.count < limit || offset >= total || offset >= 1000 { break }
            }
        } catch let e as ATSError { return FetchResult(error: e.message) }
        catch { return FetchResult(error: error.localizedDescription) }

        // Backfill descriptions only for NEW postings, bounded, so scans stay cheap.
        let fresh = all.filter { !known.contains($0.id) }.prefix(60)   // ponytail: cap detail calls/scan
        if !fresh.isEmpty {
            var byID: [String: String] = [:]
            await withTaskGroup(of: (String, String).self) { group in
                for j in fresh {
                    let token = c.token
                    let pid = String(j.id.split(separator: ":").last ?? "")
                    group.addTask { (j.id, await smartDescription(token: token, postingId: pid)) }
                }
                for await (id, d) in group where !d.isEmpty { byID[id] = d }
            }
            for i in all.indices where byID[all[i].id] != nil {
                all[i].descriptionText = String(byID[all[i].id]!.prefix(6000))
            }
        }
        return FetchResult(jobs: all)
    }

    private static func smartDescription(token: String, postingId: String) async -> String {
        guard !postingId.isEmpty,
              let json = try? await getJSON("https://api.smartrecruiters.com/v1/companies/\(token)/postings/\(postingId)"),
              let dict = json as? [String: Any],
              let sections = (dict["jobAd"] as? [String: Any])?["sections"] as? [String: Any] else { return "" }
        // Concatenate the standard SmartRecruiters ad sections.
        let text = ["companyDescription", "jobDescription", "qualifications", "additionalInformation"]
            .compactMap { (sections[$0] as? [String: Any])?["text"] as? String }
            .joined(separator: "\n")
        return clean(text)
    }

    /// Plain GET returning parsed JSON (no conditional headers). Used by paginated boards.
    private static func getJSON(_ urlString: String) async throws -> Any? {
        guard let url = URL(string: urlString) else { throw ATSError(message: "bad url") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("JobHunter/2.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ATSError(message: "no response") }
        if http.statusCode >= 400 { throw ATSError(message: "HTTP \(http.statusCode)") }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: stable IDs (so unchanged postings aren't re-inserted as "new" every scan)

    /// A real ATS id if present, else a deterministic hash of the URL/title. Returns "" when there
    /// is no stable basis (no id, url, or title) - callers skip such postings rather than mint a
    /// random UUID that would re-insert as "new" on every scan.
    static func stableID(_ raw: Any?, url: String, title: String) -> String {
        if let s = idString(raw) { return s }
        let basis = !url.isEmpty ? url : title
        return basis.isEmpty ? "" : "h" + stableHash(basis)
    }
    private static func idString(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.isEmpty ? nil : s
        case let n as Int: return String(n)
        case let n as Int64: return String(n)
        case let d as Double: return String(Int64(d))
        default: return nil
        }
    }
    /// FNV-1a over UTF-8, stable across process launches (Swift's hashValue is NOT).
    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }

    private static func endpoint(for c: Company) -> String {
        switch c.ats {
        case .greenhouse: return "https://boards-api.greenhouse.io/v1/boards/\(c.token)/jobs?content=true"
        case .ashby: return "https://api.ashbyhq.com/posting-api/job-board/\(c.token)?includeCompensation=true"
        case .lever: return "https://api.lever.co/v0/postings/\(c.token)?mode=json"
        case .smartrecruiters: return "https://api.smartrecruiters.com/v1/companies/\(c.token)/postings?limit=100"
        case .manual: return ""   // not a fetchable board
        }
    }

    private struct CondResult { var json: Any?; var etag: String?; var lastModified: String?; var notModified: Bool }

    private static func conditionalGet(_ urlString: String, etag: String?, lastModified: String?) async throws -> CondResult {
        guard let url = URL(string: urlString) else { throw ATSError(message: "bad url") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("JobHunter/2.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { req.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ATSError(message: "no response") }
        if http.statusCode == 304 { return CondResult(json: nil, etag: etag, lastModified: lastModified, notModified: true) }
        if http.statusCode >= 400 { throw ATSError(message: "HTTP \(http.statusCode)") }
        let json = try JSONSerialization.jsonObject(with: data)
        return CondResult(json: json,
                          etag: http.value(forHTTPHeaderField: "ETag"),
                          lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                          notModified: false)
    }

    private static func parse(_ c: Company, json: Any) -> [Job] {
        switch c.ats {
        case .greenhouse: return parseGreenhouse(c, json)
        case .ashby: return parseAshby(c, json)
        case .lever: return parseLever(c, json)
        case .smartrecruiters: return parseSmart(c, json)
        case .manual: return []   // manual jobs are never fetched/parsed
        }
    }

    private static func make(_ c: Company, id: String, title: String, location: String,
                             url: String, dept: String, desc: String, posted: String) -> Job {
        Job(id: "\(c.name)::\(id)", company: c.name, tier: c.tier, ats: c.ats,
            title: title, location: location, url: url, department: dept,
            descriptionText: String(desc.prefix(6000)), postedAt: posted,
            keywordScore: 0, aiScore: nil, aiVerdict: nil, aiReasons: [], aiGaps: [],
            constraints: .empty, status: .active, appliedStage: .none, appliedDate: nil,
            followUpDate: nil, notes: "", firstSeen: "", lastSeen: "", isNew: false)
    }

    private static func parseGreenhouse(_ c: Company, _ root: Any) -> [Job] {
        guard let dict = root as? [String: Any], let arr = dict["jobs"] as? [[String: Any]] else { return [] }
        return arr.compactMap { j -> Job? in
            let loc = (j["location"] as? [String: Any])?["name"] as? String ?? ""
            let depts = (j["departments"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            let url = j["absolute_url"] as? String ?? "", title = j["title"] as? String ?? ""
            let id = stableID(j["id"], url: url, title: title)
            guard !id.isEmpty else { return nil }
            return make(c, id: id, title: title, location: loc, url: url, dept: depts,
                        desc: clean(j["content"] as? String ?? ""), posted: j["updated_at"] as? String ?? "")
        }
    }
    private static func parseAshby(_ c: Company, _ root: Any) -> [Job] {
        guard let dict = root as? [String: Any], let arr = dict["jobs"] as? [[String: Any]] else { return [] }
        return arr.compactMap { j in
            if let listed = j["isListed"] as? Bool, listed == false { return nil }
            var loc = (j["location"] as? String) ?? (j["locationName"] as? String) ?? ""
            if (j["isRemote"] as? Bool) == true { loc = (loc + " (Remote)").trimmingCharacters(in: .whitespaces) }
            let dept = (j["department"] as? String) ?? (j["team"] as? String) ?? ""
            let desc = (j["descriptionPlain"] as? String) ?? clean(j["descriptionHtml"] as? String ?? "")
            let link = (j["jobUrl"] as? String) ?? (j["applyUrl"] as? String) ?? ""
            let title = j["title"] as? String ?? ""
            let id = stableID(j["id"], url: link, title: title)
            guard !id.isEmpty else { return nil }
            return make(c, id: id, title: title, location: loc, url: link, dept: dept,
                        desc: desc, posted: (j["publishedDate"] as? String) ?? (j["publishedAt"] as? String) ?? "")
        }
    }
    private static func parseLever(_ c: Company, _ root: Any) -> [Job] {
        guard let arr = root as? [[String: Any]] else { return [] }
        return arr.compactMap { j -> Job? in
            let cats = j["categories"] as? [String: Any] ?? [:]
            let dept = (cats["department"] as? String) ?? (cats["team"] as? String) ?? ""
            let desc = (j["descriptionPlain"] as? String) ?? clean(j["description"] as? String ?? "")
            let url = j["hostedUrl"] as? String ?? "", title = j["text"] as? String ?? ""
            let id = stableID(j["id"], url: url, title: title)
            guard !id.isEmpty else { return nil }
            return make(c, id: id, title: title, location: cats["location"] as? String ?? "",
                        url: url, dept: dept, desc: desc,
                        posted: String(describing: j["createdAt"] ?? ""))
        }
    }
    private static func parseSmart(_ c: Company, _ root: Any) -> [Job] {
        guard let dict = root as? [String: Any], let arr = dict["content"] as? [[String: Any]] else { return [] }
        return arr.map { j in
            let loc = j["location"] as? [String: Any] ?? [:]
            var locStr = [loc["city"] as? String, loc["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            if (loc["remote"] as? Bool) == true { locStr += " (Remote)" }
            // SmartRecruiters always carries a real posting id; needed for the URL + detail fetch.
            let id = idString(j["id"]) ?? stableHash(j["name"] as? String ?? "")
            let dept = (j["department"] as? [String: Any])?["label"] as? String ?? ""
            return make(c, id: id, title: j["name"] as? String ?? "", location: locStr,
                        url: "https://jobs.smartrecruiters.com/\(c.token)/\(id)", dept: dept,
                        desc: "", posted: j["releasedDate"] as? String ?? "")
        }
    }

    static func clean(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var s = raw
        // Preserve structure before stripping tags: list items -> bullet lines, block ends -> newlines.
        s = s.replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n• ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</(p|div|h[1-6]|ul|ol|li|tr|section|header)>", with: "\n", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                        "&#39;": "'", "&#x27;": "'", "&nbsp;": " ", "&rsquo;": "'", "&ldquo;": "\"", "&rdquo;": "\""]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)   // strip remaining tags
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)    // collapse spaces, keep newlines
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)    // trim around newlines
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)  // cap blank runs
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
