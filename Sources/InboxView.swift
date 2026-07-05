import SwiftUI

@MainActor
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @State private var appPassword = ""
    @State private var testing = false
    @State private var testMsg: String?
    @State private var testOK = false

    var body: some View {
        @Bindable var settings = store.settings
        SplitScaffold("Inbox", subtitle: "Auto-detect application status from your Gmail",
                      icon: "envelope", rightWidth: 340) {
            // MARK: left - connection + setup
            SettingsGroup("Gmail connection", icon: "envelope.badge.shield.half.filled") {
                HStack {
                    Text(store.gmailConfigured() ? "Connected" : "Not connected")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(store.gmailConfigured() ? .green : .secondary)
                    Spacer()
                    Toggle("", isOn: $settings.gmailEnabled).labelsHidden().tint(Palette.brand1)
                }
                .padding(.bottom, 4)

                TextField("you@gmail.com", text: $settings.gmailAddress).textFieldStyle(.roundedBorder)
                SecureField("App Password (16 characters)", text: $appPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appPassword) {
                        let a = appPassword.replacingOccurrences(of: " ", with: "")
                        if a.isEmpty { Keychain.delete(AppStore.gmailAccount) } else { Keychain.set(a, account: AppStore.gmailAccount) }
                    }

                HStack(spacing: 9) {
                    Button {
                        testing = true; testMsg = nil
                        let email = settings.gmailAddress
                        let pass = appPassword.replacingOccurrences(of: " ", with: "")
                        Task {
                            let r = await Task.detached { GmailService.testConnection(email: email, appPassword: pass) }.value
                            switch r {
                            case .success(let n): testOK = true; testMsg = "Connected · \(n) messages in inbox"
                            case .failure(let e): testOK = false; testMsg = e.localizedDescription
                            }
                            testing = false
                        }
                    } label: { Label("Test connection", systemImage: "bolt.fill") }
                    .buttonStyle(.bordered)
                    .disabled(testing || settings.gmailAddress.isEmpty || appPassword.isEmpty)
                    if testing { ProgressView().controlSize(.small) }
                    Spacer()
                }
                .padding(.top, 2)
                if let m = testMsg {
                    Label(m, systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testOK ? .green : .red).font(.caption)
                }
            }

            SettingsGroup("One-time setup", icon: "list.number") {
                step("1", "Turn on 2-Step Verification for your Google account.")
                step("2", "Create an App Password and paste it above.")
                step("3", "Enable IMAP in Gmail > Settings > Forwarding and POP/IMAP.")
                Link(destination: URL(string: "https://myaccount.google.com/apppasswords")!) {
                    Label("Open Google App Passwords", systemImage: "arrow.up.right.square")
                }.font(.caption).padding(.top, 2)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("Read-only. Your App Password is stored in the macOS Keychain and passed to curl via a private 0600 file, never on the command line. Mail is read directly from Gmail over an encrypted connection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        } right: {
            // MARK: right - status + detected responses
            PanelCard("Sync status", icon: "arrow.triangle.2.circlepath") {
                HStack(spacing: 9) {
                    Circle().fill(store.gmailConfigured() ? Palette.chip(.good) : Palette.chip(.warn))
                        .frame(width: 10, height: 10)
                        .shadow(color: (store.gmailConfigured() ? Palette.chip(.good) : Palette.chip(.warn)).opacity(0.8), radius: 5)
                    Text(store.gmailConfigured() ? "Connected" : "Not connected")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(store.gmailConfigured() ? Palette.chip(.good) : Palette.chip(.warn))
                    Spacer(minLength: 0)
                }
                Button { Task { await store.syncInbox() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(store.inboxSyncing ? "Syncing…" : "Sync now")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(store.inboxSyncing || !store.gmailConfigured())
                if !store.lastInboxSync.isEmpty {
                    Text("Last synced · \(store.lastInboxSync)").font(.caption2).foregroundStyle(.secondary)
                }
            }

            PanelCard("Detected responses", icon: "tray.and.arrow.down") {
                if store.responses.isEmpty {
                    Text(store.gmailConfigured()
                         ? "No interview / offer / rejection signals yet. Apply to roles, then Sync."
                         : "Connect Gmail to auto-detect replies.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.responses) { job in
                        HStack(spacing: 10) {
                            Badge(text: job.appliedStage.label, color: stageColor(job.appliedStage))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                Text(job.company).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .onAppear { appPassword = Keychain.get(AppStore.gmailAccount) ?? "" }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.caption2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Palette.brand1, in: Circle())
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
    private func stageColor(_ s: AppliedStage) -> Color {
        switch s {
        case .offer: return Palette.chip(.good)
        case .interviewing: return Palette.brand1
        case .rejected: return Palette.chip(.bad)
        default: return .secondary
        }
    }
}
