import SwiftUI

// MARK: - CoachHomeView
//
// Coach's front door (owner 2026-08-24: "the coach should replace the
// programs widget on the T1 of the You tab… within the Coach page, the
// program building feature should be moved another layer down, and then
// we add some functionality to Coach, like the dedicated chat").
//
//   CHAT — the persistent thread (CoachChatView below): one ongoing
//     conversation with compaction, not a per-workout debrief.
//   MY PROGRAM — the generator (CoachWizardView), one layer down.
//   RESEARCH — when a question the corpus couldn't answer comes back
//     researched, the delivery notice lands here.
struct CoachHomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var profile = TrainingProfile()
    @State private var researched: [String] = []
    /// Set when a rule the athlete just gave could not be stored. The
    /// whole point of the 2026-08-26 fix is that this is never nil in
    /// silence: if their words did not stick, they are told.
    @State private var ruleTrouble: String?
    /// Rules Coach has a reading for and has not been told whether it got
    /// them right. A lever never fires from an unconfirmed reading.
    @State private var toConfirm: [TrainingRule] = []
    /// Rules Coach CAN now build and has not built yet - the mirror of
    /// "the research came back", for capability instead of knowledge.
    @State private var nowBuildable: [TrainingRule] = []
    /// Loaded for the consult, whose constraint chips must offer labels
    /// selection recognises — see ConsultVocabulary.
    @State private var catalog: [Exercise] = []
    /// Sessions per week the LOG shows, over the trailing 8 weeks. nil
    /// means no evidence, which is not the same as zero — it decides
    /// whether the consult diagnoses or cold-starts.
    @State private var loggedCadence: Double?
    /// The consult ends on "BUILD IT", so it has to actually build.
    /// Saving a profile and dropping the athlete back here with
    /// instructions to go press generate somewhere else is not what that
    /// button says.
    /// One destination at a time.
    ///
    /// The consult used to be a NavigationLink and the wizard a separate
    /// navigationDestination, both anchored on this screen - so finishing
    /// the consult PUSHED the wizard on top of it, leaving the consult
    /// mounted underneath. Popping out of the builder landed the athlete
    /// back in the consult, which restarted at its health gate and asked
    /// the medical questions a second time.
    ///
    /// navigationDestination(item:) REPLACES rather than stacks: moving
    /// route from .consult to .wizard swaps the pushed view, so the
    /// consult is gone and the builder pops back to here.
    @State private var route: Route?

    private enum Route: Hashable { case consult, wizard, schedule }

    private var persona: CoachPersona? { CoachPersona.bySlug(profile.persona) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                personaHeader

                chatDoor

                consultDoor

                programDoor

                if let ruleTrouble {
                    ruleTroubleNotice(ruleTrouble)
                }

                ForEach(toConfirm) { rule in
                    confirmReadingCard(rule)
                }

                if !nowBuildable.isEmpty {
                    nowBuildableNotice
                }

                if !researched.isEmpty {
                    researchNotice
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationDestination(item: $route) { destination in
            switch destination {
            case .consult:
                consultDestination
            case .wizard:
                // Owner 2026-08-26: "When I built my week, it should take
                // us to our scheduling stack." It did the opposite —
                // dismiss() popped the athlete OUT of the builder, which
                // is the only screen in the app that instantiates
                // ProgramScheduleView. The week they had just commissioned
                // was three taps back the way they came.
                //
                // The same REPLACE that fixed the consult loop carries
                // this: moving route to .schedule swaps the pushed view,
                // so the builder unmounts and the schedule takes its place
                // — no wizard underneath to fall back into.
                CoachWizardView(onCreated: {
                    route = .schedule
                    return .handled
                })
                .background(theme.bg)
            case .schedule:
                ProgramScheduleView()
                    .background(theme.bg)
            }
        }
        .task {
            if let loaded = try? await TrainingProfileRepository.load() {
                profile = loaded
            }
            researched = await CoachChatRepository.researchedQuestions()
            await readRules()
            catalog = (try? await ExerciseRepository.fetchAll()) ?? []
            await readCadence()
        }
    }

    private var personaHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text((persona?.name ?? "Coach").uppercased())
                    .font(GSFont.bold(15, relativeTo: .body))
                    .tracking(0.8)
                    .foregroundStyle(theme.text)
                Text(persona?.tagline ?? "Reads the log. Says what matters.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: CHAT (the headline feature — wide, tall, extruded)

    private var chatDoor: some View {
        NavigationLink {
            CoachChatView()
                .background(theme.bg)
                .navigationTitle("Threads")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CHAT")
                        .font(GSFont.bold(22, relativeTo: .title3))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                Text("Threads with your coach — one per topic. Pick any back up where it left off, or start fresh.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Text("EVERY THREAD REMEMBERS")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral500)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chat with your coach")
    }

    // MARK: THE CONSULT (the guided way in)
    //
    // Sits above MY PROGRAM because it LEADS there: the five doors are
    // coarse adjustment, the consult confirms and fine-tunes, and both
    // end at the same generator.
    private var consultDoor: some View {
        Button { route = .consult } label: {
            consultDoorLabel
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The consult — a few questions, then a program")
    }

    private var consultDestination: some View {
        CoachConsultView(
            profile: profile,
            catalog: catalog,
            // Everything below is READ. A consult that opens already
            // knowing the athlete is the difference between a consult and
            // a form.
            //
            // A block finished OR sets logged. Carryover alone would
            // cold-start someone midway through their first block - they
            // have a log, they just have not finished anything.
            hasLog: profile.carryover != nil || loggedCadence != nil,
            loggedDaysPerWeek: loggedCadence
                ?? profile.carryover?.suggestedDaysPerWeek.map(Double.init),
            recommendedDaysPerWeek: profile.daysPerWeek,
            userID: appState.currentProfile?.id,
            onFinish: { answers in
                Task {
                    await applyConsult(answers)
                    // REPLACES the consult rather than pushing on top of
                    // it. Stacking was the bug: the builder popped back
                    // into a consult that then re-ran its health gate.
                    route = .wizard
                }
            })
        .background(theme.bg)
        .navigationBarBackButtonHidden(true)
    }

    private var consultDoorLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("THE CONSULT")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                Text(consultSubtitle)
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// A returning athlete is not starting over, and the door should not
    /// say they are.
    private var consultSubtitle: String {
        profile.carryover == nil
            ? "A few questions, then I build your first block"
            : "Tell me what changed and I'll retune the block"
    }

    /// Fold the consult's answers into the profile and save. The generator
    /// is not run from here — the athlete lands on MY PROGRAM with every
    /// field already set, which is the point of the split: the consult
    /// TUNES, the wizard BUILDS, and both read the same profile.
    private func applyConsult(_ answers: ConsultAnswers) async {
        guard let userID = appState.currentProfile?.id else { return }
        let tuned = answers.apply(to: profile, catalog: catalog)
        profile = tuned
        try? await TrainingProfileRepository.save(tuned, userID: userID)
        // NOT `try?`. The swallowed error here is what made the original
        // defect invisible: every add() threw 23502 and nobody heard it.
        // A rule that cannot be stored is reported, because the athlete
        // just told us something and deserves to know it did not stick.
        for rule in answers.standingRules {
            // Read it into a structured intent before storing. Failure
            // here is not an error: RuleClassifier returns .unknown when
            // it cannot do better, which stores the rule verbatim, reports
            // it as heard-not-built, and counts it in the queue of levers
            // worth building next.
            let reading = await RuleClassifier.read(rule, catalog: catalog)
            do {
                try await TrainingRulesRepository.add(
                    rule, source: "consult",
                    intent: reading.intent,
                    slots: reading.slots.isEmpty ? nil : reading.slots,
                    userID: userID)
            } catch {
                ruleTrouble = ErrorMapping.map(error).errorDescription
            }
        }
        await readRules()
    }

    /// The trailing-8-week cadence, from set logs. Distinct DAYS, not log
    /// rows — see ConsultProbe.loggedCadence.
    private func readCadence() async {
        guard let userID = appState.currentProfile?.id else { return }
        let since = Calendar.current.date(byAdding: .day, value: -56, to: Date()) ?? Date()
        guard let logs = try? await SessionRepository.recentSetLogs(userID: userID,
                                                                   since: since) else { return }
        loggedCadence = ConsultProbe.loggedCadence(sessionDates: logs.map(\.loggedAt))
    }

    // MARK: MY PROGRAM (the generator, one layer down)

    private var programDoor: some View {
        // Same route as the consult, so there is exactly one way the
        // builder gets onto the stack and exactly one thing that can pop
        // off it.
        Button { route = .wizard } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MY PROGRAM")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Text("Goals, schedule, style, body, limits — the generator builds your week")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("My program — the generator")
    }

    // MARK: Research deliveries

    /// The athlete told Coach a rule and it did not stick.
    ///
    /// Deliberately loud rather than a grey line, and deliberately says
    /// what to do next. The failure this replaces was invisible: from the
    /// consult's side the rule was accepted, and the table stayed empty.
    private func ruleTroubleNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A RULE DID NOT STICK")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            Text(message)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            // A NavigationLink rather than a Route case, matching
            // chatDoor - chat is a push, not one of the three destinations
            // this screen swaps between.
            NavigationLink {
                CoachChatView()
                    .background(theme.bg)
                    .navigationTitle("Threads")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Text("Tell Coach again in chat")
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(theme.accent, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// "Here is what I think you meant. Right?"
    ///
    /// The gate between a model's reading and the athlete's training. It
    /// exists because the failure it prevents is invisible: a rule read
    /// wrongly would quietly reshape their program, and they would have
    /// no reason to suspect the rule was why.
    private func confirmReadingCard(_ rule: TrainingRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DID I GET THIS RIGHT?")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            Text("“\(rule.rule)”")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            Text(rule.intent.reading(slots: rule.slots ?? [:]))
                .font(GSFont.bold(15, relativeTo: .headline))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    Task {
                        await TrainingRulesRepository.setConfirmed(rule.id, true)
                        await readRules()
                    }
                } label: {
                    Text("YES, BUILD IT")
                        .font(GSFont.bold(13, relativeTo: .headline))
                        .tracking(0.6)
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 13))

                Button {
                    Task {
                        await TrainingRulesRepository.setConfirmed(rule.id, false)
                        await readRules()
                    }
                } label: {
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

    /// The capability mirror of "the research came back".
    ///
    /// Owner 2026-08-26: "we should have unfulfilled request log that we
    /// then accumulate parts and upgrade the generator to account for in
    /// the future." Because buildability is derived from this build's
    /// lever registry rather than stored per row, shipping a lever makes
    /// every rule ever recorded with that intent light up here at once -
    /// including ones typed long before it existed.
    private var nowBuildableNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("I CAN BUILD THIS NOW")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            ForEach(nowBuildable) { rule in
                Text("“\(rule.rule)”")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(2)
            }
            Text("Build your program again and it goes in.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func readRules() async {
        let all = (try? await TrainingRulesRepository.active()) ?? []
        toConfirm = all.filter(\.needsConfirmation)
        nowBuildable = all.filter(\.isWaitingToBeBuilt)
    }

    private var researchNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THE RESEARCH CAME BACK")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            ForEach(researched, id: \.self) { question in
                Text("“\(question)”")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(2)
            }
            Text("Ask again in chat — the library has answers now.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CoachChatView (the thread list)
//
// Claude-style threads (owner 2026-08-24: "go to a thread, continue
// the conversation, then back out and jump into a different one about
// a different topic. Not one long chat."). This screen is the list;
// CoachThreadView below is one conversation. Each thread carries its
// own compaction state on its row.
struct CoachChatView: View {
    @Environment(\.gsTheme) private var theme

    @State private var threads: [CoachChatThread] = []
    @State private var loading = true
    @State private var pushedThread: CoachChatThread?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                newThreadButton

                if threads.isEmpty && !loading {
                    Text("No conversations yet. Start one — a lift that feels off, a programming question, what the research says. Each thread keeps its own history.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                        .padding(.horizontal, 2)
                }

                ForEach(threads) { thread in
                    threadRow(thread)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task {
            threads = await CoachChatRepository.threads()
            loading = false
        }
        .navigationDestination(item: $pushedThread) { thread in
            CoachThreadView(thread: thread)
                .background(theme.bg)
                .navigationTitle(thread.title == "New thread" ? "Coach" : thread.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var newThreadButton: some View {
        Button {
            Task {
                if let created = await CoachChatRepository.createThread() {
                    threads.insert(created, at: 0)
                    pushedThread = created
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("NEW THREAD")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.6)
                    .foregroundStyle(theme.text)
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityLabel("New thread")
    }

    private func threadRow(_ thread: CoachChatThread) -> some View {
        Button {
            pushedThread = thread
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title)
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(relativeAge(thread.updatedAt))
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        // Deletion rides the long-press context menu (the crew-member
        // removal precedent) — no swipe gestures in a ScrollView.
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    await CoachChatRepository.deleteThread(id: thread.id)
                    threads.removeAll { $0.id == thread.id }
                }
            } label: {
                Label("Delete thread", systemImage: "trash")
            }
        }
    }

    private func relativeAge(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 3600 { return "Just now" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "Yesterday" : "\(days)d ago"
    }
}

// MARK: - CoachThreadView (one conversation)
//
// History loads from coach_chat_messages by thread; every exchange
// persists both sides; the engine compacts onto the thread row behind
// the scenes (CoachChatEngine) so the conversation never hits the
// model's window.
struct CoachThreadView: View {
    let thread: CoachChatThread
    /// Context the caller wants Coach to open the thread with (a routine,
    /// a block week). Shown as Coach's first line on an empty thread in
    /// place of the generic greeting; not persisted, so it never becomes
    /// a message the model has to account for later.
    var seededOpener: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var messages: [CoachChatMessage] = []
    @State private var draft = ""
    @State private var thinking = false
    @State private var loading = true
    @State private var titled = false
    /// The Apply loop in threads (owner 2026-08-25): Coach proposed, the
    /// athlete decides — #38's no-silent-tweaks holds here too.
    @State private var pendingEdit: RoutineEditProposal?
    @State private var applyingEdit = false
    @State private var allExercises: [Exercise] = []
    /// Held as Any so this view compiles on every SDK; only the gated
    /// paths below cast it (the CoachRecapView precedent).
    @State private var engine: Any?

    var body: some View {
        VStack(spacing: 0) {
            if CoachDebrief.isConversationAvailable {
                conversation
            } else {
                unavailableCard
            }
        }
        .background(theme.bg)
        .task { await open() }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            bubble(message)
                        }
                        if thinking {
                            Text("…")
                                .font(GSFont.bold(15, relativeTo: .body))
                                .foregroundStyle(theme.neutral500)
                                .padding(.horizontal, 14)
                        }
                        Color.clear.frame(height: 1).id("chat-tail")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo("chat-tail", anchor: .bottom) }
                }
            }
            if let proposal = pendingEdit {
                VStack(alignment: .leading, spacing: 6) {
                    Text("COACH PROPOSES · \(proposal.exerciseName.uppercased())")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.accent)
                    Text(threadProposalSummary(proposal))
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text(proposal.reason)
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            guard !applyingEdit else { return }
                            applyingEdit = true
                            Task {
                                defer { applyingEdit = false }
                                let confirmation = await applyThreadRoutineEdit(proposal)
                                    ?? "I couldn't find that one in your routines to edit — the numbers stand as they were."
                                if let saved = await CoachChatRepository.append(
                                    threadID: thread.id, role: "coach", body: confirmation) {
                                    messages.append(saved)
                                } else {
                                    messages.append(CoachChatMessage(id: UUID(), role: "coach",
                                                                     body: confirmation, createdAt: .now))
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
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach chat needs Apple Intelligence (iOS 26+).")
                .font(GSFont.bold(15, relativeTo: .body))
                .foregroundStyle(theme.text)
            Text("Your program, stats, and every after-workout report still work — the live back-and-forth is the only part that needs the on-device model.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ message: CoachChatMessage) -> some View {
        Text(message.body)
            .font(GSFont.body(14, relativeTo: .body))
            .foregroundStyle(message.isCoach ? theme.text : theme.bg)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(message.isCoach ? theme.surface : theme.accent))
            .frame(maxWidth: .infinity,
                   alignment: message.isCoach ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// History + engine, once. The engine gets the same computed-facts
    /// tool belt as the debrief: trends from the athlete's own 42-day
    /// log (built the CrewCoachEngine way), plus the research corpus.
    private func open() async {
        guard loading else { return }
        defer { loading = false }
        AppLogger.workout.info("coach thread open: available=\(CoachDebrief.isConversationAvailable, privacy: .public)")
        messages = await CoachChatRepository.recent(threadID: thread.id)
        titled = thread.title != "New thread" || !messages.isEmpty
        // Field 2026-08-24 ("the coach chat page doesn't have anything
        // on it"): a fresh thread must never read as a dead screen —
        // Coach opens it, unprompted and unpersisted.
        if messages.isEmpty {
            messages = [CoachChatMessage(id: UUID(), role: "coach",
                body: seededOpener
                    ?? "Fresh thread — what's on your mind? A lift, the week's plan, something from the research. Each thread here stays on its topic.",
                createdAt: .now)]
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), CoachDebrief.isConversationAvailable {
            let profile = (try? await TrainingProfileRepository.load()) ?? TrainingProfile()
            var logsByName: [String: [SetLog]] = [:]
            allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
            if let userID = appState.currentProfile?.id,
               let logs = try? await SessionRepository.recentSetLogs(
                   userID: userID, since: Date(timeIntervalSinceNow: -42 * 86_400)) {
                let nameByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
                for log in logs where !log.isPenalty {
                    guard let name = nameByID[log.exerciseID]?.lowercased() else { continue }
                    logsByName[name, default: []].append(log)
                }
            }
            // Field #3: routines + schedule context for the thread.
            var railLines: [String] = []
            if let ownerID = appState.currentProfile?.id,
               let routines = try? await RoutineRepository.fetchAll(ownerID: ownerID) {
                let own = routines.filter { $0.prescribedBy == nil }.prefix(12)
                if !own.isEmpty {
                    railLines.append("SAVED ROUTINES: " + own.map(\.name).joined(separator: " · "))
                }
                let prescribed = routines.filter { $0.prescribedBy != nil }
                if !prescribed.isEmpty {
                    railLines.append("TRAINER-PRESCRIBED: " + prescribed.map(\.name).joined(separator: " · "))
                }
            }
            if let userID = appState.currentProfile?.id,
               let history = try? await SessionRepository.history(userID: userID, limit: 12) {
                let recent = history.compactMap { session -> String? in
                    guard let done = session.completedAt else { return nil }
                    let days = max(0, Int(Date().timeIntervalSince(done) / 86_400))
                    return days == 0 ? "today" : "\(days)d ago"
                }
                if !recent.isEmpty {
                    railLines.append("RECENT SESSIONS: \(recent.count) in the log, latest \(recent.first ?? "")")
                }
            }
            if let seededOpener {
                railLines.append("THIS THREAD WAS OPENED FROM: \(seededOpener)")
            }
            // The athlete's own standing rules, so Coach can CITE one
            // rather than silently obeying it — the difference between a
            // coach who listened and a setting that took effect.
            let rules = (try? await TrainingRulesRepository.active()) ?? []
            engine = CoachChatEngine(
                thread: thread,
                profile: profile,
                persona: CoachPersona.bySlug(profile.persona),
                routinesRail: railLines.joined(separator: "\n"),
                trendLookup: { [logsByName] name in
                    if let logs = logsByName[name.lowercased()], logs.count > 1 {
                        return DebriefBuilder.trendSentence(name: name, logs: logs)
                    }
                    return "\(name): not enough logged history for a trend yet."
                },
                volumeLookup: {
                    "Per-muscle weekly volume lands in an upcoming update — ask about any lift's trend instead."
                },
                // The app's math as a tool (owner 2026-08-25) — the same
                // qualifying-set filter and Epley the live session uses.
                progressionLookup: { [logsByName] name, targetReps in
                    let unit = ThemeStore.shared.weightUnit
                    let logs = logsByName[name.lowercased()] ?? logsByName.first(where: {
                        $0.key.contains(name.lowercased()) || name.lowercased().contains($0.key)
                    })?.value ?? []
                    return DebriefBuilder.progressionSentence(
                        name: name, targetReps: targetReps, logs: logs, unit: unit)
                },
                standingRules: rules.map(\.rule),
                onProposeEdit: { proposal in
                    DispatchQueue.main.async { pendingEdit = proposal }
                })
        }
        #endif
    }

    private func threadProposalSummary(_ p: RoutineEditProposal) -> String {
        var parts: [String] = []
        if let w = p.weight { parts.append("\(Int(w.rounded())) \(ThemeStore.shared.weightUnit.label)") }
        if let lo = p.repsLow, let hi = p.repsHigh { parts.append("\(lo)–\(hi) reps") }
        else if let lo = p.repsLow { parts.append("\(lo)+ reps") }
        if let r = p.routineName { parts.append("in \(r)") }
        return parts.isEmpty ? "Adjustment" : parts.joined(separator: " · ")
    }

    /// The standalone apply writer (owner 2026-08-25: the Apply loop
    /// works on custom-built routines too, outside any session). Picks
    /// the routine by the proposal's name when given, else the athlete's
    /// own routine that contains the exercise; trainer prescriptions are
    /// never touched. Returns the confirmation line, nil on any miss.
    private func applyThreadRoutineEdit(_ proposal: RoutineEditProposal) async -> String? {
        guard let ownerID = appState.currentProfile?.id,
              let routines = try? await RoutineRepository.fetchAll(ownerID: ownerID)
        else { return nil }
        let own = routines.filter { $0.prescribedBy == nil }
        guard !own.isEmpty else { return nil }
        let nameByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name.lowercased()) })
        let target = proposal.exerciseName.lowercased()
        func matches(_ re: RoutineExercise) -> Bool {
            guard let name = nameByID[re.exerciseID] else { return false }
            return name == target || name.contains(target) || target.contains(name)
        }
        let allRows = (try? await RoutineRepository.exercisesForRoutines(ids: own.map(\.id))) ?? []
        let rowsByRoutine = Dictionary(grouping: allRows, by: \.routineID)
        var routine: Routine?
        if let wanted = proposal.routineName?.lowercased() {
            routine = own.first { $0.name.lowercased() == wanted }
                ?? own.first { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) }
        }
        if routine == nil {
            routine = own.first { rowsByRoutine[$0.id]?.contains(where: matches) == true }
        }
        guard let routine, var rows = rowsByRoutine[routine.id],
              let index = rows.firstIndex(where: matches) else { return nil }
        var summary: [String] = []
        let unit = ThemeStore.shared.weightUnit
        if let weight = proposal.weight {
            let pounds = Units.toPounds(Decimal(weight), from: unit)
            rows[index].targetWeight = "\(pounds)"
            summary.append(Units.format(pounds: pounds, unit: unit,
                                        rounded: false, includeUnit: true))
        }
        if let lo = proposal.repsLow {
            rows[index].targetRepsLow = lo
            rows[index].targetRepsHigh = proposal.repsHigh ?? max(lo, rows[index].targetRepsHigh ?? lo)
            rows[index].targetReps = "\(lo)"
            summary.append("\(lo)–\(rows[index].targetRepsHigh ?? lo) reps")
        } else if let hi = proposal.repsHigh {
            rows[index].targetRepsHigh = hi
            summary.append("up to \(hi) reps")
        }
        guard !summary.isEmpty else { return nil }
        do {
            try await RoutineRepository.save(routine, exercises: rows)
        } catch { return nil }
        let exerciseName = allExercises.first(where: { $0.id == rows[index].exerciseID })?.name
            ?? proposal.exerciseName
        return "Done — \(exerciseName) in \(routine.name) is now \(summary.joined(separator: " × ")). It'll load that way next session."
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        draft = ""
        thinking = true
        Task {
            defer { thinking = false }
            // UI first; persistence AFTER the reply — the engine's
            // cold-start seed reads persisted history, and the current
            // question must not appear there AND in the prompt.
            messages.append(CoachChatMessage(id: UUID(), role: "athlete",
                                             body: question, createdAt: .now))
            if !titled {
                titled = true
                await CoachChatRepository.autoTitle(threadID: thread.id, from: question)
            }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), let engine = engine as? CoachChatEngine {
                do {
                    let reply = try await engine.reply(to: question)
                    await CoachChatRepository.append(threadID: thread.id,
                                                     role: "athlete", body: question)
                    if let saved = await CoachChatRepository.append(threadID: thread.id,
                                                                    role: "coach", body: reply) {
                        messages.append(saved)
                    } else {
                        messages.append(CoachChatMessage(id: UUID(), role: "coach",
                                                         body: reply, createdAt: .now))
                    }
                } catch {
                    AppLogger.workout.error("coach thread reply failed: \(error.localizedDescription, privacy: .public)")
                    messages.append(CoachChatMessage(id: UUID(), role: "coach",
                        body: "That one didn't come through — give me the question once more.",
                        createdAt: .now))
                }
                return
            }
            #endif
            // Engine missing where the model is available = a wiring
            // failure worth naming, not a silent dead composer (the
            // 2026-08-24 field report's failure shape).
            AppLogger.workout.error("coach thread send: no engine (available=\(CoachDebrief.isConversationAvailable, privacy: .public))")
            messages.append(CoachChatMessage(id: UUID(), role: "coach",
                body: "I couldn't reach the on-device model just now — give me that once more in a moment.",
                createdAt: .now))
        }
    }
}
