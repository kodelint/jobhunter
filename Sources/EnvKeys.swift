import Foundation

/// Resolves API keys from environment variables.
/// GUI apps launched from Finder don't inherit shell env, so we also read the
/// user's shell config as a fallback. We use a NON-interactive shell on purpose:
/// an interactive shell (zsh -i) emits terminal/shell-integration escape codes
/// (e.g. iTerm2 "]1337;") into stdout, which would corrupt the key.
enum EnvKeys {
    static func varName(for p: AIProvider) -> String? {
        switch p {
        case .claude: return "ANTHROPIC_API_KEY"
        case .gpt: return "OPENAI_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        case .local: return nil
        }
    }

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func value(for p: AIProvider) -> String? {
        guard let name = varName(for: p) else { return nil }
        if let v = ProcessInfo.processInfo.environment[name] {
            let clean = sanitize(v)
            if !clean.isEmpty { return clean }
        }
        return shellValue(name)
    }

    static func hasValue(for p: AIProvider) -> Bool { (value(for: p)?.isEmpty == false) }

    private static func shellValue(_ name: String) -> String? {
        lock.lock()
        if let c = cache[name] { lock.unlock(); return c.isEmpty ? nil : c }
        lock.unlock()
        let out = readFromShell(name) ?? ""
        lock.lock(); cache[name] = out; lock.unlock()
        return out.isEmpty ? nil : out
    }

    private static func readFromShell(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Non-interactive: source the login/env files (not ~/.zshrc, which is interactive config
        // and can run arbitrary shell startup), then print only the value.
        let script = "[ -f ~/.zshenv ] && source ~/.zshenv >/dev/null 2>&1; " +
                     "[ -f ~/.zprofile ] && source ~/.zprofile >/dev/null 2>&1; " +
                     "printf %s \"${\(name)}\""
        task.arguments = ["-c", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(3.0)
        while task.isRunning && Date() < deadline { usleep(40_000) }
        if task.isRunning { task.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let clean = sanitize(raw)
        return clean.isEmpty ? nil : clean
    }

    /// Keep only printable ASCII (0x21–0x7E): strips escape sequences, spaces, newlines.
    private static func sanitize(_ s: String) -> String {
        let scalars = s.unicodeScalars.filter { $0.value >= 0x21 && $0.value <= 0x7E }
        return String(String.UnicodeScalarView(scalars))
    }

    static func prefetch() {
        DispatchQueue.global(qos: .utility).async {
            for p in [AIProvider.claude, .gpt, .gemini] { _ = value(for: p) }
        }
    }
}
