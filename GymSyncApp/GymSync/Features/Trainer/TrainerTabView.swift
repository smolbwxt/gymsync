import SwiftUI

// MARK: - TrainerTabView (trainer arm T3)
//
// The TRAINER tab root: the client roster as wide extruded widgets (the
// Crews-tab language), pending invite codes, and MINT INVITE. Appears
// only for accounts that coach (AppState.isTrainer). Tap a client →
// ClientDetailView, the assess/manage/prescribe command center.
struct TrainerTabView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var relationships: [TrainerClient] = []
    @State private var profilesByID: [UUID: Profile] = [:]
    @State private var loading = true
    @State private var errorText: String?
    @State private var busy = false

    private var selfID: UUID? { appState.currentProfile?.id }
    private var activeClients: [TrainerClient] {
        relationships.filter { $0.trainerID == selfID && $0.status == "active" }
    }
    private var pendingInvites: [TrainerClient] {
        relationships.filter { $0.trainerID == selfID && $0.status == "invited" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Trainer")
                        .font(GSFont.heading(24, relativeTo: .title))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    GSSectionHeader("Your clients")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    if loading && relationships.isEmpty {
                        HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                            .padding(.top, 30)
                    } else if activeClients.isEmpty {
                        GSEmptyState(
                            icon: "figure.strengthtraining.traditional",
                            title: "No clients yet",
                            message: "Mint an invite code below and share it — your client accepts and chooses what you can see.",
                            ctaTitle: "+ Invite a client",
                            action: { Task { await mintInvite() } }
                        )
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(activeClients) { rel in
                                clientWidget(rel)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if !pendingInvites.isEmpty {
                        GSSectionHeader("Open invite codes")
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        VStack(spacing: 8) {
                            ForEach(pendingInvites) { rel in
                                inviteRow(rel)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if !activeClients.isEmpty {
                        Button {
                            Task { await mintInvite() }
                        } label: {
                            Text("+ Invite a client")
                        }
                        .buttonStyle(GSSecondaryButtonStyle())
                        .disabled(busy)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }
                    Spacer(minLength: 24)
                }
            }
            .contentMargins(.bottom, 88, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                // Launch-readiness accounting (RootView's overlay hold).
                appState.beginLaunchFetch()
                await load()
                appState.endLaunchFetch()
            }
            .refreshable { await load() }
        }
    }

    private func clientWidget(_ rel: TrainerClient) -> some View {
        NavigationLink {
            ClientDetailView(relationship: rel,
                             clientProfile: rel.clientID.flatMap { profilesByID[$0] })
        } label: {
            HStack(spacing: 12) {
                GSInitialsAvatar(
                    name: clientName(rel),
                    avatarURL: rel.clientID.flatMap { profilesByID[$0]?.avatarURL },
                    size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clientName(rel))
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text(scopeSummary(rel.scopes))
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
    }

    private func inviteRow(_ rel: TrainerClient) -> some View {
        HStack {
            Text(rel.inviteCode ?? "—")
                .font(GSFont.heading(16, relativeTo: .body).monospaced())
                .foregroundStyle(theme.accent)
            Text("share this code")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
            Spacer()
            Button("Revoke") {
                Task {
                    try? await TrainerClientRepository.revokeInvite(id: rel.id)
                    await load()
                }
            }
            .font(GSFont.bold(12, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)
        }
        .padding(12)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    private func clientName(_ rel: TrainerClient) -> String {
        guard let id = rel.clientID, let profile = profilesByID[id] else { return "Lifter" }
        return profile.displayName?.isEmpty == false ? profile.displayName! : profile.username
    }

    private func scopeSummary(_ scopes: TrainerScopes) -> String {
        let granted = [scopes.history ? "history" : nil,
                       scopes.stats ? "stats" : nil,
                       scopes.bodyWeight ? "weight" : nil,
                       scopes.calendar ? "calendar" : nil].compactMap { $0 }
        return granted.isEmpty ? "prescriptions only" : granted.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let rows = try await TrainerClientRepository.mine()
            relationships = rows
            let me = selfID
            appState.isTrainer = rows.contains { $0.trainerID == me && $0.status != "ended" }
            let ids = Set(rows.compactMap(\.clientID))
            let profiles = (try? await ProfileRepository.fetchMany(ids: Array(ids))) ?? []
            profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            errorText = nil
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func mintInvite() async {
        busy = true; defer { busy = false }
        do {
            _ = try await TrainerClientRepository.createInvite()
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
