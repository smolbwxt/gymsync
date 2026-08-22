import SwiftUI

// MARK: - Coach debrief surfaces (concept 2026-08-20, build 2026-08-21)
//
// The free card renders the computed headline for EVERYONE — specific
// beats generic, and a computed fact proves Coach was watching. Its last
// line is the invitation; the tap is where the conversation begins.
// One data pipeline (WorkoutDebrief) under both tiers, so the card can
// never contradict the coach.

struct CoachDebriefCard: View {
    let debrief: WorkoutDebrief
    let coachName: String
    let onTalk: () -> Void
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(coachName.uppercased())
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .tracking(1.0)
                    .foregroundStyle(theme.text.opacity(0.78))
                Spacer()
            }
            // Safety lines FIRST, plainly, in every tier — never behind
            // a model, never behind a paywall.
            ForEach(debrief.safetyNotes, id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent700)
                    Text(note)
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(debrief.headline)
                .font(GSFont.bold(15, relativeTo: .body))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onTalk) {
                HStack(spacing: 6) {
                    Text("TALK IT THROUGH")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .tracking(0.8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - The recap conversation

/// The AI recap: a conversation with the coach over the session's
/// computed payload. Devices without the on-device model get the
/// structured report — the same facts, no chat — because the
/// subscription sells the RELATIONSHIP, and the conversation is one
/// expression of it where hardware allows.
struct CoachRecapView: View {
    /// The apply writer (owner 2026-08-22): fuzzy-matches the exercise,
    /// writes the routine, returns a confirmation line - or nil when
    /// nothing matched / the write failed. Nil closure = no edit tool
    /// (group recaps, trainer prescriptions).
    var applyRoutineEdit: ((RoutineEditProposal) async -> String?)? = nil
    @State private var pendingEdit: RoutineEditProposal?
    @State private var applyingEdit = false
    let debrief: WorkoutDebrief
    let persona: CoachPersona?
    let profile: TrainingProfile
    /// Tool backends — computed sentences from the tested builders.
    let trendLookup: @Sendable (String) -> String
    let volumeLookup: @Sendable () -> String

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private struct Turn: Identifiable {
        let id = UUID()
        let isCoach: Bool
        let text: String
    }
    @State private var turns: [Turn] = []
    @State private var draft = ""
    @State private var thinking = false

    private var coachName: String { persona?.name ?? "Coach" }

    var body: some View {
        VStack(spacing: 0) {
            header
            if CoachDebrief.isConversationAvailable {
                conversation
            } else {
                reportCard
            }
        }
        .background(theme.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(coachName.uppercased())
                    .font(GSFont.bold(15, relativeTo: .body))
                    .tracking(0.8)
                    .foregroundStyle(theme.text)
                Text(persona?.tagline ?? "Read the log. Says what matters.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.neutral500)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    // MARK: Structured report (every device, every OS)

    private var reportCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(debrief.safetyNotes, id: \.self) { note in
                    label(icon: "exclamationmark.triangle.fill", text: note,
                          tint: theme.accent700)
                }
                Text(debrief.headline)
                    .font(GSFont.bold(17, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                // The payload IS the report — the same lines the model
                // would narrate, shown raw for the curious.
                ForEach(debrief.corePrompt.split(separator: "\n").dropFirst()
                    .map(String.init), id: \.self) { line in
                    Text(line)
                        .font(GSFont.body(12, relativeTo: .caption).monospaced())
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The back-and-forth version of this recap needs Apple Intelligence (iOS 26+). Every number above is computed from your log either way.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private func label(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(GSFont.body(13, relativeTo: .body))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Live conversation (Apple Intelligence devices)

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(turns) { turn in
                        bubble(turn)
                    }
                    if thinking {
                        Text("…")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .foregroundStyle(theme.neutral500)
                            .padding(.horizontal, 14)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let proposal = pendingEdit {
                // The Apply card (owner 2026-08-22): Coach proposed, the
                // athlete decides - #38's no-silent-tweaks, kept even
                // for Coach's own suggestions.
                VStack(alignment: .leading, spacing: 6) {
                    Text("COACH PROPOSES · \(proposal.exerciseName.uppercased())")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.accent)
                    Text(proposalSummary(proposal))
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text(proposal.reason)
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            guard !applyingEdit, let apply = applyRoutineEdit else { return }
                            applyingEdit = true
                            Task {
                                defer { applyingEdit = false }
                                if let confirmation = await apply(proposal) {
                                    turns.append(Turn(isCoach: true, text: confirmation))
                                } else {
                                    turns.append(Turn(isCoach: true,
                                        text: "I couldn't find that exercise in the routine to edit — the numbers stand as they were."))
                                }
                                pendingEdit = nil
                            }
                        } label: {
                            Text(applyingEdit ? "APPLYING…" : "APPLY")
                                .font(GSFont.bold(11, relativeTo: .caption2))
                                .tracking(0.6)
                                .foregroundStyle(theme.bg)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(theme.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            pendingEdit = nil
                            turns.append(Turn(isCoach: true,
                                text: "No problem — the routine stays as written."))
                        } label: {
                            Text("NOT NOW")
                                .font(GSFont.bold(11, relativeTo: .caption2))
                                .tracking(0.6)
                                .foregroundStyle(theme.neutral700)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                TextField("Ask your coach…", text: $draft, axis: .vertical)
                    .font(GSFont.body(14, relativeTo: .body))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(draft.isEmpty ? theme.neutral500 : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty || thinking)
            }
            .padding(12)
        }
        .task { await open() }
    }

    private func proposalSummary(_ p: RoutineEditProposal) -> String {
        var parts: [String] = []
        if let w = p.weight { parts.append("\(Int(w.rounded())) \(ThemeStore.shared.weightUnit.label)") }
        if let lo = p.repsLow, let hi = p.repsHigh { parts.append("\(lo)–\(hi) reps") }
        else if let lo = p.repsLow { parts.append("\(lo)+ reps") }
        return parts.isEmpty ? "Adjustment" : parts.joined(separator: " × ")
    }

    private func bubble(_ turn: Turn) -> some View {
        Text(turn.text)
            .font(GSFont.body(14, relativeTo: .body))
            .foregroundStyle(turn.isCoach ? theme.text : theme.bg)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(turn.isCoach ? theme.surface : theme.accent))
            .frame(maxWidth: .infinity,
                   alignment: turn.isCoach ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    // The adapter is availability-gated; these helpers only run where
    // `isConversationAvailable` said yes.
    private func open() async {
        guard turns.isEmpty else { return }
        thinking = true
        defer { thinking = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Explicitly typed: the bare ternary-of-closure was ambiguous
            // to infer, and the iOS 26 SDK's named-Task initializer made
            // a Task { @MainActor } hop ambiguous too - plain main-queue
            // dispatch does the one job needed.
            var proposeHook: (@Sendable (RoutineEditProposal) -> Void)? = nil
            if applyRoutineEdit != nil {
                proposeHook = { proposal in
                    DispatchQueue.main.async { pendingEdit = proposal }
                }
            }
            let session = CoachDebriefSession(
                debrief: debrief, persona: persona, profile: profile,
                trendLookup: trendLookup, volumeLookup: volumeLookup,
                onProposeEdit: proposeHook)
            activeSession = session
            if let opening = try? await session.open() {
                turns.append(Turn(isCoach: true, text: opening))
                return
            }
        }
        #endif
        turns.append(Turn(isCoach: true, text: debrief.headline))
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        draft = ""
        turns.append(Turn(isCoach: false, text: message))
        thinking = true
        Task {
            defer { thinking = false }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *),
               let session = activeSession as? CoachDebriefSession {
                // Field screenshot 2026-08-22: `try?` here conflated a
                // thrown generation error (guardrail trip, transient
                // failure) with a device that can't run the model - the
                // "can't chat on this device" line was a lie mid-chat.
                // A throw is a RETRYABLE moment, and the real error goes
                // to the log so repeat offenders get named.
                do {
                    let reply = try await session.reply(to: message)
                    turns.append(Turn(isCoach: true, text: reply))
                } catch {
                    AppLogger.workout.error("coach reply failed: \(error.localizedDescription, privacy: .public)")
                    turns.append(Turn(isCoach: true,
                                      text: "That one didn't come through — give me the question once more."))
                }
                return
            }
            #endif
            turns.append(Turn(isCoach: true,
                              text: "I can't chat on this device, but every number in the report is real — tap through the recap for the full breakdown."))
        }
    }

    /// Held as Any so this view compiles on every SDK; only the gated
    /// paths above cast it.
    @State private var activeSession: Any?
}
