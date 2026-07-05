import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude, gpt, gemini, local
    var id: String { rawValue }
    var label: String {
        switch self {
        case .claude: return "Claude"
        case .gpt: return "GPT"
        case .gemini: return "Gemini"
        case .local: return "Local"
        }
    }
    var keychainAccount: String { "apikey.\(rawValue)" }
    var needsKey: Bool { self != .local }
    var models: [String] {
        switch self {
        case .claude: return ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
        case .gpt: return ["gpt-5", "gpt-5-mini", "gpt-4.1"]
        case .gemini: return ["gemini-2.5-pro", "gemini-2.5-flash"]
        case .local: return ["llama3.1", "qwen2.5", "mistral"]
        }
    }
    var defaultModel: String { models.first ?? "" }
    var defaultBaseURL: String { self == .local ? "http://localhost:11434" : "" }
}

struct AIConfig {
    var provider: AIProvider
    var model: String
    var apiKey: String
    var baseURL: String
}

struct AIError: LocalizedError { let msg: String; var errorDescription: String? { msg } }

enum AIService {
    // MARK: public API

    static func testConnection(_ cfg: AIConfig) async -> Result<String, Error> {
        do {
            let reply = try await complete(cfg, system: "You are a connection test.",
                                           user: "Reply with the single word: OK", maxTokens: 16)
            return .success(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return .failure(error) }
    }

    static func analyzeResume(_ text: String, cfg: AIConfig) async throws -> ExtractedProfile {
        let system = """
        You analyze a resume and extract a structured job-search profile. \
        Respond with ONLY minified JSON, no prose, no code fences, matching:
        {"summary":string,"level":string,"targetTitles":[string],"skills":[string],"idealRoles":string,"country":string}
        - level: the seniority band this person should target (e.g. "VP / Senior Director").
        - targetTitles: 4-8 concrete titles to search for.
        - skills: 6-12 core skills, each a SHORT atomic keyword or tech (e.g. "Kubernetes", "AWS", "SRE", "Terraform"), NOT long descriptive phrases.
        - idealRoles: one sentence describing the ideal role.
        - country: the candidate's country in full (e.g. "United States", "United Kingdom", "India"); infer from address, phone, or work history. Use "" only if truly indeterminable.
        """
        let user = "RESUME:\n" + String(text.prefix(12000))
        let raw = try await complete(cfg, system: system, user: user, maxTokens: 900)
        guard let data = extractJSON(raw)?.data(using: .utf8),
              let p = try? JSONDecoder().decode(ExtractedProfile.self, from: data) else {
            throw AIError(msg: "Could not parse the model's resume analysis.")
        }
        return p
    }

    static func evaluate(job: Job, profile: ExtractedProfile, resume: String,
                         feedback: [String] = [], cfg: AIConfig) async throws -> AIEvaluation {
        let system = """
        You evaluate how well a job fits a candidate. Respond with ONLY minified JSON, no prose, matching:
        {"score":int(0-100),"verdict":string,"reasons":[string],"gaps":[string],\
        "subscores":{"leadership":int(0-100),"location":int(0-100),"technical":int(0-100),"domain":int(0-100),"compensation":int(0-100)},\
        "constraints":{"salaryMin":int|null,"salaryMax":int|null,\
        "workAuth":"sponsorOffered|noSponsorship|citizensOnly|clearanceRequired|notStated",\
        "remotePolicy":string,"yoeMin":int|null,"managerScope":"manager|ic|","clearance":bool,"travel":string|null}}
        - score: overall fit for THIS candidate (seniority, domain, skills).
        - subscores: 0-100 for each signal - leadership scope, location/remote match, technical depth, domain overlap, compensation alignment - relative to the candidate.
        - verdict: one sentence.
        - reasons: 3-5 specific reasons it fits, grounded in the resume.
        - gaps: 1-3 honest gaps or conflicts.
        - constraints: extract from the job text; salary in thousands USD; use "notStated" when unknown, never guess work authorization.
        - The candidate has flagged WRONG MATCHES (see list if present): roles fundamentally mismatched to their background - wrong function, domain, seniority, or location, i.e. the opposite of their resume. If THIS job resembles any of them (same off-profile function/domain/industry/location), score it very LOW and name the mismatch in gaps.
        """
        let candidate = profile.summary.isEmpty ? String(resume.prefix(4000))
            : "LEVEL: \(profile.level)\nTARGET: \(profile.targetTitles.joined(separator: ", "))\nSKILLS: \(profile.skills.joined(separator: ", "))\nSUMMARY: \(profile.summary)"
        // Only the most recent feedback is injected, to bound token cost. Lives in the USER prompt so
        // the (cacheable) system prompt stays identical across every job in a scan.
        let fb = feedback.isEmpty ? "" :
            "\n\nWRONG MATCHES the candidate flagged (opposite of their profile - do not score similar roles high):\n"
            + feedback.suffix(15).map { "- \($0)" }.joined(separator: "\n")
        let user = """
        CANDIDATE:
        \(candidate)\(fb)

        JOB:
        Title: \(job.title)
        Company: \(job.company)
        Location: \(job.location)
        Description: \(String(job.descriptionText.prefix(6000)))
        """
        let raw = try await complete(cfg, system: system, user: user, maxTokens: 700)
        guard let data = extractJSON(raw)?.data(using: .utf8),
              let e = try? JSONDecoder().decode(AIEvaluation.self, from: data) else {
            throw AIError(msg: "Could not parse evaluation for \(job.title).")
        }
        return e
    }

    // MARK: provider dispatch

    static func complete(_ cfg: AIConfig, system: String, user: String, maxTokens: Int) async throws -> String {
        switch cfg.provider {
        case .claude: return try await anthropic(cfg, system: system, user: user, maxTokens: maxTokens)
        case .gpt: return try await openAICompatible(cfg, base: "https://api.openai.com", system: system, user: user, maxTokens: maxTokens)
        case .gemini: return try await gemini(cfg, system: system, user: user, maxTokens: maxTokens)
        case .local:
            let base = cfg.baseURL.isEmpty ? "http://localhost:11434" : cfg.baseURL
            return try await openAICompatible(cfg, base: base, system: system, user: user, maxTokens: maxTokens)
        }
    }

    private static func post(_ url: String, headers: [String: String], body: [String: Any]) async throws -> Any {
        guard let u = URL(string: url) else { throw AIError(msg: "Bad URL") }
        let payload = try JSONSerialization.data(withJSONObject: body)
        // One bounded retry on rate-limit / transient server errors, so a single 429 doesn't
        // silently drop a job's evaluation.
        for attempt in 0...1 {
            var req = URLRequest(url: u, timeoutInterval: 90)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = payload
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                let retryable = http.statusCode == 429 || http.statusCode >= 500
                if retryable && attempt == 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw AIError(msg: "HTTP \(http.statusCode): \(String(msg.prefix(200)))")
            }
            return try JSONSerialization.jsonObject(with: data)
        }
        throw AIError(msg: "Request failed after retry")
    }

    private static func anthropic(_ cfg: AIConfig, system: String, user: String, maxTokens: Int) async throws -> String {
        // Mark the system prompt cacheable: it's identical across every job in a scan, so Anthropic
        // reuses it instead of re-billing input tokens (kicks in once the prompt clears the model's
        // cache threshold; harmless below it).
        let systemBlocks: [[String: Any]] = [["type": "text", "text": system,
                                              "cache_control": ["type": "ephemeral"]]]
        let json = try await post("https://api.anthropic.com/v1/messages",
            headers: ["x-api-key": cfg.apiKey, "anthropic-version": "2023-06-01"],
            body: ["model": cfg.model, "max_tokens": maxTokens, "system": systemBlocks,
                   "messages": [["role": "user", "content": user]]])
        guard let d = json as? [String: Any], let content = d["content"] as? [[String: Any]],
              let first = content.first(where: { $0["type"] as? String == "text" }) ?? content.first,
              let txt = first["text"] as? String else { throw AIError(msg: "Unexpected Claude response") }
        return txt
    }

    private static func openAICompatible(_ cfg: AIConfig, base: String, system: String, user: String, maxTokens: Int) async throws -> String {
        var headers = ["Content-Type": "application/json"]
        if !cfg.apiKey.isEmpty { headers["Authorization"] = "Bearer \(cfg.apiKey)" }
        let json = try await post("\(base)/v1/chat/completions", headers: headers,
            body: ["model": cfg.model, "max_tokens": maxTokens,
                   "messages": [["role": "system", "content": system], ["role": "user", "content": user]]])
        guard let d = json as? [String: Any], let choices = d["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any], let txt = msg["content"] as? String
        else { throw AIError(msg: "Unexpected response from provider") }
        return txt
    }

    private static func gemini(_ cfg: AIConfig, system: String, user: String, maxTokens: Int) async throws -> String {
        // Key goes in a header, not the URL query string, so it can't leak into logs/traces.
        let url = "https://generativelanguage.googleapis.com/v1beta/models/\(cfg.model):generateContent"
        let json = try await post(url, headers: ["x-goog-api-key": cfg.apiKey],
            body: ["system_instruction": ["parts": [["text": system]]],
                   "contents": [["parts": [["text": user]]]],
                   "generationConfig": ["maxOutputTokens": maxTokens]])
        guard let d = json as? [String: Any], let cands = d["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]], let txt = parts.first?["text"] as? String
        else { throw AIError(msg: "Unexpected Gemini response") }
        return txt
    }

    // MARK: JSON extraction
    static func extractJSON(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else { return nil }
        return String(s[start...end])
    }
}
