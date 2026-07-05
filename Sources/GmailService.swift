import Foundation

/// Reads Gmail over IMAPS via the system `curl` (app is non-sandboxed) using an
/// App Password. No OAuth / Google Cloud project required. Read-only.
enum GmailService {
    struct Msg: Sendable {
        var uid: String
        var from: String
        var subject: String
        var date: Date?
    }

    enum Detected: String, Sendable { case received, interviewing, offer, rejected }

    struct AuthError: LocalizedError {
        let code: Int32
        var errorDescription: String? {
            switch code {
            case 67: return "Login failed. Use a Gmail App Password (needs 2-Step Verification), and make sure IMAP is enabled in Gmail settings."
            case 6, 7: return "Couldn't reach imap.gmail.com. Check your connection."
            case 28: return "Timed out contacting Gmail."
            default: return "Gmail connection error (curl \(code))."
            }
        }
    }

    private static let host = "imaps://imap.gmail.com:993/INBOX"

    // MARK: curl runner
    private static func runCurl(_ email: String, _ pass: String, request: String, timeout: Int = 40) -> (out: String, code: Int32) {
        // Credentials go in a 0600 netrc temp file, never on argv (argv is visible to any
        // local process via `ps`/Activity Monitor for the life of the call).
        let netrc = FileManager.default.temporaryDirectory
            .appendingPathComponent("jh-\(UUID().uuidString).netrc")
        let body = "machine imap.gmail.com login \(email) password \(pass)\n"
        guard FileManager.default.createFile(atPath: netrc.path,
                contents: Data(body.utf8), attributes: [.posixPermissions: 0o600]) else { return ("", 1) }
        defer { try? FileManager.default.removeItem(at: netrc) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--max-time", String(timeout), "--url", host,
                          "--netrc-file", netrc.path, "-X", request]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return ("", 1) }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", task.terminationStatus)
    }

    // MARK: public API
    static func testConnection(email: String, appPassword: String) -> Result<Int, Error> {
        let r = runCurl(email, appPassword, request: "EXAMINE INBOX", timeout: 25)
        if r.code != 0 { return .failure(AuthError(code: r.code)) }
        let n = firstInt(in: r.out, pattern: #"\*\s+(\d+)\s+EXISTS"#) ?? 0
        return .success(n)
    }

    /// Fetch recent job-related message headers (last `days` days).
    static func fetchRecent(email: String, appPassword: String, days: Int) -> Result<[Msg], Error> {
        let query = "newer_than:\(days)d (\"your application\" OR \"application to\" OR \"application for\" OR \"application was\" OR \"thank you for applying\" OR \"received your application\" OR interview OR \"phone screen\" OR \"next step\" OR \"next steps\" OR \"moving forward\" OR \"not moving forward\" OR unfortunately OR \"regret to inform\" OR \"not be moving\" OR \"other candidates\" OR offer OR \"we received\")"
        let search = runCurl(email, appPassword, request: "UID SEARCH X-GM-RAW \"\(query)\"", timeout: 40)
        if search.code != 0 { return .failure(AuthError(code: search.code)) }
        var uids = uidList(from: search.out)
        if uids.isEmpty { return .success([]) }
        if uids.count > 80 { uids = Array(uids.suffix(80)) } // most recent
        let set = uids.joined(separator: ",")
        let fetch = runCurl(email, appPassword,
            request: "UID FETCH \(set) (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])", timeout: 60)
        if fetch.code != 0 { return .failure(AuthError(code: fetch.code)) }
        return .success(parseMessages(fetch.out))
    }

    // MARK: classification
    static func classify(subject: String, from: String) -> Detected? {
        let s = (subject + " " + from).lowercased()
        let rejected = ["unfortunately", "not moving forward", "will not be moving", "not be moving forward",
                        "decided not to", "not to move forward", "no longer under consideration",
                        "other candidates", "regret to inform", "not selected", "unable to offer",
                        "won't be moving", "not proceeding", "pursue other", "wish you the best",
                        "position has been filled", "not advance"]
        let offer = ["offer letter", "we are excited to offer", "pleased to offer", "your offer",
                     "extend an offer", "offer of employment"]
        let interview = ["interview", "phone screen", "schedule a", "schedule some time", "next steps",
                         "next step", "availability", "hiring manager", "recruiter screen", "coding challenge",
                         "take-home", "assessment", "would like to speak", "set up a call", "meet with", "chat with"]
        let received = ["received your application", "thank you for applying", "application was received",
                        "we received your", "we've received", "application has been received", "successfully applied"]
        if rejected.contains(where: s.contains) { return .rejected }
        if offer.contains(where: s.contains) { return .offer }
        if interview.contains(where: s.contains) { return .interviewing }
        if received.contains(where: s.contains) { return .received }
        return nil
    }

    // MARK: parsing helpers
    private static func firstInt(in text: String, pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    private static func uidList(from text: String) -> [String] {
        // untagged: * SEARCH 12 34 56
        guard let re = try? NSRegularExpression(pattern: #"\*\s+SEARCH([\d\s]*)"#) else { return [] }
        var out: [String] = []
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 1), in: text) {
                out += text[r].split(whereSeparator: { $0 == " " || $0 == "\r" || $0 == "\n" }).map(String.init)
            }
        }
        return out.filter { Int($0) != nil }
    }

    private static func parseMessages(_ raw: String) -> [Msg] {
        // Split on untagged FETCH markers, keep UID + header block for each.
        var msgs: [Msg] = []
        let blocks = raw.components(separatedBy: "* ")
        for b in blocks {
            guard b.contains("FETCH") else { continue }
            let uid = firstInt(in: b, pattern: #"UID\s+(\d+)"#).map(String.init) ?? ""
            let lines = unfold(b)
            var from = "", subject = "", dateStr = ""
            for line in lines {
                let low = line.lowercased()
                if low.hasPrefix("from:") { from = decodeMIME(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
                else if low.hasPrefix("subject:") { subject = decodeMIME(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)) }
                else if low.hasPrefix("date:") { dateStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            }
            if from.isEmpty && subject.isEmpty { continue }
            msgs.append(Msg(uid: uid, from: from, subject: subject, date: parseDate(dateStr)))
        }
        return msgs
    }

    /// Join folded header continuation lines (leading space/tab).
    private static func unfold(_ block: String) -> [String] {
        var result: [String] = []
        for raw in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).replacingOccurrences(of: "\r", with: "")
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty {
                result[result.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z",
                    "EEE, d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Minimal RFC2047 encoded-word decoder for Subjects/From.
    private static func decodeMIME(_ s: String) -> String {
        guard s.contains("=?"), let re = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#) else { return s }
        var result = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let full = Range(m.range, in: s),
                  let encR = Range(m.range(at: 2), in: s),
                  let txtR = Range(m.range(at: 3), in: s) else { continue }
            let enc = s[encR].uppercased(); let txt = String(s[txtR])
            var decoded = txt
            if enc == "B" {
                if let d = Data(base64Encoded: txt), let str = String(data: d, encoding: .utf8) { decoded = str }
            } else { // Q
                var q = txt.replacingOccurrences(of: "_", with: " ")
                if let re2 = try? NSRegularExpression(pattern: "=([0-9A-Fa-f]{2})") {
                    for mm in re2.matches(in: q, range: NSRange(q.startIndex..., in: q)).reversed() {
                        if let r2 = Range(mm.range(at: 1), in: q), let byte = UInt8(q[r2], radix: 16),
                           let rr = Range(mm.range, in: q) {
                            q.replaceSubrange(rr, with: String(UnicodeScalar(byte)))
                        }
                    }
                }
                decoded = q
            }
            result.replaceSubrange(full, with: decoded)
        }
        return result
    }
}
