import SwiftUI

// MARK: - CoachingView (trainer arm T1)
//
// The relationship + consent surface, both sides on one screen:
//   AS A CLIENT — who coaches you, exactly what they can see (the scope
//   toggles, live-editable), and the End button. No invisible watching.
//   AS A TRAINER — your active clients, pending invite codes to share,
//   and MINT INVITE. The TRAINER tab with client widgets is T4; this is
//   the plumbing made visible.
struct CoachingView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var relationships: [TrainerClient] = []
    @State private var profilesByID: [UUID: Profile] = [:]
    @State private var loading = true
    @State private var errorText: String?
    @State private var redeemCode = ""
    @State private var redeemScopes = TrainerScopes(history: true, stats: true,
                                                   bodyWeight: false, calendar: true)
    @State private var busy = false

    private var selfID: UUID? { appState.currentProfile?.id }

    private var myTrainers: [TrainerClient] {
        relationships.filter { $0.clientID == selfID && $0.status == "active" }
    }
    private var myClients: [TrainerClient] {
        relationships.filter { $0.trainerID == selfID && $0.status == "active" }
    }
    private var myPendingInvites: [TrainerClient] {
        relationships.filter { $0.trainerID == selfID && $0.status == "invited" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading && relationships.isEmpty {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 40)
                } else {
                    coachedBySection
                    redeemSection
                    clientsSection
                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Coaching")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - As a client

    private var coachedBySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Coached by")
            if myTrainers.isEmpty {
                Text("Nobody — your training is yours alone until you redeem a trainer's code below.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                ForEach(myTrainers) { rel in
                    trainerCard(rel)
                }
            }
        }
    }

    private func trainerCard(_ rel: TrainerClient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name(for: rel.trainerID))
                    .font(GSFont.bold(15, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Spacer()
                Button("End", role: .destructive) {
                    Task { await end(rel) }
                }
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .tint(.red)
            }
            Text("They can see exactly what's on below — change it any time.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
            scopeToggles(rel)
        }
        .padding(12)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    private func scopeToggles(_ rel: TrainerClient) -> some View {
        VStack(spacing: 6) {
            scopeRow("Session history", value: rel.scopes.history) { on in
                var s = rel.scopes; s.history = on
                Task { await update(rel, scopes: s) }
            }
            scopeRow("Stats & trends", value: rel.scopes.stats) { on in
                var s = rel.scopes; s.stats = on
                Task { await update(rel, scopes: s) }
            }
            scopeRow("Body weight", value: rel.scopes.bodyWeight) { on in
                var s = rel.scopes; s.bodyWeight = on
                Task { await update(rel, scopes: s) }
            }
            scopeRow("Calendar", value: rel.scopes.calendar) { on in
                var s = rel.scopes; s.calendar = on
                Task { await update(rel, scopes: s) }
            }
        }
    }

    private func scopeRow(_ label: String, value: Bool,
                          onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label)
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: onChange))
                .labelsHidden()
                .tint(theme.accent)
        }
    }

    // MARK: - Redeem

    private var redeemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Have a trainer's code?")
            VStack(alignment: .leading, spacing: 10) {
                TextField("Invite code", text: $redeemCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(GSFont.heading(16, relativeTo: .body).monospaced())
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.divider, lineWidth: 1))
                Text("You choose what they see — starting scopes below, adjustable after.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                scopeRow("Session history", value: redeemScopes.history) { redeemScopes.history = $0 }
                scopeRow("Stats & trends", value: redeemScopes.stats) { redeemScopes.stats = $0 }
                scopeRow("Body weight", value: redeemScopes.bodyWeight) { redeemScopes.bodyWeight = $0 }
                scopeRow("Calendar", value: redeemScopes.calendar) { redeemScopes.calendar = $0 }
                Button {
                    Task { await redeem() }
                } label: {
                    Text("Accept coaching")
                }
                .buttonStyle(GSSecondaryButtonStyle())
                .disabled(busy || redeemCode.trimmingCharacters(in: .whitespaces).count < 6)
            }
            .padding(12)
            .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        }
    }

    // MARK: - As a trainer

    private var clientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Your clients")
            ForEach(myClients) { rel in
                HStack {
                    Text(name(for: rel.clientID ?? rel.trainerID))
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(scopeSummary(rel.scopes))
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    Button("End", role: .destructive) {
                        Task { await end(rel) }
                    }
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .tint(.red)
                }
                .padding(12)
                .gs3DCard(cornerRadius: GSMetrics.radiusMd)
            }
            ForEach(myPendingInvites) { rel in
                HStack {
                    Text(rel.inviteCode ?? "—")
                        .font(GSFont.heading(16, relativeTo: .body).monospaced())
                        .foregroundStyle(theme.accent)
                    Text("share this code")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    Spacer()
                    Button("Revoke") {
                        Task { await revoke(rel) }
                    }
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                }
                .padding(12)
                .gs3DCard(cornerRadius: GSMetrics.radiusMd)
            }
            Button {
                Task { await mintInvite() }
            } label: {
                Text("+ Invite a client")
            }
            .buttonStyle(GSSecondaryButtonStyle())
            .disabled(busy)
        }
    }

    private func scopeSummary(_ scopes: TrainerScopes) -> String {
        let granted = [scopes.history ? "history" : nil,
                       scopes.stats ? "stats" : nil,
                       scopes.bodyWeight ? "weight" : nil,
                       scopes.calendar ? "calendar" : nil].compactMap { $0 }
        return granted.isEmpty ? "nothing shared yet" : granted.joined(separator: " · ")
    }

    private func name(for id: UUID) -> String {
        profilesByID[id].map { $0.displayName?.isEmpty == false ? $0.displayName! : $0.username }
            ?? "Lifter"
    }

    // MARK: - Actions

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let rows = try await TrainerClientRepository.mine()
            relationships = rows
            // Keep the TRAINER tab gate live (owner report 2026-08-16: tab
            // invisible after minting): MainTabView only evaluates it at
            // launch, so minting your FIRST invite here must inject the tab
            // now — not after an app restart. Same predicate as launch.
            if let me = selfID {
                appState.isTrainer = rows.contains { $0.trainerID == me && $0.status != "ended" }
            }
            let ids = Set(rows.flatMap { [$0.trainerID, $0.clientID].compactMap { $0 } })
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

    @MainActor
    private func redeem() async {
        busy = true; defer { busy = false }
        do {
            try await TrainerClientRepository.redeem(
                code: redeemCode.trimmingCharacters(in: .whitespaces),
                scopes: redeemScopes)
            redeemCode = ""
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func update(_ rel: TrainerClient, scopes: TrainerScopes) async {
        do {
            try await TrainerClientRepository.updateScopes(id: rel.id, scopes: scopes)
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func end(_ rel: TrainerClient) async {
        do {
            try await TrainerClientRepository.end(id: rel.id)
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func revoke(_ rel: TrainerClient) async {
        do {
            try await TrainerClientRepository.revokeInvite(id: rel.id)
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
