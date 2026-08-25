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
    @Environment(\.gsTheme) private var theme

    @State private var profile = TrainingProfile()
    @State private var researched: [String] = []

    private var persona: CoachPersona? { CoachPersona.bySlug(profile.persona) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                personaHeader

                chatDoor

                programDoor

                if !researched.isEmpty {
                    researchNotice
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task {
            if let loaded = try? await TrainingProfileRepository.load() {
                profile = loaded
            }
            researched = await CoachChatRepository.researchedQuestions()
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

    // MARK: MY PROGRAM (the generator, one layer down)

    private var programDoor: some View {
        NavigationLink {
            CoachWizardView(onCreated: {})
                .background(theme.bg)
        } label: {
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

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var messages: [CoachChatMessage] = []
    @State private var draft = ""
    @State private var thinking = false
    @State private var loading = true
    @State private var titled = false
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
                body: "Fresh thread — what's on your mind? A lift, the week's plan, something from the research. Each thread here stays on its topic.",
                createdAt: .now)]
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), CoachDebrief.isConversationAvailable {
            let profile = (try? await TrainingProfileRepository.load()) ?? TrainingProfile()
            var logsByName: [String: [SetLog]] = [:]
            if let userID = appState.currentProfile?.id,
               let exercises = try? await ExerciseRepository.fetchAll(),
               let logs = try? await SessionRepository.recentSetLogs(
                   userID: userID, since: Date(timeIntervalSinceNow: -42 * 86_400)) {
                let nameByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.name) })
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
                })
        }
        #endif
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
