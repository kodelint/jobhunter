import SwiftUI
import AppKit

@MainActor
struct MenuBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("JobHunter", systemImage: "target").font(.headline)
                Spacer()
                if store.scan.running { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 0) {
                stat("\(store.count(.new))", "New")
                Divider().frame(height: 30)
                stat("\(store.count(.all))", "Matches")
                Divider().frame(height: 30)
                stat("\(store.count(.applied))", "Applied")
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            let top = Array(store.filtered(.new).prefix(3))
            if !top.isEmpty {
                Text("TOP NEW FITS").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
                ForEach(top) { job in
                    HStack(spacing: 9) {
                        ScoreBadge(score: job.effectiveScore)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(job.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text(job.company).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                Text(store.lastScan.isEmpty ? "No scans yet." : "No new roles right now.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button {
                    Task { await store.scanNow() }
                } label: { Label("Scan now", systemImage: "arrow.clockwise") }
                .disabled(store.scan.running)
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Label("Open", systemImage: "macwindow") }
            }
            if !store.lastScan.isEmpty {
                Text("Last scan · \(store.lastScan)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
