import SwiftUI

enum AppVersion {
    static var short: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty, v != "__VERSION__" {
            return v
        }
        return "1.1.0"
    }

    static var build: String {
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !b.isEmpty, b != "__BUILD__" {
            return b
        }
        return "1"
    }

    static var sidebarLabel: String {
        "v\(short) · build \(build)"
    }
}

enum SidebarItem: Hashable {
    case dashboard, jobs(JobTab), sources, resume, eligibility, inbox, ai
}

@MainActor
struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: SidebarItem = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            main
        }
        .frame(minWidth: 1060, minHeight: 720)
        .background(Palette.appBackground)
        .preferredColorScheme(.dark)
        .task { await backgroundLoop() }
        .onChange(of: store.settings.eligibility) { store.refreshStats() }
        .overlay(alignment: .bottom) { toast }
    }

    // MARK: sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    navRow(.dashboard, "Dashboard", "square.grid.2x2.fill", nil)
                    SectionLabel(text: "Jobs").padding(.leading, 12).padding(.bottom, 4).padding(.top, 14)
                    navRow(.jobs(.new), "New", "sparkles", store.count(.new))
                    navRow(.jobs(.all), "All matches", "square.stack.3d.up", store.count(.all))
                    navRow(.jobs(.low), "Low matches", "arrow.down.circle", store.count(.low))
                    navRow(.jobs(.favorites), "Favorites", "star.fill", store.count(.favorites))
                    navRow(.jobs(.applied), "Applied", "checkmark.seal", store.count(.applied))
                    navRow(.jobs(.ignored), "Ignored", "archivebox", store.count(.ignored))
                    navRow(.jobs(.wrong), "Wrong matches", "exclamationmark.triangle", store.count(.wrong))
                    SectionLabel(text: "Setup").padding(.leading, 12).padding(.bottom, 4).padding(.top, 16)
                    navRow(.sources, "Sources", "building.2", store.companies.count)
                    navRow(.resume, "Resume", "doc.text", nil)
                    navRow(.eligibility, "Eligibility", "checkmark.shield", nil)
                    navRow(.inbox, "Inbox", "envelope", store.responsesCount)
                    navRow(.ai, "AI & Settings", "wand.and.stars", nil)
                }
                .padding(.horizontal, 10)
            }
            scanFooter
        }
        .frame(width: 240)
        .background(Palette.sidebarGradient)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1) }
        .environment(\.colorScheme, .dark)
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().stroke(Palette.accentGradient, lineWidth: 3).frame(width: 26, height: 26)
                Circle().fill(Palette.accentGradient).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("JobHunter").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text(AppVersion.sidebarLabel).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 36).padding(.bottom, 16)
    }

    private func navRow(_ item: SidebarItem, _ title: String, _ icon: String, _ count: Int?) -> some View {
        let selected = selection == item
        return Button {
            withAnimation(.snappy(duration: 0.18)) { selection = item }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 20)
                    .foregroundStyle(selected ? AnyShapeStyle(Palette.accentGradient) : AnyShapeStyle(Color.white.opacity(0.72)))
                Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .white : Color.white.opacity(0.82))
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selected ? .white : Color.white.opacity(0.6))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.white.opacity(selected ? 0.20 : 0.09), in: Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white.opacity(selected ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.accentGradient).frame(width: 3, height: 18).offset(x: -2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var boostCard: some View {
        Button { withAnimation(.snappy(duration: 0.18)) { selection = .resume } } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                    Text("Boost your chances").font(.system(size: 12.5, weight: .semibold))
                }.foregroundStyle(.white)
                Text("Get AI feedback to sharpen your resume for top roles.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text("Review resume").font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.white.opacity(0.14), in: Capsule())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(
                LinearGradient(colors: [Palette.brand1.opacity(0.30), Palette.brand2.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.13)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scanFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            boostCard
            if store.scan.running {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.scan.phase).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    ProgressView(value: store.scan.fraction).tint(Palette.brand1).controlSize(.small)
                }
            }
            Button { Task { await store.scanNow() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: store.scan.running ? "hourglass" : "sparkles")
                    Text(store.scan.running ? "Scanning…" : "Scan new jobs")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(store.scan.running)
            Text(store.lastScan.isEmpty ? "Not scanned yet" : "Last scan · \(store.lastScan)")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
    }

    // MARK: main
    private var main: some View {
        Group {
            switch selection {
            case .dashboard: DashboardView(onNavigate: { item in withAnimation(.snappy(duration: 0.18)) { selection = item } })
            case .jobs(let tab): JobsView(tab: tab)
            case .sources: SourcesView()
            case .resume: ResumeView()
            case .eligibility: EligibilityView()
            case .inbox: InboxView()
            case .ai: AISettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.appBackground)
                RadialGradient(colors: [Palette.brand1.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 620)
                RadialGradient(colors: [Palette.brand2.opacity(0.06), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var toast: some View {
        if let t = store.toast {
            Text(t)
                .font(.callout)
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(radius: 12, y: 4)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { store.toast = nil }
                .task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    store.toast = nil
                }
        }
    }

    private func backgroundLoop() async {
        while !Task.isCancelled {
            let hrs = max(store.settings.scanIntervalHours, 1)
            try? await Task.sleep(nanoseconds: UInt64(hrs) * 3_600 * 1_000_000_000)
            if !store.scan.running { await store.scanNow() }
        }
    }
}
