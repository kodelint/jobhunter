import Foundation
import SwiftUI
import Observation

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

enum BackgroundMode: String, CaseIterable, Identifiable, Codable {
    case whileRunning, always
    var id: String { rawValue }
    var label: String { self == .whileRunning ? "While app runs" : "Always (helper)" }
}

@MainActor @Observable
final class Settings {
    var appearance: Appearance { didSet { persist() } }
    var provider: AIProvider { didSet { persist() } }
    var model: String { didSet { persist() } }
    var baseURL: String { didSet { persist() } }
    var useAI: Bool { didSet { persist() } }
    var topN: Int { didSet { persist() } }
    var showMinFit: Int { didSet { persist() } }
    var requireUS: Bool { didSet { persist() } }
    var backgroundMode: BackgroundMode { didSet { persist() } }
    var scanIntervalHours: Int { didSet { persist() } }
    var retentionDays: Int { didSet { persist() } }
    var eligibility: EligibilityProfile { didSet { persist() } }
    var gmailEnabled: Bool { didSet { persist() } }
    var gmailAddress: String { didSet { persist() } }
    var inboxSyncDays: Int { didSet { persist() } }
    // Negative-match feedback: reasons the candidate rejected roles, injected into future AI evals.
    var matchFeedback: [String] { didSet { persist() } }

    private let d = UserDefaults.standard
    private var loading = false

    init() {
        loading = true
        appearance = Settings.decode("appearance") ?? .system
        let p: AIProvider = Settings.decode("provider") ?? .claude
        provider = p
        model = d.string(forKey: "model") ?? ""
        baseURL = d.string(forKey: "baseURL") ?? ""
        useAI = d.object(forKey: "useAI") as? Bool ?? true
        topN = d.object(forKey: "topN") as? Int ?? 40
        showMinFit = d.object(forKey: "showMinFit") as? Int ?? 0
        requireUS = d.object(forKey: "requireUS") as? Bool ?? true
        backgroundMode = Settings.decode("backgroundMode") ?? .whileRunning
        scanIntervalHours = d.object(forKey: "scanIntervalHours") as? Int ?? 6
        retentionDays = d.object(forKey: "retentionDays") as? Int ?? 45
        eligibility = Settings.decode("eligibility") ?? .default
        gmailEnabled = d.object(forKey: "gmailEnabled") as? Bool ?? false
        gmailAddress = d.string(forKey: "gmailAddress") ?? ""
        inboxSyncDays = d.object(forKey: "inboxSyncDays") as? Int ?? 45
        matchFeedback = Settings.decode("matchFeedback") ?? []
        loading = false
    }

    func selectProvider(_ p: AIProvider) {
        provider = p
        model = ""
        baseURL = p.defaultBaseURL
    }

    private func persist() {
        guard !loading else { return }
        Settings.encode(appearance, "appearance")
        Settings.encode(provider, "provider")
        d.set(model, forKey: "model")
        d.set(baseURL, forKey: "baseURL")
        d.set(useAI, forKey: "useAI")
        d.set(topN, forKey: "topN")
        d.set(showMinFit, forKey: "showMinFit")
        d.set(requireUS, forKey: "requireUS")
        Settings.encode(backgroundMode, "backgroundMode")
        d.set(scanIntervalHours, forKey: "scanIntervalHours")
        d.set(retentionDays, forKey: "retentionDays")
        Settings.encode(eligibility, "eligibility")
        d.set(gmailEnabled, forKey: "gmailEnabled")
        d.set(gmailAddress, forKey: "gmailAddress")
        d.set(inboxSyncDays, forKey: "inboxSyncDays")
        Settings.encode(matchFeedback, "matchFeedback")
    }

    private static func encode<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { UserDefaults.standard.set(data, forKey: key) }
    }
    private static func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
