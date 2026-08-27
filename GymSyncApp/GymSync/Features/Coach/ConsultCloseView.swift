import SwiftUI

// MARK: - ConsultCloseView
//
// The consult's closing conversation, mounted when the probes are
// exhausted on a device that can chat. Coach opens by summarizing what
// the consult established, then discusses standing rules; each rule the
// athlete states comes back as a consent card — their words beside
// Coach's reading — and only their tap stores it.
//
// A sibling of the debrief conversation on purpose: same bubbles, same
// thinking indicator, same proposal-card mechanism. Two chat idioms in
// one app would drift; this borrows every pattern the debrief already
// proved.
struct ConsultCloseView: View {
    @Environment(\.gsTheme) private var theme

    let answers: ConsultAnswers
    let profile: TrainingProfile
    let catalog: [Exercise]
    let userID: UUID?
    /// "THAT'S EVERYTHING — BUILD IT" — the same terminal the finished
    /// card offers, so the chat close and the fallback end identically.
    let onDone: () -> Void

    private struct Turn: Identifiable {
        let id = UUID()
        let isCoach: Bool
        let text: String
    }

    @State private var turns: [Turn] = []
    @State private var draft = ""
    @State private var thinking = false
    @State private var pendingRule: StandingRuleProposal?
    @State private var savedRules = 0
    @State private var activeSession: AnyObject?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(turns) { turn in
                        bubble(turn)
                    }
                    if thinking {
                        // Owner 2026-08-27: "a coach thinking little
                        // loop" - the ellipsis read as a dead screen
                        // while the opening turn composed.
                        CoachThinkingRow(text: "COACH IS THINKING")
                            .padding(.horizontal, 6)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let pendingRule {
                ruleCard(pendingRule)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                TextField("Tell your coach…", text: $draft, axis: .vertical)
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
            Button { onDone() } label: {
                Text(savedRules > 0
                     ? "THAT'S EVERYTHING — BUILD IT (\(savedRules) RULE\(savedRules == 1 ? "" : "S") HELD)"
                     : "THAT'S EVERYTHING — BUILD IT")
                    .font(GSFont.bold(15, relativeTo: .headline))
                    .tracking(0.8)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .task { await open() }
    }

    // MARK: The consent card

    /// The athlete's words beside Coach's reading, and the honest line
    /// when the reading cannot fire. Confirming implies action, so an
    /// unbuildable reading says so BEFORE the tap, never after.
    private func ruleCard(_ proposal: StandingRuleProposal) -> some View {
        let buildable = proposal.reading.intent.isBuildable(slots: proposal.reading.slots)
        let condition = proposal.reading.slots["condition"]
        return VStack(alignment: .leading, spacing: 8) {
            Text("COACH HEARD")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            Text("“\(proposal.verbatim)”")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            Text(proposal.reading.intent.reading(slots: proposal.reading.slots))
                .font(GSFont.bold(15, relativeTo: .headline))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let condition, !condition.isEmpty {
                // Owner's call (2026-08-27): a conditioned rule stays as
                // said, and the trigger routes through chat — Coach makes
                // the change when the athlete reports the condition.
                Text("Kept as said. When \(condition), tell Coach in chat and the change happens then.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !buildable {
                Text("I understand this one but can't build it into a block yet — it goes on my list, and I'll tell you when I can.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { accept(proposal) } label: {
                    Text(buildable ? "THAT'S IT" : "THAT'S WHAT I MEANT")
                        .font(GSFont.bold(13, relativeTo: .headline))
                        .tracking(0.6)
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 13))
                Button { reject(proposal) } label: {
                    Text("NOT QUITE")
                        .font(GSFont.bold(13, relativeTo: .headline))
                        .tracking(0.6)
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(GS3DButtonStyle(face: theme.raised3DFace,
                                             lip: theme.raised3DLip,
                                             cornerRadius: 13))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 12)
    }

    private func accept(_ proposal: StandingRuleProposal) {
        pendingRule = nil
        Task {
            // Confirmed AT CAPTURE, atomically — the athlete just read
            // their own words beside the reading and agreed. This is what
            // lets the rule fire on the very first build.
            if let userID {
                try? await TrainingRulesRepository.add(
                    proposal.verbatim, source: "consult",
                    intent: proposal.reading.intent,
                    slots: proposal.reading.slots.isEmpty ? nil : proposal.reading.slots,
                    confirmed: true,
                    userID: userID)
                savedRules += 1
            }
            await verdict(accepted: true, verbatim: proposal.verbatim)
        }
    }

    private func reject(_ proposal: StandingRuleProposal) {
        pendingRule = nil
        Task { await verdict(accepted: false, verbatim: proposal.verbatim) }
    }

    private func verdict(accepted: Bool, verbatim: String) async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let session = activeSession as? ConsultCloseSession,
           let reply = await session.noteVerdict(accepted: accepted, verbatim: verbatim) {
            turns.append(Turn(isCoach: true, text: reply))
        }
        #endif
    }

    // MARK: Wire

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

    private func open() async {
        guard turns.isEmpty else { return }
        thinking = true
        defer { thinking = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = ConsultCloseSession(
                digest: ConsultClose.digest(answers),
                persona: CoachPersona.bySlug(profile.persona),
                profile: profile,
                catalog: catalog,
                onPropose: { proposal in
                    DispatchQueue.main.async { pendingRule = proposal }
                })
            activeSession = session
            if let opening = try? await session.open() {
                turns.append(Turn(isCoach: true, text: opening))
                return
            }
        }
        #endif
        // The model refused its opening turn — degrade to the honest
        // static close rather than a mute chat.
        turns.append(Turn(isCoach: true,
                          text: "That's everything I need. Any standing rules before I build — things like \"pulls before arms\" or \"no leg extensions\"? Type them here, or hit build."))
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
               let session = activeSession as? ConsultCloseSession {
                // A throw is a RETRYABLE moment, not a missing model —
                // same lesson the debrief learned from the field
                // (2026-08-22): conflating them lies mid-chat.
                do {
                    let reply = try await session.reply(to: message)
                    turns.append(Turn(isCoach: true, text: reply))
                } catch {
                    AppLogger.workout.error("consult close reply failed: \(error.localizedDescription, privacy: .public)")
                    turns.append(Turn(isCoach: true,
                                      text: "That one didn't come through — say it once more."))
                }
                return
            }
            #endif
            // No session: keep the rule in their words, honestly heard.
            if let userID {
                try? await TrainingRulesRepository.add(
                    message, source: "consult",
                    intent: .unknown, slots: nil, confirmed: false,
                    userID: userID)
                savedRules += 1
                turns.append(Turn(isCoach: true,
                                  text: "Kept, in your words. I'll tell you when I can build it in."))
            }
        }
    }
}

// MARK: - CoachThinkingRow
//
// The visible wait: a spinner and a pulsing label. Shared by the close
// chat (composing a turn) and the consult (building the program), so the
// two waits look like the same coach.
struct CoachThinkingRow: View {
    let text: String

    @Environment(\.gsTheme) private var theme
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(theme.accent)
            Text(text)
                .font(GSFont.bold(12, relativeTo: .caption))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
                .opacity(pulse ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                           value: pulse)
        }
        .onAppear { pulse = true }
        .accessibilityLabel(text.capitalized)
    }
}
