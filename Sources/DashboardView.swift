import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    var onNavigate: (SidebarItem) -> Void
    @State private var showAddManual = false
    @State private var wrongMatchJob: Job?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greeting
                if showGetStarted { getStartedCard }
                kpiRow
                HStack(alignment: .top, spacing: 16) {
                    topMatchSlot.frame(maxWidth: .infinity)
                    moreMatchesCard.frame(width: 320)
                }
                analyticsRow
                bottomRow
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showAddManual) { AddManualJobSheet() }
        .sheet(item: $wrongMatchJob) { WrongMatchSheet(job: $0) }
    }

    // MARK: greeting (warm, time-aware)
    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Self.timeGreeting), \(Self.firstName)").font(.system(size: 27, weight: .bold))
                Text(warmSubline).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                statusPill(store.aiReady ? "\(store.settings.provider.label) ready" : "AI key needed",
                           store.aiReady ? Palette.chip(.good) : Palette.chip(.warn), "sparkles")
                statusPill(store.gmailConfigured() ? "Gmail on" : "Gmail off",
                           store.gmailConfigured() ? Palette.chip(.good) : .secondary, "envelope")
            }
        }
    }

    private var warmSubline: String {
        let new = store.count(.new), due = store.followUpsDue.count, all = store.count(.all)
        if store.lastScan.isEmpty { return "Let's find your next role - run your first scan." }
        if new > 0 {
            let base = "\(new) fresh role\(new == 1 ? "" : "s") waiting · \(all) in your queue"
            return due > 0 ? base + " · \(due) follow-up\(due == 1 ? "" : "s") due" : base
        }
        if due > 0 { return "\(due) follow-up\(due == 1 ? "" : "s") due today - stay on it." }
        return "You're all caught up. Nice work."
    }

    static var timeGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Working late"
        }
    }
    static var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }

    private func statusPill(_ text: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: get started (first-run onboarding, hides once set up)
    private var showGetStarted: Bool { store.resumeText.isEmpty || store.lastScan.isEmpty }

    private var getStartedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Get started")
            stepRow(done: !store.resumeText.isEmpty, title: "Import your resume",
                    detail: "Ranks every role against your real background.", cta: "Resume") { onNavigate(.resume) }
            stepRow(done: store.aiReady, title: "Add an AI key (optional)",
                    detail: "Adds a deeper fit verdict. Keyword scoring works without it.", cta: "AI & Settings") { onNavigate(.ai) }
            stepRow(done: !store.lastScan.isEmpty, title: "Run your first scan",
                    detail: "Pulls open roles from every enabled source.",
                    cta: store.scan.running ? "Scanning…" : "Scan now") { Task { await store.scanNow() } }
        }
        .card()
    }

    private func stepRow(done: Bool, title: String, detail: String, cta: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18)).foregroundStyle(done ? AnyShapeStyle(Palette.chip(.good)) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                    .strikethrough(done, color: .secondary).foregroundStyle(done ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { Button(cta, action: action).buttonStyle(.bordered).disabled(store.scan.running && cta.hasPrefix("Scan")) }
        }
    }

    // MARK: KPI row (interview card only shows when Gmail is connected)
    private var kpiRow: some View {
        HStack(spacing: 14) {
            kpiCard("Active applications", "\(store.count(.applied))",
                    appliedThisWeek > 0 ? "▲\(appliedThisWeek) this week" : "in your pipeline", up: appliedThisWeek > 0,
                    "paperplane.fill", Palette.brand1) { onNavigate(.jobs(.applied)) }
            if store.gmailConfigured() {
                kpiCard("Interviews booked", "\(store.interviewingJobs.count)", nextInterviewText, up: false,
                        "calendar", Palette.brand2) { onNavigate(.jobs(.applied)) }
            }
            kpiCard("Avg match fit", "\(store.avgMatchFit)", fitTrendText, up: (store.fitTrend ?? 0) >= 0,
                    "chart.line.uptrend.xyaxis", Palette.chip(.good)) { onNavigate(.jobs(.all)) }
            kpiCard("Profile strength", "\(store.profileStrength)%", "Tune your resume", up: false,
                    "shield.lefthalf.filled", .orange) { onNavigate(.resume) }
        }
    }

    private func kpiCard(_ title: String, _ big: String, _ sub: String, up: Bool,
                         _ icon: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint)
                }
                Text(big).font(.system(size: 30, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(sub).font(.caption2).foregroundStyle(up ? AnyShapeStyle(Palette.chip(.good)) : AnyShapeStyle(Color.secondary))
            }
            .card()
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var appliedThisWeek: Int {
        let cutoff = AppStore.cutoff(daysAgo: 7)
        return store.jobs.filter { $0.status == .applied && ($0.appliedDate ?? "") >= cutoff }.count
    }
    private var nextInterviewText: String {
        if let d = store.interviewingJobs.compactMap(\.interviewDate).min() { return "next: \(d)" }
        return store.interviewingJobs.isEmpty ? "none scheduled" : "\(store.interviewingJobs.count) in progress"
    }
    private var fitTrendText: String {
        guard let t = store.fitTrend else { return "across current matches" }
        return "\(t >= 0 ? "▲" : "▼")\(abs(t)) vs last scan"
    }

    // MARK: top match (flat #3-style card with why/gaps; scanning/invite states otherwise)
    @ViewBuilder private var topMatchSlot: some View {
        if store.scan.running { scanningCard }
        else if let job = store.stats.topNew.first { topMatchCard(job) }
        else { scanInvite }
    }

    private func topMatchCard(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionLabel(text: "Top match for you")
                Spacer()
                Button("View all matches") { onNavigate(.jobs(.all)) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Palette.brand1)
            }
            HStack(alignment: .center, spacing: 18) {
                ScoreRing(score: job.effectiveScore, size: 84)
                VStack(alignment: .leading, spacing: 7) {
                    Text(job.title).font(.system(size: 21, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(metaLine(job)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 9) {
                        Button { if let u = URL(string: job.url) { openURL(u) } } label: {
                            Label("Apply", systemImage: "paperplane.fill")
                        }.buttonStyle(GradientButtonStyle()).disabled(job.url.isEmpty)
                        Button { wrongMatchJob = job } label: { Label("Not a fit", systemImage: "hand.thumbsdown") }
                            .buttonStyle(.bordered)
                        Button { store.toggleFavorite(job) } label: {
                            Image(systemName: job.favorite ? "star.fill" : "star")
                        }.buttonStyle(.bordered).tint(job.favorite ? .yellow : nil)
                    }.padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if job.evaluatedByAI && (!job.aiReasons.isEmpty || !job.aiGaps.isEmpty) {
                Divider().opacity(0.4)
                HStack(alignment: .top, spacing: 24) {
                    if !job.aiReasons.isEmpty {
                        matchColumn("WHY YOU MATCH", "checkmark.circle.fill", Palette.chip(.good), job.aiReasons)
                    }
                    if !job.aiGaps.isEmpty {
                        matchColumn("GAPS TO ADDRESS", "exclamationmark.triangle.fill", Palette.chip(.warn), job.aiGaps)
                    }
                }
            } else if !job.evaluatedByAI {
                Text("Keyword-ranked. Enable AI matching in Settings for a fit verdict, why-you-match, and gaps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 20)
    }

    private func matchColumn(_ title: String, _ icon: String, _ color: Color, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(color)
            ForEach(items.prefix(3), id: \.self) { item in
                HStack(alignment: .top, spacing: 7) {
                    Text("›").font(.caption.weight(.bold)).foregroundStyle(color.opacity(0.7))
                    Text(item).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaLine(_ job: Job) -> String {
        var parts = [job.company]
        if !job.location.isEmpty { parts.append(job.location) }
        if let mn = job.constraints.salaryMin {
            parts.append(job.constraints.salaryMax != nil ? "$\(mn)k-$\(job.constraints.salaryMax!)k" : "$\(mn)k+")
        }
        return parts.joined(separator: " · ")
    }

    private var scanningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scanning your sources…").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
            Text(store.scan.phase.isEmpty ? "Pulling fresh roles…" : store.scan.phase)
                .font(.callout).foregroundStyle(.white.opacity(0.88))
            ProgressView(value: store.scan.fraction).tint(.white)
            Text("\(Int(store.scan.fraction * 100))% complete").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background { gradientBG }.shadow(color: Palette.brand1.opacity(0.3), radius: 16, y: 7)
    }

    private var scanInvite: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Ready when you are").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
            Text(store.resumeText.isEmpty ? "Import your resume, then scan to see roles ranked for you."
                 : "Run a scan to pull fresh roles and surface your best-fit picks.")
                .font(.callout).foregroundStyle(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
            Button { Task { await store.scanNow() } } label: {
                Label(store.scan.running ? "Scanning…" : "Scan now", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.brand1)
                    .padding(.horizontal, 18).padding(.vertical, 10).background(.white, in: Capsule())
            }.buttonStyle(.plain).disabled(store.scan.running)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background { gradientBG }.shadow(color: Palette.brand1.opacity(0.3), radius: 16, y: 7)
    }

    private var gradientBG: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Palette.accentGradient)
            .overlay(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    // MARK: more top matches
    private var moreMatchesCard: some View {
        let list = Array(store.filtered(.all, ignoreSearch: true)
            .filter { $0.id != store.stats.topNew.first?.id }.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "More top matches")
                Spacer()
                if !list.isEmpty {
                    Button("See all") { onNavigate(.jobs(.all)) }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.brand1)
                }
            }
            if list.isEmpty {
                Text(store.lastScan.isEmpty ? "Run a scan to see your best-fit roles." : "No other matches yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(list) { job in
                    Button { onNavigate(.jobs(.all)) } label: {
                        HStack(spacing: 11) {
                            initialBadge(job.company)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                Text(job.company + (job.location.isEmpty ? "" : " · \(job.location)"))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text("\(job.effectiveScore)").font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.fit(job.effectiveScore))
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if job.id != list.last?.id { Divider().opacity(0.35) }
                }
            }
        }
        .card()
    }

    private func initialBadge(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.brand1.opacity(0.16))
            Text(String(name.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.brand1)
        }.frame(width: 32, height: 32)
    }

    // MARK: analytics row (fit + pipeline + weekly, weekly hides with no history)
    private var analyticsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            fitBreakdownCard.frame(maxWidth: .infinity)
            pipelineCard.frame(maxWidth: .infinity)
            if weeklyHasData { weeklyChartCard.frame(maxWidth: .infinity) }
        }
    }

    private var weeklyHasData: Bool { store.weeklyNewMatches().contains { $0.count > 0 } }

    // Per-signal breakdown when the top match has AI sub-scores; otherwise the band distribution.
    private var fitBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Fit breakdown")
            if let job = store.stats.topNew.first, !job.aiSubscores.isEmpty {
                ForEach(FitSignal.ordered, id: \.key) { sig in
                    if let v = job.aiSubscores[sig.key] { bar(sig.label, v, Palette.fit(v)) }
                }
            } else {
                let bands: [(String, Int)] = [("Strong", 85), ("Good", 70), ("Fair", 55), ("Low", 40)]
                let counts = store.stats.fit
                let maxC = max(counts.max() ?? 1, 1)
                ForEach(Array(bands.enumerated()), id: \.offset) { i, b in
                    bar(b.0, Int(240 * Double(counts[i]) / Double(maxC)), Palette.fit(b.1), trailing: "\(counts[i])")
                }
            }
        }
        .card()
    }

    private func bar(_ label: String, _ pct: Int, _ color: Color, trailing: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text(trailing ?? "\(pct)").font(.caption.weight(.semibold)).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: max(4, g.size.width * CGFloat(min(pct, 100)) / 100))
                }
            }.frame(height: 6)
        }
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Your pipeline")
                Spacer()
                Button { showAddManual = true } label: { Label("Add applied job", systemImage: "plus.circle.fill").font(.caption.weight(.semibold)) }
                    .buttonStyle(GradientButtonStyle())
            }
            pipeRow("Matches", store.count(.all), Palette.brand2)
            pipeRow("Applied", store.count(.applied), Palette.brand1)
            pipeRow("Interviewing", store.stageCount(.interviewing), Palette.chip(.good))
            pipeRow("Offers", store.stageCount(.offer), .orange)
            if store.count(.applied) > 0 {
                Divider().opacity(0.4)
                HStack {
                    Text("Response rate").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(Double(store.responsesCount) / Double(store.count(.applied)) * 100))%")
                        .font(.caption.weight(.bold)).foregroundStyle(Palette.chip(.good))
                }
            }
        }
        .card()
    }

    private func pipeRow(_ label: String, _ n: Int, _ color: Color) -> some View {
        let maxN = max(store.count(.all), 1)
        return HStack(spacing: 12) {
            Text("\(n)").font(.system(size: 18, weight: .bold, design: .rounded)).frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 12.5, weight: .medium))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(color).frame(width: max(4, g.size.width * CGFloat(n) / CGFloat(maxN)))
                    }
                }.frame(height: 5)
            }
        }
    }

    private var weeklyChartCard: some View {
        let data = store.weeklyNewMatches()
        let maxV = max(data.map(\.count).max() ?? 1, 1)
        let total = data.map(\.count).reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "New matches / week")
                    Text("Last 7 days of scans").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(total) total").font(.caption.weight(.semibold)).foregroundStyle(Palette.chip(.good))
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.accentGradient)
                            .frame(height: max(4, 70 * CGFloat(d.count) / CGFloat(maxV)))
                        Text(d.label).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 92, alignment: .bottom)
        }
        .card()
    }

    // MARK: bottom row (response timeline + right column of interviews/market/follow-ups)
    @ViewBuilder private var bottomRow: some View {
        let showInterviews = store.gmailConfigured() && !store.interviewingJobs.isEmpty
        let showMarket = store.marketBand != nil
        let showFollowUps = !store.followUpsDue.isEmpty
        let hasSide = showInterviews || showMarket || showFollowUps
        if !store.responses.isEmpty || hasSide {
            HStack(alignment: .top, spacing: 16) {
                if !store.responses.isEmpty { responseTimelineCard.frame(maxWidth: .infinity) }
                if hasSide {
                    VStack(spacing: 16) {
                        if showFollowUps { followUpsCard }
                        if showInterviews { upcomingInterviewsCard }
                        if showMarket { marketInsightCard }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var responseTimelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Response timeline")
                Spacer()
                Button("View all") { onNavigate(.inbox) }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.brand1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach(store.responses.prefix(6)) { job in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(stageColor(job.appliedStage)).frame(width: 8, height: 8).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.appliedStage.label.uppercased()).font(.system(size: 9, weight: .bold))
                                .foregroundStyle(stageColor(job.appliedStage))
                            Text(job.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(job.company + (job.appliedDate.map { " · \($0)" } ?? "")).font(.caption2)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .card()
    }

    private func stageColor(_ s: AppliedStage) -> Color {
        switch s {
        case .offer: return Palette.chip(.good)
        case .rejected: return Palette.chip(.bad)
        case .interviewing: return Palette.brand2
        default: return Palette.brand1
        }
    }

    private var followUpsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SectionLabel(text: "Follow-ups due")
                Spacer()
                Text("\(store.followUpsDue.count)").font(.caption.weight(.bold)).foregroundStyle(Palette.brand1)
            }
            ForEach(store.followUpsDue.prefix(4)) { job in
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill").font(.caption2).foregroundStyle(Palette.chip(.warn))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(job.company).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let d = job.followUpDate { Text(d).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
        .card()
    }

    // Only reachable when Gmail is connected (see bottomRow) - never an empty frame.
    private var upcomingInterviewsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(text: "Upcoming interviews")
            ForEach(store.interviewingJobs.prefix(4)) { job in
                HStack(spacing: 11) {
                    VStack(spacing: 0) {
                        Text(job.interviewDate.map { String($0.suffix(5)) } ?? "TBD")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.brand2)
                    }
                    .frame(width: 46, height: 34)
                    .background(Palette.brand2.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(job.company).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .card()
    }

    // Only shown when marketBand has enough salary signal (see bottomRow).
    private var marketInsightCard: some View {
        Group {
            if let b = store.marketBand {
                let span = max(b.high - b.low, 1)
                let frac = b.target > 0 ? min(max(Double(b.target - b.low) / Double(span), 0), 1) : 0.5
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Market insight")
                    Text("Roles matching your profile").font(.caption2).foregroundStyle(.tertiary)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.accentGradient.opacity(0.35)).frame(height: 6).offset(y: 7)
                            Circle().fill(Palette.brand1).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(.white.opacity(0.6)))
                                .offset(x: max(0, g.size.width * CGFloat(frac) - 6), y: 4)
                        }
                    }.frame(height: 20)
                    HStack {
                        Text("$\(b.low)k").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(b.target > 0 ? "target $\(b.target)k" : "set a target in Eligibility")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Palette.brand1)
                        Spacer()
                        Text("$\(b.high)k").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .card()
            }
        }
    }
}
