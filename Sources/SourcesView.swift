import SwiftUI

struct SourcesView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var query = ""

    var body: some View {
        SplitScaffold("Sources", subtitle: "\(store.companies.count) companies · \(enabledCount) enabled",
                      icon: "building.2", rightWidth: 300) {
            // MARK: left - search + grouped company list (fills the width)
            searchBar
            ForEach(ATSKind.sources) { kind in
                let items = filtered.filter { $0.ats == kind }
                if !items.isEmpty { groupSection(kind, items) }
            }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("No companies match \u{201C}\(query)\u{201D}.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 50)
            }
        } right: {
            // MARK: right - live source mix + add
            sourceMixPanel
        }
        .sheet(isPresented: $showAdd) { AddCompanySheet() }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Search companies", text: $query).textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var sourceMixPanel: some View {
        let maxCount = max(ATSKind.sources.map { k in store.companies.filter { $0.ats == k }.count }.max() ?? 1, 1)
        return VStack(spacing: 16) {
            PanelCard("Source mix", icon: "chart.bar.xaxis") {
                ForEach(ATSKind.sources) { kind in
                    let items = store.companies.filter { $0.ats == kind }
                    let on = items.filter { $0.enabled }.count
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Circle().fill(Self.atsColor(kind)).frame(width: 8, height: 8)
                            Text(kind.label).font(.system(size: 12.5, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("\(on)/\(items.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                            Capsule().fill(Self.atsColor(kind))
                                .frame(width: max(6, 240 * CGFloat(items.count) / CGFloat(maxCount)), height: 6)
                        }
                    }
                    .padding(.vertical, 3)
                }
                Divider().opacity(0.4)
                HStack {
                    Text("Enabled").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(enabledCount) of \(store.companies.count)").font(.caption.weight(.semibold))
                }
            }
            PanelCard("Add a source", icon: "plus.circle") {
                Text("A token is the slug in a company's careers URL (e.g. boards.greenhouse.io/**stripe**).")
                    .font(.caption).foregroundStyle(.secondary)
                Button { showAdd = true } label: {
                    Label("Add company", systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(GradientButtonStyle())
            }
        }
    }

    private func groupSection(_ kind: ATSKind, _ items: [Company]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(Self.atsColor(kind)).frame(width: 9, height: 9)
                    .shadow(color: Self.atsColor(kind).opacity(0.6), radius: 3)
                Text(kind.label).font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                Spacer()
                let on = items.filter { $0.enabled }.count
                Text("\(on) on").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.leading, 3)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                    CompanyRow(company: c, color: Self.atsColor(kind))
                    if idx < items.count - 1 { Divider().padding(.leading, 54).opacity(0.5) }
                }
            }
            .card(padding: 0)
        }
    }

    private var filtered: [Company] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.companies }
        return store.companies.filter { $0.name.lowercased().contains(q) || $0.token.lowercased().contains(q) }
    }
    private var enabledCount: Int { store.companies.filter { $0.enabled }.count }

    static func atsColor(_ k: ATSKind) -> Color {
        switch k {
        case .greenhouse:      return Color(red: 0.16, green: 0.73, blue: 0.45)
        case .ashby:           return Palette.brand2
        case .lever:           return Color(red: 0.95, green: 0.58, blue: 0.20)
        case .smartrecruiters: return Color(red: 0.30, green: 0.60, blue: 0.98)
        case .manual:          return .gray
        }
    }
}

// MARK: - Company row

struct CompanyRow: View {
    let company: Company
    let color: Color
    @Environment(AppStore.self) private var store
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.16))
                Text(String(company.name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(color)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(company.name).font(.system(size: 13.5, weight: .medium))
                Text(company.token).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Badge(text: company.tier.label, color: Palette.tierColor(company.tier == .startup))
            Toggle("", isOn: Binding(get: { company.enabled }, set: { _ in store.toggleCompany(company) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button(role: .destructive) { store.deleteCompany(company) } label: {
                Image(systemName: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .opacity(hover ? 1 : 0.001)
            .help("Remove \(company.name)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(hover ? Color.primary.opacity(0.045) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

// MARK: - Add company

struct AddCompanySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ats: ATSKind = .greenhouse
    @State private var token = ""
    @State private var tier: Tier = .startup

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add company").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                Picker("ATS", selection: $ats) { ForEach(ATSKind.sources) { Text($0.label).tag($0) } }
                TextField("Token (careers URL slug)", text: $token)
                    .font(.system(.body, design: .monospaced))
                Picker("Tier", selection: $tier) { ForEach(Tier.allCases) { Text($0.label).tag($0) } }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    store.addCompany(name: name.trimmingCharacters(in: .whitespaces),
                                     ats: ats, token: token.trimmingCharacters(in: .whitespaces), tier: tier)
                    dismiss()
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(name.isEmpty || token.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}
