import SwiftUI

@MainActor
struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var apiKey = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        @Bindable var settings = store.settings
        SplitScaffold("AI & Settings", subtitle: "Provider, keys, matching, scanning, and appearance",
                      icon: "wand.and.stars", rightWidth: 300) {
            // MARK: left - controls
            SettingsGroup("Provider", icon: "cpu") {
                Picker("", selection: Binding(
                    get: { settings.provider },
                    set: { settings.selectProvider($0); loadKey(); store.refreshAIState(); testResult = nil })) {
                    ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().padding(.vertical, 4)

                SettingRow("Model") {
                    if store.loadingModels && store.availableModels.isEmpty {
                        ProgressView().controlSize(.small).frame(width: 230, alignment: .trailing)
                    } else if store.availableModels.isEmpty {
                        Text(settings.provider.needsKey ? "Add API key to load models" : "No models found")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: $settings.model) {
                            ForEach(store.availableModels, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 230)
                    }
                }

                if settings.provider == .local {
                    TextField("Base URL", text: $settings.baseURL, prompt: Text("http://localhost:11434"))
                        .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                        .onSubmit { store.refreshAIState() }
                }

                if settings.provider.needsKey {
                    SecureField("API key", text: $apiKey, prompt: Text(envPrompt))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveKey() }
                        .onChange(of: apiKey) { saveKey() }
                    keyStatus
                }
            }

            SettingsGroup("Matching", icon: "slider.horizontal.3") {
                SettingToggle(title: "Use AI to score fit", isOn: $settings.useAI)
                SettingSlider(title: "Deep-evaluate top", valueText: "\(settings.topN) roles",
                              value: Binding(get: { Double(settings.topN) }, set: { settings.topN = Int($0) }),
                              range: 10...100, step: 5)
                SettingSlider(title: "Hide fit below",
                              valueText: settings.showMinFit == 0 ? "Off" : "\(settings.showMinFit)",
                              value: Binding(get: { Double(settings.showMinFit) }, set: { settings.showMinFit = Int($0) }),
                              range: 0...90, step: 5)
                Text("Location and level filters live in the Eligibility tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsGroup("What the AI avoids", icon: "hand.thumbsdown") {
                if settings.matchFeedback.isEmpty {
                    Text("Flag a role as \u{201C}Wrong match\u{201D} (wrong function, domain, or location) - it lands here and steers future AI scoring away from similar off-profile roles.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(settings.matchFeedback, id: \.self) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "minus.circle.fill").font(.caption)
                                .foregroundStyle(Palette.chip(.warn)).padding(.top, 2)
                            Text(entry).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Button { store.removeMatchFeedback(entry) } label: {
                                Image(systemName: "trash").font(.caption2)
                            }.buttonStyle(.plain).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            SettingsGroup("Scanning", icon: "clock.arrow.circlepath") {
                SettingRow("Background scanning") {
                    Picker("", selection: $settings.backgroundMode) {
                        ForEach(BackgroundMode.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 190)
                }
                SettingRow("Scan interval", subtitle: "Every \(settings.scanIntervalHours) hours") {
                    Stepper("", value: $settings.scanIntervalHours, in: 1...24).labelsHidden()
                }
                SettingSlider(title: "Keep roles for", valueText: "\(settings.retentionDays) days",
                              value: Binding(get: { Double(settings.retentionDays) }, set: { settings.retentionDays = Int($0) }),
                              range: 7...180, step: 1)
                Text("Old, unsaved postings are purged after this many days; storage is also capped at \(AppStore.storeCap) active roles. Applied, ignored, and saved (favorite) roles are always kept.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Scans run while JobHunter (or its menu-bar icon) is open. To scan after quitting, add JobHunter to System Settings > General > Login Items.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsGroup("Appearance", icon: "paintbrush") {
                Picker("", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().padding(.vertical, 4)
            }
        } right: {
            // MARK: right - live status + cost
            statusPanel(settings: settings)
            costPanel(settings: settings)
            aboutPanel
        }
        .onAppear { loadKey() }
    }

    private var aboutPanel: some View {
        PanelCard("About", icon: "info.circle") {
            HStack {
                Text("Version").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("v\(AppVersion.short) (build \(AppVersion.build))")
                    .font(.system(.caption, design: .monospaced))
            }
            HStack {
                Text("Seeded boards").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(SeedData.companies.count)")
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    // MARK: right panels
    private func statusPanel(settings: Settings) -> some View {
        let ok = store.aiReady
        return PanelCard("Connection", icon: "dot.radiowaves.left.and.right") {
            HStack(spacing: 9) {
                Circle().fill(ok ? Palette.chip(.good) : Palette.chip(.warn))
                    .frame(width: 10, height: 10)
                    .shadow(color: (ok ? Palette.chip(.good) : Palette.chip(.warn)).opacity(0.8), radius: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ok ? "Ready" : (settings.provider.needsKey ? "Key needed" : "Ready"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ok ? Palette.chip(.good) : Palette.chip(.warn))
                    Text("\(settings.provider.label) · \(settings.model)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Button {
                testing = true; testResult = nil
                Task {
                    let cfg = AIConfig(provider: settings.provider, model: settings.model,
                                       apiKey: effectiveKey, baseURL: settings.baseURL)
                    switch await AIService.testConnection(cfg) {
                    case .success(let r): testOK = true; testResult = "Connected · \(r)"
                    case .failure(let e): testOK = false; testResult = e.localizedDescription
                    }
                    testing = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text(testing ? "Testing…" : "Test connection")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(testing || (settings.provider.needsKey && effectiveKey.isEmpty))

            if let r = testResult {
                Label(r, systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(testOK ? Palette.chip(.good) : Palette.chip(.bad))
                    .font(.caption).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func costPanel(settings: Settings) -> some View {
        PanelCard("Estimated cost", icon: "creditcard") {
            let cost = costPerScan(settings)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(cost == 0 ? "Free" : String(format: "$%.2f", cost))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(cost == 0 ? Palette.chip(.good) : .primary)
                    .contentTransition(.numericText())
                Text(cost == 0 ? "· local model" : "/ scan").font(.callout).foregroundStyle(.secondary)
            }
            Text(settings.useAI
                 ? "Deep-evaluates the top \(settings.topN) keyword matches. Already-scored roles are never re-sent."
                 : "AI scoring is off. You're running on free keyword matching only.")
                .font(.caption).foregroundStyle(.secondary)
            if cost > 0 {
                Label("First scan only; re-scans reuse cached scores.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// Rough per-scan estimate. ponytail: coarse per-model rates, not a live pricing feed.
    private func costPerScan(_ settings: Settings) -> Double {
        guard settings.useAI else { return 0 }
        let m = settings.model.lowercased()
        let per: Double
        switch settings.provider {
        case .local: per = 0
        case .claude: per = m.contains("opus") ? 0.012 : m.contains("haiku") ? 0.0010 : 0.0045
        case .gpt:    per = m.contains("mini") ? 0.0009 : 0.0060
        case .gemini: per = m.contains("flash") ? 0.0004 : 0.0040
        }
        return Double(settings.topN) * per
    }

    // MARK: key helpers
    private var keyStatus: some View {
        Group {
            let src = store.aiKeySource
            if src == "keychain" {
                Label("Stored in your macOS Keychain.", systemImage: "key.fill").font(.caption).foregroundStyle(.secondary)
            } else if src == "env", let v = EnvKeys.varName(for: store.settings.provider) {
                Label("Using \(v) from your environment.", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
            } else if let v = EnvKeys.varName(for: store.settings.provider) {
                Text("Paste a key (saved to Keychain) or export \(v) in your shell.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var envPrompt: String {
        if store.aiKeySource == "env", let v = EnvKeys.varName(for: store.settings.provider) {
            return "Using \(v) from environment"
        }
        return "sk-…"
    }

    private var effectiveKey: String {
        apiKey.isEmpty ? (EnvKeys.value(for: store.settings.provider) ?? "") : apiKey
    }

    private func loadKey() { apiKey = Keychain.get(store.settings.provider.keychainAccount) ?? "" }
    private func saveKey() {
        let acct = store.settings.provider.keychainAccount
        if apiKey.isEmpty { Keychain.delete(acct) } else { Keychain.set(apiKey, account: acct) }
        store.refreshAIState()
    }
}
