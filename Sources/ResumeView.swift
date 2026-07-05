import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
struct ResumeView: View {
    @Environment(AppStore.self) private var store
    @State private var analyzing = false

    var body: some View {
        let hasResume = !store.resumeText.isEmpty
        let p = store.profile
        let analyzed = !p.summary.isEmpty || !p.skills.isEmpty

        return SplitScaffold("Resume", subtitle: "Drives keyword matching and AI fit scoring - stays on this Mac",
                             icon: "doc.text", rightWidth: 300) {
            // MARK: left - the profile canvas (the star; fills the width)
            if analyzed {
                if !p.level.isEmpty {
                    HStack(spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.brand1.opacity(0.16))
                            Image(systemName: "target").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Palette.accentGradient)
                        }.frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel(text: "Target level")
                            Text(p.level).font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Palette.accentGradient)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 16)
                }
                if !p.summary.isEmpty {
                    SettingsGroup("Summary", icon: "text.alignleft") {
                        Text(p.summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !p.targetTitles.isEmpty {
                    SettingsGroup("Target titles", icon: "briefcase") {
                        FlowLayout(spacing: 7) { ForEach(p.targetTitles, id: \.self) { TagView(text: $0) } }
                    }
                }
                if !p.skills.isEmpty {
                    SettingsGroup("Core skills", icon: "star") {
                        FlowLayout(spacing: 7) { ForEach(p.skills, id: \.self) { TagView(text: $0) } }
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: hasResume ? "wand.and.stars" : "doc.text")
                        .font(.system(size: 46)).foregroundStyle(Palette.accentGradient)
                    Text(hasResume ? "Analyze to build your profile" : "No resume yet")
                        .font(.title3.bold())
                    Text(hasResume
                         ? "Hit \"Analyze with AI\" on the right to extract your target level, titles, and skills - this is what makes matches relevant to you."
                         : "Import a PDF or text file on the right. It stays on this Mac and drives every match.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
                .card(padding: 28)
            }
        } right: {
            // MARK: right rail - actions + status + explainer
            PanelCard("Resume file", icon: "doc") {
                if hasResume {
                    Label("\(store.resumeText.count.formatted()) characters loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Palette.chip(.good))
                }
                Button { importResume() } label: {
                    Label(hasResume ? "Replace resume" : "Import resume", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(GradientButtonStyle())
                if hasResume {
                    Button {
                        analyzing = true
                        Task { await store.analyzeResume(); analyzing = false }
                    } label: {
                        HStack(spacing: 6) {
                            if analyzing { ProgressView().controlSize(.small) }
                            Label(analyzed ? "Re-analyze with AI" : "Analyze with AI", systemImage: "wand.and.stars")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).disabled(analyzing)
                }
            }

            PanelCard("How scoring uses it", icon: "sparkles") {
                bullet("Free keyword pass ranks every posting against your titles, seniority, and skills.")
                bullet("Analyzing adapts matching to any career, not just one field.")
                bullet("Top matches are then deep-scored for genuine fit (if AI is on).")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                .foregroundStyle(Palette.chip(.good)).padding(.top, 2)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func importResume() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            var text = ""
            if url.pathExtension.lowercased() == "pdf" {
                if let doc = PDFDocument(url: url) { text = doc.string ?? "" }
            } else {
                text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            if text.isEmpty { store.toast = "Couldn't read text from that file." }
            else { store.setResume(text: text) }
        }
    }
}
