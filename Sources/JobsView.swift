import SwiftUI

@MainActor
struct JobsView: View {
    let tab: JobTab
    @Environment(AppStore.self) private var store
    @State private var selectedID: String?
    @State private var showAddManual = false

    var body: some View {
        @Bindable var store = store
        let list = store.filtered(tab)
        VStack(spacing: 0) {
            header(count: list.count, store: store)
            Divider()
            HSplitView {
                listPane(list)
                    .frame(minWidth: 300, idealWidth: 372, maxWidth: 560)
                    .background(Color.primary.opacity(0.02))
                detailPane(list)
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: tab) { selectedID = nil }
        .sheet(isPresented: $showAddManual) { AddManualJobSheet() }
    }

    // MARK: header
    private func header(count: Int, store: AppStore) -> some View {
        @Bindable var store = store
        return HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.rawValue).font(.system(size: 22, weight: .bold))
                    Text("\(count) \(count == 1 ? "role" : "roles") found").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if tab == .applied {
                Button { showAddManual = true } label: {
                    Label("Add applied job", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GradientButtonStyle())
                .help("Track a job you applied to outside your sources (e.g. a Workday portal).")
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search roles, skills, companies…", text: $store.search).textFieldStyle(.plain).frame(width: 250)
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairline))
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
    }

    // MARK: list
    private func listPane(_ list: [Job]) -> some View {
        Group {
            if list.isEmpty {
                emptyList
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(list) { job in
                            JobCard(job: job, selected: job.id == selectedID) { selectedID = job.id }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var emptyList: some View {
        VStack(spacing: 12) {
            Image(systemName: tab.systemImage).font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(emptyTitle).font(.headline)
            Text(emptyHint).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: detail
    private func detailPane(_ list: [Job]) -> some View {
        Group {
            if let job = list.first(where: { $0.id == selectedID }) ?? list.first {
                JobDetail(job: job)
            } else {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.brand1.opacity(0.12)).frame(width: 82, height: 82)
                        Image(systemName: "briefcase").font(.system(size: 32)).foregroundStyle(Palette.brand1)
                    }
                    Text("Select a role").font(.title3.bold())
                    Text("Pick a role on the left to see its fit, constraints, and AI verdict.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyTitle: String {
        switch tab {
        case .new: return "No new roles"
        case .all: return "No matches yet"
        case .low: return "No low-scoring matches"
        case .favorites: return "No favorites yet"
        case .applied: return "Nothing applied"
        case .ignored: return "Nothing ignored"
        case .wrong: return "No wrong matches"
        }
    }
    private var emptyHint: String {
        if tab == .applied { return "Apply from a match, or use \u{201C}Add applied job\u{201D} above to track one from a company portal (Workday, etc.)." }
        if tab == .wrong { return "Flag a role as \u{201C}Wrong match\u{201D} when it's the opposite of your background (wrong function, domain, or location). The AI learns from these and scores similar roles lower." }
        if tab == .favorites { return "Tap the star on any role to save it here and apply later." }
        if tab == .low { return "Relevant roles that scored below \(AppStore.lowFit) land here, kept out of your main matches." }
        guard tab == .all || tab == .new else {
            return "Roles show up here as you work through matches."
        }
        if store.resumeText.isEmpty {
            return "Import your resume in the Resume tab, then run a scan - matches are ranked against it."
        }
        if store.lastScan.isEmpty {
            return "Run a scan (button in the sidebar) to pull open roles from your sources."
        }
        return "No roles cleared your filters. Loosen the fit threshold or eligibility filters, or add more sources."
    }
}

// MARK: - Job card (list row)

@MainActor
struct JobCard: View {
    let job: Job
    let selected: Bool
    let onTap: () -> Void
    @Environment(AppStore.self) private var store
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                ScoreBadge(score: job.effectiveScore, ai: job.evaluatedByAI, size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Text("\(job.company) · \(job.location.isEmpty ? job.ats.label : job.location)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 5) {
                        if job.favorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow) }
                        if job.isNew && job.status == .active { Badge(text: "New", color: Palette.chip(.good)) }
                        if job.ats == .manual { Badge(text: "Manual", color: Palette.brand2) }
                        if let tier = job.tier { Badge(text: tier.label, color: Palette.tierColor(tier == .startup)) }
                        if !job.evaluatedByAI { Badge(text: "Keyword", color: Color.secondary) }
                        ForEach(badChips) { ChipView(chip: $0) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .background(background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Palette.accentGradient).frame(width: 3, height: 28).padding(.leading, 3)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected ? Palette.brand1.opacity(0.5) : Color.primary.opacity(hover ? 0.13 : 0.06),
                              lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(hover && !selected ? 0.14 : 0), radius: 7, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var background: Color {
        if selected { return Palette.brand1.opacity(0.13) }
        return Color.primary.opacity(hover ? 0.06 : 0.028)
    }
    private var badChips: [Eligibility.Chip] {
        Eligibility.chips(job, store.settings.eligibility).filter { $0.kind == .bad }
    }
}

// MARK: - Job detail

@MainActor
struct JobDetail: View {
    let job: Job
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var notes = ""
    @State private var stage: AppliedStage = .none
    @State private var followUp = false
    @State private var followUpDate = Date()
    @State private var interviewSet = false
    @State private var interviewDateVal = Date()
    @State private var showWrongMatch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                constraintsCard
                if job.evaluatedByAI {
                    if let v = job.aiVerdict, !v.isEmpty { verdictCard(v) }
                    if !job.aiReasons.isEmpty {
                        card("Why it fits") { bullets(job.aiReasons, "checkmark.circle.fill", Palette.chip(.good)) }
                    }
                    if !job.aiGaps.isEmpty {
                        card("Gaps & conflicts") { bullets(job.aiGaps, "exclamationmark.triangle.fill", Palette.chip(.warn)) }
                    }
                    if !job.aiSubscores.isEmpty { fitSignalsCard }
                } else {
                    card("AI evaluation") {
                        Text("Not evaluated yet — showing the keyword score. Enable AI matching in Settings, or this role fell outside the top \(store.settings.topN) shortlist.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !job.descriptionText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        // Match the other card labels' ALL-CAPS style, but bright white for emphasis.
                        Text("Role description".uppercased())
                            .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(.white)
                        DescriptionView(text: job.descriptionText)
                    }
                    .card()
                }
                trackingCard
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .task(id: job.id) {
            notes = job.notes; stage = job.appliedStage
            followUp = job.followUpDate != nil
            followUpDate = job.followUpDate.flatMap(AppStore.parseYMD)
                ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            interviewSet = job.interviewDate != nil
            interviewDateVal = job.interviewDate.flatMap(AppStore.parseYMD)
                ?? Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        }
        .sheet(isPresented: $showWrongMatch) { WrongMatchSheet(job: job) }
    }

    private var fitSignalsCard: some View {
        card("Fit signals") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(FitSignal.ordered, id: \.key) { sig in
                    if let v = job.aiSubscores[sig.key] { signalBar(sig.label, v) }
                }
            }
        }
    }
    private func signalBar(_ label: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text("\(v)").font(.caption.weight(.semibold)).foregroundStyle(Palette.fit(v))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Palette.fit(v)).frame(width: max(6, g.size.width * CGFloat(v) / 100))
                }
            }.frame(height: 6)
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 22) {
            FitDial(score: job.effectiveScore, size: 104, evaluatedByAI: job.evaluatedByAI)
            VStack(alignment: .leading, spacing: 9) {
                Text(job.title).font(.system(size: 24, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text("\(job.company)  ·  \(job.location.isEmpty ? "Location n/a" : job.location)")
                    .font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if job.isNew && job.status == .active { Badge(text: "New", color: Palette.chip(.good)) }
                    if let tier = job.tier { Badge(text: tier.label, color: Palette.tierColor(tier == .startup)) }
                    if job.status == .applied { Badge(text: job.appliedStage.label, color: Palette.brand1) }
                    if job.status == .ignored { Badge(text: "Ignored", color: .gray) }
                    if job.status == .wrongMatch { Badge(text: "Wrong match", color: Palette.chip(.warn)) }
                    Text(job.department.isEmpty ? job.ats.label : job.department)
                        .font(.caption).foregroundStyle(.tertiary)
                }
                actions.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Palette.fitSoft(job.effectiveScore), Color.primary.opacity(0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Palette.fit(job.effectiveScore).opacity(0.25)))
    }

    private var actions: some View {
        HStack(spacing: 9) {
            Button { if let u = URL(string: job.url) { openURL(u) } } label: {
                Label("Apply", systemImage: "paperplane.fill")
            }.buttonStyle(GradientButtonStyle()).disabled(job.url.isEmpty)

            Button { store.markApplied(job) } label: { Label("Mark applied", systemImage: "checkmark") }
                .buttonStyle(.bordered)

            Button { store.toggleFavorite(job) } label: {
                Label(job.favorite ? "Saved" : "Save", systemImage: job.favorite ? "star.fill" : "star")
            }
            .buttonStyle(.bordered).tint(job.favorite ? .yellow : nil)

            if job.status == .ignored || job.status == .wrongMatch {
                Button { store.restore(job) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.bordered)
            } else {
                Button { store.ignore(job) } label: { Label("Ignore", systemImage: "xmark") }
                    .buttonStyle(.bordered)
                Button { showWrongMatch = true } label: { Label("Wrong match", systemImage: "exclamationmark.triangle") }
                    .buttonStyle(.bordered).tint(Palette.chip(.warn))
            }
        }
    }

    private var constraintsCard: some View {
        card("Constraints & good fits") {
            let chips = Eligibility.chips(job, store.settings.eligibility)
            if chips.isEmpty { Text("No constraints detected.").font(.callout).foregroundStyle(.secondary) }
            else { FlowLayout(spacing: 7) { ForEach(chips) { ChipView(chip: $0) } } }
        }
    }

    private func verdictCard(_ v: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Palette.accentGradient).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "AI verdict")
                Text(v).font(.system(size: 15, weight: .medium))
            }
        }
        .padding(16)
        .background(Palette.brand1.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.brand1.opacity(0.20)))
    }

    private var trackingCard: some View {
        card("Tracking") {
            VStack(alignment: .leading, spacing: 13) {
                Picker("Status", selection: $stage) {
                    ForEach(AppliedStage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: stage) { store.setStage(job, stage) }

                if let d = job.appliedDate { Text("Applied \(d)").font(.caption).foregroundStyle(.secondary) }

                Toggle("Remind me to follow up", isOn: $followUp)
                    .onChange(of: followUp) { store.setFollowUp(job, followUp ? AppStore.ymd(followUpDate) : nil) }
                if followUp {
                    DatePicker("Follow-up date", selection: $followUpDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .onChange(of: followUpDate) { store.setFollowUp(job, AppStore.ymd(followUpDate)) }
                }

                if stage == .interviewing {
                    Toggle("Interview scheduled", isOn: $interviewSet)
                        .onChange(of: interviewSet) { store.setInterviewDate(job, interviewSet ? AppStore.ymd(interviewDateVal) : nil) }
                    if interviewSet {
                        DatePicker("Interview date", selection: $interviewDateVal, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .onChange(of: interviewDateVal) { store.setInterviewDate(job, AppStore.ymd(interviewDateVal)) }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: "Notes")
                    TextEditor(text: $notes)
                        .frame(minHeight: 66).font(.callout).scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
                        .onChange(of: notes) { store.setNotes(job, notes) }
                }
            }
        }
    }

    private func bullets(_ items: [String], _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: symbol).foregroundStyle(color).font(.system(size: 13)).padding(.top, 1)
                    Text(item).font(.callout)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(text: title)
            content()
        }
        .card()
    }
}

// MARK: - Add applied job (manual entry for applications made outside the scanned sources)

@MainActor
struct AddManualJobSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var company = ""
    @State private var title = ""
    @State private var url = ""
    @State private var location = ""
    @State private var stage: AppliedStage = .applied
    @State private var notes = ""

    // Stages that imply the candidate has already applied (excludes "Not applied").
    private let stages: [AppliedStage] = [.applied, .interviewing, .offer, .rejected]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add applied job").font(.title2.bold())
            Text("Track a role you applied to outside your sources - a company's own portal like Workday, a referral, or LinkedIn. If Gmail sync is on, its status updates automatically from your inbox; otherwise set it here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Company", text: $company)
                TextField("Job title", text: $title)
                TextField("Posting URL (optional)", text: $url).font(.system(.body, design: .monospaced))
                TextField("Location (optional)", text: $location)
                Picker("Status", selection: $stage) { ForEach(stages) { Text($0.label).tag($0) } }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    store.addManualJob(company: company.trimmingCharacters(in: .whitespaces),
                                       title: title.trimmingCharacters(in: .whitespaces),
                                       url: url.trimmingCharacters(in: .whitespaces),
                                       location: location.trimmingCharacters(in: .whitespaces),
                                       stage: stage, notes: notes.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(company.isEmpty || title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Wrong match (fundamentally off-profile; captures a reason that teaches future AI scoring)

@MainActor
struct WrongMatchSheet: View {
    let job: Job
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    private let presets = ["Wrong function (e.g. sales, design, ops)", "Wrong domain / industry",
                           "Wrong location / country", "Too junior", "Too senior",
                           "Unrelated to my background"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wrong match").font(.title2.bold())
            Text("\(job.title) · \(job.company)").font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Text("Use this when a role is the opposite of your background - wrong function, domain, seniority, or location. The AI learns from these and scores similar roles lower on future scans. A reason sharpens it (optional).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 7) {
                ForEach(presets, id: \.self) { p in
                    Button { reason = p } label: { Text(p).font(.caption) }.buttonStyle(.bordered)
                }
            }
            TextField("Reason (optional)", text: $reason, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Flag wrong match") { store.markWrongMatch(job, reason: reason); dismiss() }
                    .buttonStyle(GradientButtonStyle())
            }
        }
        .padding(20).frame(width: 470)
    }
}

// MARK: - Structured role-description renderer (headings / bullets / paragraphs)

struct DescriptionView: View {
    let text: String
    private enum Block { case heading(String), bullet(String), para(String) }

    // Lowercased prefixes that mark a section heading even without a trailing colon.
    private static let headers = ["responsibilit", "requirement", "qualification", "what you", "who you",
                                  "about the", "about you", "about the role", "the role", "benefit", "perks",
                                  "preferred", "basic qualif", "minimum qualif", "nice to have", "your impact",
                                  "day to day", "what we", "overview", "the opportunity", "compensation",
                                  "in this role", "key responsibilit", "what success", "how you"]
    // Common headers used to re-section flat/blobby text that lost its line breaks.
    private static let flatBreaks = ["About the Role", "About the role", "What You'll Do", "What you'll do",
                                     "What You Will Do", "Who You Are", "Who you are", "What We're Looking For",
                                     "What we're looking for", "What We Are Looking For", "Responsibilities",
                                     "Requirements", "Qualifications", "Preferred Qualifications",
                                     "Basic Qualifications", "Minimum Qualifications", "Benefits", "Perks",
                                     "Nice to Have", "Your Impact", "The Role"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                switch b {
                case .heading(let h):
                    Text(h).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.top, i == 0 ? 0 : 8).fixedSize(horizontal: false, vertical: true)
                case .bullet(let t):
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(Palette.brand1).frame(width: 5, height: 5).padding(.top, 7)
                        Text(t).font(.callout).foregroundStyle(Color.primary.opacity(0.8))
                            .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                case .para(let t):
                    Text(t).font(.callout).foregroundStyle(Color.primary.opacity(0.8))
                        .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        for raw in sourceLines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let b = bulletText(line) { out.append(.bullet(b)) }
            else if isHeading(line) { out.append(.heading(line.hasSuffix(":") ? String(line.dropLast()) : line)) }
            else { out.append(.para(line)) }
        }
        return out
    }

    /// Prefer the real line breaks; if the text is one flat blob, inject breaks before common headers.
    private var sourceLines: [Substring] {
        if text.contains("\n") { return text.split(separator: "\n", omittingEmptySubsequences: true) }
        var s = text
        for h in Self.flatBreaks { s = s.replacingOccurrences(of: h, with: "\n\n" + h) }
        return s.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private func bulletText(_ l: String) -> String? {
        for m in ["• ", "- ", "* ", "· ", "– ", "● ", "▪ "] where l.hasPrefix(m) { return String(l.dropFirst(m.count)) }
        return nil
    }
    private static let smallWords: Set<String> = ["the", "a", "an", "of", "and", "to", "for", "in", "on", "with", "at", "by", "or"]

    private func isHeading(_ l: String) -> Bool {
        if l.count > 70 || l.hasSuffix(".") || l.hasSuffix(",") { return false }
        if l.hasSuffix(":") { return true }
        let low = l.lowercased()
        if Self.headers.contains(where: { low.hasPrefix($0) }) { return true }
        // ALL-CAPS short line, e.g. "WHAT WE'RE LOOKING FOR" or "COME AS YOU ARE".
        let letters = l.filter { $0.isLetter }
        if !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }), l.count <= 60 { return true }
        // Title-case short line: every significant word capitalized (e.g. "Who We Are", "About You").
        let words = l.split(separator: " ")
        if words.count <= 5 {
            let significant = words.filter { !Self.smallWords.contains($0.lowercased()) }
            if significant.count >= 2, significant.allSatisfy({ $0.first?.isUppercase == true }) { return true }
        }
        return false
    }
}
