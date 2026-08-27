import SwiftUI

// MARK: - CoachRulesView
//
// The management surface for standing rules. Owner 2026-08-27: "There
// should be a way to audit, edit, or delete rules as well."
//
// Audit and delete existed before this screen — as an inline section on
// the Coach landing with a LONG-PRESS to drop. The owner asking for them
// was the finding: an affordance nobody can see is a secret, not a
// feature. This page makes every fact and every action visible.
//
// WHY THIS IS NOT IN SETTINGS (owner asked): rules are not
// configuration — they are agreements between the athlete and Coach.
// They carry provenance (consult vs chat), a confirmation the athlete
// gave, an applied-at receipt, sometimes a condition. Settings is where
// things go to be forgotten; these are cited in conversation and shape
// every build, so they live in Coach's world.
//
// WHY "EDIT" IS RE-STATEMENT, not a text field: a raw editor would
// change the WORDS while the stored reading — the thing the levers fire
// on — kept its old meaning. That is the confirmed-but-wrong state the
// whole pipeline exists to prevent. The honest edit is saying it again:
// the new version walks the same classify-then-confirm road as every
// rule, and the old one is dropped here. No rule ever takes effect
// without the athlete having seen Coach's reading of it.
struct CoachRulesView: View {
    @Environment(\.gsTheme) private var theme

    @State private var rules: [TrainingRule] = []
    @State private var loading = true
    @State private var workingOn: UUID?
    /// The drop confirmation — a visible, deliberate act, unlike the
    /// long-press it replaces as the primary affordance.
    @State private var dropping: TrainingRule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().tint(theme.accent)
                        Text("READING YOUR RULES")
                            .font(GSFont.bold(13, relativeTo: .headline))
                            .tracking(0.9)
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gs3DCard(cornerRadius: GSMetrics.radiusSm)
                } else if rules.isEmpty {
                    emptyCard
                } else {
                    Text("Everything Coach is holding for you. Drop one and it stops shaping your programs and Coach's advice — the record keeps it, in case you ever ask what changed.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                    ForEach(rules) { rule in
                        ruleCard(rule)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .confirmationDialog(
            "Drop this rule?",
            isPresented: Binding(get: { dropping != nil },
                                 set: { if !$0 { dropping = nil } }),
            titleVisibility: .visible
        ) {
            Button("Drop it", role: .destructive) {
                if let rule = dropping {
                    Task {
                        try? await TrainingRulesRepository.retire(rule.id)
                        await load()
                    }
                }
                dropping = nil
            }
            Button("Keep it", role: .cancel) { dropping = nil }
        } message: {
            Text(dropping.map { "\u{201c}\($0.rule)\u{201d} stops shaping your programs from the next build on." } ?? "")
        }
    }

    // MARK: One rule, every fact, every action

    private func ruleCard(_ rule: TrainingRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\u{201c}\(rule.rule)\u{201d}")
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(sourceBadge(rule))
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.surface))
            }

            // Coach's reading, when it has one — the thing a lever
            // actually fires on, shown so the words and the meaning can
            // be audited side by side.
            if rule.intent != .unknown {
                Text(rule.intent.reading(slots: rule.slots ?? [:]))
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusLine(rule))
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(rule.appliedAt != nil ? theme.accent : theme.neutral500)

            HStack(spacing: 10) {
                // WAITING ON YOU gets its verdict buttons HERE too — the
                // confirm cards live on the landing, but a management
                // page that shows a waiting rule and offers no way to
                // answer it would be an audit of a queue you can't move.
                if rule.needsConfirmation {
                    Button {
                        verdict(rule, agreed: true)
                    } label: {
                        actionLabel("THAT'S RIGHT", filled: true)
                    }
                    .buttonStyle(.plain)
                    Button {
                        verdict(rule, agreed: false)
                    } label: {
                        actionLabel("NOT QUITE", filled: false)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        // Re-statement IS the edit. The new version walks
                        // the same classify-then-confirm road as every
                        // rule; the old one is dropped here once the new
                        // one is held. Two deliberate taps, no consent
                        // bypass.
                        CoachThreadLauncher(
                            title: "Rule change",
                            opener: "You want to change a standing rule. The current one: \u{201c}\(rule.rule)\u{201d}. Tell me the new version in your own words \u{2014} I'll read it back, and once you confirm it, come back and drop the old one from your rules list.")
                        .background(theme.bg)
                        .navigationTitle("Coach")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        actionLabel("SAY IT DIFFERENTLY", filled: false)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    dropping = rule
                } label: {
                    if workingOn == rule.id {
                        ProgressView().tint(theme.accent)
                    } else {
                        Text("DROP")
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO STANDING RULES")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("Tell Coach one in the consult or in any chat \u{2014} \u{201c}pulls before arms\u{201d}, \u{201c}no leg extensions\u{201d} \u{2014} and it lives here, shaping every block until you drop it.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    // MARK: Wire

    private func actionLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(GSFont.bold(11, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(filled ? theme.bg : theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(filled ? theme.accent : theme.surface))
    }

    private func sourceBadge(_ rule: TrainingRule) -> String {
        switch rule.source {
        case "chat": return "FROM CHAT"
        case "manual": return "MANUAL"
        default: return "FROM THE CONSULT"
        }
    }

    /// Same statuses as the landing preview — the two surfaces must
    /// never disagree about what a rule is doing.
    private func statusLine(_ rule: TrainingRule) -> String {
        if rule.appliedAt != nil { return "LIVE \u{2014} built into your block" }
        if rule.needsConfirmation { return "WAITING ON YOU \u{2014} is my reading right?" }
        if rule.isWaitingToBeBuilt { return "READY \u{2014} goes in on your next build" }
        if rule.understoodButUnbuildable { return "HEARD \u{2014} on my list, can't build this one yet" }
        return "KEPT \u{2014} I couldn't read this as a program change"
    }

    private func verdict(_ rule: TrainingRule, agreed: Bool) {
        guard workingOn == nil else { return }
        workingOn = rule.id
        Task {
            defer { workingOn = nil }
            await TrainingRulesRepository.setConfirmed(rule.id, agreed)
            await load()
        }
    }

    private func load() async {
        rules = (try? await TrainingRulesRepository.active()) ?? []
        loading = false
    }
}
