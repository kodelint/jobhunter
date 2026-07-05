import SwiftUI

@MainActor
struct EligibilityView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        SplitScaffold("Eligibility", subtitle: "What counts as a fit - drives the chip colors and filters",
                      icon: "checkmark.shield", rightWidth: 340) {
            // MARK: left - controls
            SettingsGroup("Location", icon: "mappin.and.ellipse") {
                SettingRow("Country", subtitle: "Auto-set from your resume; change any time") {
                    Picker("", selection: Binding(
                        get: { settings.eligibility.country.isEmpty ? "Any" : settings.eligibility.country },
                        set: { settings.eligibility.country = ($0 == "Any" ? "" : $0) })) {
                        ForEach(Geo.pickable, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 190)
                }
                SettingRow("States / regions", subtitle: "Optional, comma-separated (e.g. CA, New York)") {
                    TextField("Any", text: statesText).textFieldStyle(.roundedBorder).frame(width: 190)
                }
                SettingToggle(title: "Include anywhere-remote roles",
                              subtitle: "Show global-remote roles even if outside your country.",
                              isOn: $settings.eligibility.includeRemoteGlobal)
            }

            SettingsGroup("Level", icon: "chart.bar.doc.horizontal") {
                if !store.profile.level.isEmpty {
                    SettingRow("Your target level") {
                        Text(store.profile.level).font(.callout).foregroundStyle(.secondary)
                    }
                }
                SettingToggle(title: "Also show roles below my level",
                              subtitle: "Include IC, mid, and junior roles. Off = only your target band and up.",
                              isOn: $settings.eligibility.includeBelowLevel)
            }

            SettingsGroup("Your situation", icon: "person.text.rectangle") {
                SettingRow("Work authorization") {
                    Picker("", selection: $settings.eligibility.status) {
                        ForEach(EligibilityStatus.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 190)
                }
                SettingSlider(title: "Minimum base",
                              valueText: settings.eligibility.minBase == 0 ? "Any" : "$\(settings.eligibility.minBase)k",
                              value: Binding(get: { Double(settings.eligibility.minBase) },
                                             set: { settings.eligibility.minBase = Int($0) }),
                              range: 0...600, step: 10)
            }

            SettingsGroup("Work style", icon: "laptopcomputer") {
                SettingToggle(title: "Remote", isOn: styleBinding("remote"))
                SettingToggle(title: "Hybrid", isOn: styleBinding("hybrid"))
                SettingToggle(title: "Onsite", isOn: styleBinding("onsite"))
            }

            SettingsGroup("Filtering", icon: "line.3.horizontal.decrease.circle") {
                SettingToggle(title: "Only show roles I'm eligible for",
                              subtitle: "Hides citizens-only, below-floor, or clearance roles you can't take. Off = still shown, flagged red.",
                              isOn: $settings.eligibility.onlyEligible)
            }

            SettingsGroup("Signals shown on cards", icon: "tag") {
                SettingToggle(title: "Compensation", isOn: $settings.eligibility.showComp)
                SettingToggle(title: "Work authorization", isOn: $settings.eligibility.showAuth)
                SettingToggle(title: "Remote / hybrid / onsite", isOn: $settings.eligibility.showRemote)
                SettingToggle(title: "Years of experience", isOn: $settings.eligibility.showYOE)
                SettingToggle(title: "IC vs. manager scope", isOn: $settings.eligibility.showScope)
                SettingToggle(title: "Travel / on-call", isOn: $settings.eligibility.showTravelOnCall)
                SettingToggle(title: "Security clearance", isOn: $settings.eligibility.showClearance)
            }
        } right: {
            // MARK: right - live preview that reacts to the toggles
            PanelCard("Live preview", icon: "eye") {
                Text("How a role appears with your current settings:")
                    .font(.caption).foregroundStyle(.secondary)
                previewCard(Self.sampleWellMatched)
                previewCard(Self.sampleRestricted)
            }
        }
    }

    // MARK: preview card
    private func previewCard(_ job: Job) -> some View {
        let elig = store.settings.eligibility
        let chips = Eligibility.chips(job, elig)
        let ok = Eligibility.isEligible(job, elig)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ScoreRing(score: job.effectiveScore, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(job.company).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if chips.isEmpty {
                Text("No signals enabled.").font(.caption).foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) { ForEach(chips) { ChipView(chip: $0) } }
            }
            verdict(ok: ok, hidden: !ok && elig.onlyEligible)
        }
        .padding(13)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func verdict(ok: Bool, hidden: Bool) -> some View {
        let text = ok ? "Shows in matches" : hidden ? "Hidden by your filter" : "Shown, flagged red"
        let color = ok ? Palette.chip(.good) : hidden ? Palette.chip(.bad) : Palette.chip(.warn)
        let icon = ok ? "checkmark.circle.fill" : hidden ? "eye.slash.fill" : "exclamationmark.triangle.fill"
        return Label(text, systemImage: icon)
            .font(.caption.weight(.semibold)).foregroundStyle(color)
    }

    private var statesText: Binding<String> {
        Binding(
            get: { store.settings.eligibility.states.joined(separator: ", ") },
            set: { store.settings.eligibility.states = $0.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    private func styleBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { store.settings.eligibility.workStyles.contains(key) },
            set: { on in
                if on { store.settings.eligibility.workStyles.insert(key) }
                else { store.settings.eligibility.workStyles.remove(key) }
            })
    }

    // MARK: sample roles for the preview
    private static func sample(_ title: String, _ company: String, score: Int, _ c: JobConstraints) -> Job {
        Job(id: "sample::\(company)", company: company, tier: .startup, ats: .greenhouse,
            title: title, location: "", url: "", department: "", descriptionText: "", postedAt: "",
            keywordScore: score, aiScore: score, aiVerdict: nil, aiReasons: [], aiGaps: [],
            constraints: c, status: .active, appliedStage: .none, appliedDate: nil,
            followUpDate: nil, notes: "", firstSeen: "", lastSeen: "", isNew: false)
    }
    static let sampleWellMatched: Job = {
        var c = JobConstraints(); c.salaryMin = 185; c.salaryMax = 235
        c.workAuth = .sponsorOffered; c.remotePolicy = "Remote"; c.yoeMin = 8; c.managerScope = "manager"
        return sample("Staff Platform Engineer", "Northwind", score: 88, c)
    }()
    static let sampleRestricted: Job = {
        var c = JobConstraints(); c.workAuth = .citizensOnly; c.clearance = true
        c.remotePolicy = "Onsite"; c.yoeMin = 10; c.salaryMin = 150
        return sample("Principal Engineer", "Vertex Federal", score: 74, c)
    }()
}
