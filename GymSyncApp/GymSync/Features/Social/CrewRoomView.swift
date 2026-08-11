import SwiftUI

// The crew room — the per-group front page from the SocialTabRoot design
// handoff (design-system project: design_handoff_social_tab/, v7.4 + the
// owner's corrections: no clip, plates are the crew's iron, week count
// dead-centered over its label, lifter colors on avatars only).
//
// Wired to real data: group streak (group_streaks), members, sessions
// (routines-together count + next lift), burpee ledger, chat preview.
// Deliberately absent until their systems exist: campaign meter (no
// campaigns infra), banner chevrons (perfect-week system), IN/OUT commit
// board (no per-session RSVP table — LET'S RIDE navigates to the lobby,
// which is the app's real commitment act today).
struct CrewRoomView: View {
    let group: GymGroup

    @Environment(\.gsTheme) private var theme

    @State private var members: [(member: GroupMember, profile: Profile)] = []
    @State private var streakWeeks = 0
    @State private var crewDebts: [BurpeeLedgerMath.CrewDebt] = []
    @State private var nextSession: WorkoutSession?
    @State private var completedThisWeek = 0
    @State private var plannedThisWeek = 0
    @State private var chatPreview: [String] = []
    @State private var showChat = false
    @State private var slotBreathing = false
    // Commit widget (20260811000001): ternary — in / out / no row = unsaid.
    @State private var commitments: [SessionCommitment] = []
    @State private var myUserID: UUID?
    // Campaign meter (20260811000002); loaded flag gates the adopt prompt so
    // it never flashes before the first fetch resolves.
    @State private var campaign: GroupCampaign?
    @State private var campaignLoaded = false
    @State private var showCampaignSheet = false
    // What the next session actually is (routine + programmed exercises).
    @State private var routineName: String?
    @State private var exerciseSummary: String?

    // Design-fixed inks (committed-dark values from the handoff; these are
    // brand semantics, not palette members — gold = debt/goal/streak,
    // green = square/week-made, iron = the crew's plates).
    private static let gold = Color(roomHex: 0xE8C33A)
    private static let green = Color(roomHex: 0x2FA45C)
    private static let iron = Color(roomHex: 0x53585F)
    private static let slotRecess = Color(roomHex: 0x1D2127)
    private static let slotBreathe = Color(roomHex: 0x3D444E)
    private static let hardLip = Color(roomHex: 0x0C0E11)

    private var ironclad: Bool { plannedThisWeek > 0 && completedThisWeek >= plannedThisWeek }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                headerRow
                bannerRail
                commitCard
                campaignCard
                routinesTogetherCard
                chatPreviewCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.bg)
        .scrollContentBackground(.hidden)
        .gsHidesDock()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GroupView(group: group)
                } label: {
                    Text("MANAGE")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(theme.neutral500)
                }
            }
        }
        .sheet(isPresented: $showCampaignSheet) {
            CampaignCreateSheet(group: group) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(group: group)
                    .background(theme.bg)
                    .navigationTitle(group.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onAppear { slotBreathing = true }
    }

    // MARK: - Header: crew name + streak numeral

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name.uppercased())
                    .font(GSFont.heading(21, relativeTo: .title2))
                    .kerning(-0.3)
                    .foregroundStyle(theme.text)
                Text("\(members.count) LIFTER\(members.count == 1 ? "" : "S")")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .kerning(2.4)
                    .foregroundStyle(theme.neutral500)
            }
            Spacer()
            // Streak numeral (handoff §1, "Numeral" treatment): the count and
            // its labels share one centered column so they stay in direct
            // vertical alignment at any digit width.
            VStack(spacing: 3) {
                Text("\(streakWeeks)")
                    .font(GSFont.heading(40, relativeTo: .largeTitle))
                    .kerning(-2)
                    .foregroundStyle(Self.gold)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 2)
                Rectangle()
                    .fill(Self.gold.opacity(0.55))
                    .frame(width: 26, height: 2)
                    .clipShape(Capsule())
                Text("WEEKS")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .kerning(2.4)
                    .foregroundStyle(theme.neutral700)
                Text("STRONG")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .kerning(2.4)
                    .foregroundStyle(Self.gold)
            }
        }
    }

    // MARK: - Banner rail (identity: Ceremony)

    // Steel rod + three hung pixel cloths. Plain cloths for now — chevrons
    // arrive with the perfect-week system, and unearned chevrons would lie.
    private var bannerRail: some View {
        VStack(alignment: .leading, spacing: -1) {
            Capsule()
                .fill(LinearGradient(colors: [Color(roomHex: 0xB9C1CC), Color(roomHex: 0x5D646F)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 4)
                .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 2)
            HStack(spacing: 4) {
                GSPixelBannerShape(cloth: Color(roomHex: 0x6B4FD6))
                GSPixelBannerShape(cloth: Color(roomHex: 0x6B4FD6))
                GSPixelBannerShape(cloth: Color(roomHex: 0xC39A1E))
            }
            .padding(.leading, 9)
        }
    }

    // MARK: - Commit card: the commitment signal (NOT lobby navigation)

    private var myCommitment: SessionCommitment.Status? {
        guard let myUserID else { return nil }
        return commitments.first { $0.userID == myUserID }?.status
    }

    private var commitCard: some View {
        Group {
            if let session = nextSession {
                if myCommitment == nil {
                    commitFace(session)
                } else {
                    statusBoard(session)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOTHING ON THE BOOKS")
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text("SCHEDULE THE NEXT LIFT FROM HOME")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(theme.neutral500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // Pre-answer face: compact commit control on the left, the right side
    // describing what the workout actually is (owner feedback: the button
    // was eating the widget).
    private func commitFace(_ session: WorkoutSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 7) {
                Button {
                    Task { await setCommitment(.committed, session: session) }
                } label: {
                    Text("LET'S RIDE")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .kerning(-0.1)
                }
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 13, verticalPadding: 9))
                Button {
                    Task { await setCommitment(.out, session: session) }
                } label: {
                    Text("CAN'T MAKE IT")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(Self.gold)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 118)

            VStack(alignment: .leading, spacing: 4) {
                Text((routineName ?? "NEXT LIFT").uppercased())
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .kerning(-0.1)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let exerciseSummary {
                    Text(exerciseSummary)
                        .font(GSFont.bold(9.5, relativeTo: .caption2))
                        .kerning(0.8)
                        .foregroundStyle(theme.neutral700)
                        .lineLimit(2)
                }
                if let when = session.scheduledFor {
                    Text("\(Self.whenLabel(when).uppercased()) · \(Self.countdownLabel(to: when).uppercased())")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.divider).frame(width: 1)
            }
        }
        .padding(13)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // Answered: the roll call. IN green, OUT gold (dimmed), unsaid dimmest.
    private func statusBoard(_ session: WorkoutSession) -> some View {
        let inMembers = boardMembers(.committed)
        let outMembers = boardMembers(.out)
        let unsaid = members.filter { entry in
            !commitments.contains { $0.userID == entry.member.userID }
        }
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((routineName ?? "NEXT LIFT").uppercased())
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    if let when = session.scheduledFor {
                        Text("\(Self.whenLabel(when).uppercased()) · \(Self.countdownLabel(to: when).uppercased())")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(theme.neutral700)
                    }
                }
                Spacer()
                Button {
                    Task { await clearCommitment(session) }
                } label: {
                    Text("CHANGE")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 8) {
                if !inMembers.isEmpty {
                    boardRow(label: "\(inMembers.count) IN", labelColor: Self.green,
                             entries: inMembers, dim: 1.0)
                }
                if !outMembers.isEmpty {
                    boardRow(label: "\(outMembers.count) OUT", labelColor: Self.gold,
                             entries: outMembers, dim: 0.42)
                }
                if !unsaid.isEmpty {
                    boardRow(label: "\(unsaid.count) UNSAID", labelColor: theme.neutral500,
                             entries: unsaid, dim: 0.3)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
        }
        .padding(13)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func boardMembers(_ status: SessionCommitment.Status) -> [(member: GroupMember, profile: Profile)] {
        members.filter { entry in
            commitments.contains { $0.userID == entry.member.userID && $0.status == status }
        }
    }

    private func boardRow(label: String, labelColor: Color,
                          entries: [(member: GroupMember, profile: Profile)],
                          dim: Double) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(labelColor)
                .frame(width: 62, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(entries, id: \.member.userID) { entry in
                    GSInitialsAvatar(
                        name: entry.profile.username,
                        avatarURL: entry.profile.avatarURL,
                        size: 24,
                        fill: GSGroupColor.color(for: entry.member.userID),
                        ink: GSGroupColor.onColor(for: entry.member.userID)
                    )
                }
            }
            .opacity(dim)
            Spacer(minLength: 0)
            Text(entries.map { $0.profile.username.uppercased() }.joined(separator: " · "))
                .font(GSFont.bold(9, relativeTo: .caption2))
                .kerning(0.8)
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func setCommitment(_ status: SessionCommitment.Status, session: WorkoutSession) async {
        try? await CommitmentRepository.setMine(sessionID: session.id, status: status)
        commitments = (try? await CommitmentRepository.commitments(sessionID: session.id)) ?? []
    }

    private func clearCommitment(_ session: WorkoutSession) async {
        try? await CommitmentRepository.clearMine(sessionID: session.id)
        commitments = (try? await CommitmentRepository.commitments(sessionID: session.id)) ?? []
    }

    // MARK: - Campaign meter / adoption prompt

    private var campaignCard: some View {
        Group {
            if let campaign {
                ZStack(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color(roomHex: 0x6B4FD6).opacity(0.20))
                            .frame(width: proxy.size.width * CGFloat(campaign.currentWeek) / CGFloat(campaign.weeks))
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(Color(roomHex: 0x6B4FD6)).frame(width: 2.5)
                            }
                    }
                    HStack {
                        Text(campaign.name.uppercased())
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(theme.neutral700)
                            .lineLimit(1)
                        Spacer()
                        Text("WK \(campaign.currentWeek) OF \(campaign.weeks)")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(Color(roomHex: 0x6B4FD6))
                    }
                    .padding(.horizontal, 13)
                }
                .frame(height: 44)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if campaignLoaded {
                Button {
                    showCampaignSheet = true
                } label: {
                    HStack {
                        Text("NO CAMPAIGN RUNNING")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                        Text("START ONE ›")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Routines together: the crew's bar

    private var routinesTogetherCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ROUTINES TOGETHER")
                .font(GSFont.bold(11, relativeTo: .caption))
                .kerning(1.1)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 13)
                .padding(.top, 12)

            // The bar band: collar → the crew's iron packed flush → bare
            // sleeve (the work remaining — no ghost plates, no clip) →
            // the week count centered over THIS WEEK + the slot column.
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.neutral500.opacity(0.55))
                        .frame(width: 185, height: 9)
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.neutral500)
                            .frame(width: 10, height: 26)
                        ForEach(0..<min(completedThisWeek, 8), id: \.self) { _ in
                            CrewIronPlate()
                        }
                    }
                }
                .frame(height: 90, alignment: .center)

                Spacer(minLength: 0)

                // Count + THIS WEEK share one centered column (the owner's
                // alignment correction) with the forward lean applied to the
                // whole column so they can never drift apart.
                VStack(spacing: 4) {
                    Text("\(completedThisWeek)")
                        .font(GSFont.heading(40, relativeTo: .largeTitle))
                        .kerning(-2)
                        .foregroundStyle(ironclad ? Self.green : theme.text)
                        .monospacedDigit()
                        .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 3)
                    Text("THIS WEEK")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .kerning(1.8)
                        .foregroundStyle(ironclad ? Self.green : theme.neutral700)
                }
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.176, d: 1, tx: 0, ty: 0))
                .offset(x: 5)

                slotColumn
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 13)

            GSDivider()

            burpeeLedgerRow
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // One slot per planned routine this week, filled bottom-up; the next
    // empty slot breathes on a 2.2s cycle. All green at ironclad, no pulse.
    private var slotColumn: some View {
        VStack(spacing: 2.5) {
            ForEach((0..<max(plannedThisWeek, 1)).reversed(), id: \.self) { index in
                let filled = index < completedThisWeek
                let isNext = !filled && index == completedThisWeek && !ironclad
                RoundedRectangle(cornerRadius: 2)
                    .fill(filled ? (ironclad ? Self.green : theme.text)
                                 : (isNext && slotBreathing ? Self.slotBreathe : Self.slotRecess))
                    .frame(width: 12, height: 10)
                    .shadow(color: filled ? Self.hardLip : .clear, radius: 0, x: 0, y: 2)
                    .animation(isNext ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil,
                               value: slotBreathing)
            }
        }
    }

    private var burpeeLedgerRow: some View {
        NavigationLink {
            BurpeeLedgerView(group: group)
        } label: {
            HStack(spacing: 12) {
                Text("BURPEES")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .kerning(1.1)
                    .foregroundStyle(theme.neutral700)
                HStack(spacing: 11) {
                    ForEach(members.prefix(4), id: \.member.userID) { entry in
                        let debt = crewDebts.first { $0.userID == entry.member.userID }
                        let outstanding = debt?.outstanding ?? 0
                        HStack(spacing: 4) {
                            GSInitialsAvatar(
                                name: entry.profile.username,
                                avatarURL: entry.profile.avatarURL,
                                size: 22,
                                fill: GSGroupColor.color(for: entry.member.userID),
                                ink: GSGroupColor.onColor(for: entry.member.userID)
                            )
                            if outstanding > 0 {
                                Text("\(outstanding)")
                                    .font(GSFont.bold(10, relativeTo: .caption2))
                                    .foregroundStyle(Self.gold)
                                    .monospacedDigit()
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Self.green)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                let totalOwed = crewDebts.reduce(0) { $0 + $1.outstanding }
                Text(totalOwed > 0 ? "\(totalOwed) OWED" : "ALL SQUARE")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .kerning(1.1)
                    .foregroundStyle(totalOwed > 0 ? Self.gold : Self.green)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chat preview

    private var chatPreviewCard: some View {
        Button {
            showChat = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("THE CHAT")
                        .font(GSFont.bold(11, relativeTo: .caption))
                        .kerning(1.1)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("OPEN")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(theme.neutral500)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.neutral500)
                }
                if chatPreview.isEmpty {
                    Text("Say something — the crew can hear you.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                } else {
                    ForEach(chatPreview.indices, id: \.self) { index in
                        Text(chatPreview[index])
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: 14))
    }

    // MARK: - Data

    private static let upcomingStates: Set<String> = [
        "scheduled", "lobby_open", "editing", "voting", "locked", "in_progress"
    ]

    private func load() async {
        myUserID = await SupabaseService.shared.currentUserID()
        members = (try? await GroupRepository.members(groupID: group.id)) ?? []
        streakWeeks = (try? await StreakRepository.groupStreak(groupID: group.id))?.currentStreak ?? 0
        crewDebts = (try? await SessionRepository.burpeeLedger(groupID: group.id)) ?? []
        campaign = try? await CampaignRepository.active(groupID: group.id)
        campaignLoaded = true

        let sessions = (try? await SessionRepository.groupSessions(groupID: group.id)) ?? []
        nextSession = sessions
            .filter { Self.upcomingStates.contains($0.state) }
            .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
            .first

        if let session = nextSession {
            commitments = (try? await CommitmentRepository.commitments(sessionID: session.id)) ?? []
            if let routineID = session.routineID,
               let (routine, exercises) = try? await RoutineRepository.fetch(id: routineID) {
                routineName = routine.name
                var names: [String] = []
                for exercise in exercises.prefix(2) {
                    names.append(await ExerciseNameCache.name(for: exercise.exerciseID))
                }
                let more = exercises.count - min(2, exercises.count)
                exerciseSummary = (names.joined(separator: " · ")
                    + (more > 0 ? " +\(more)" : "")).uppercased()
            } else {
                routineName = nil
                exerciseSummary = nil
            }
        } else {
            commitments = []
        }

        // "Routines together" derivation: there is no declaration table yet,
        // so declared = what the crew put on this week's calendar (completed
        // + still-scheduled this week). One plate per completed session.
        let calendar = Calendar.current
        let now = Date.now
        func inThisWeek(_ date: Date?) -> Bool {
            guard let date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        }
        let completed = sessions.filter { $0.state == "completed" && inThisWeek($0.scheduledFor) }.count
        let upcoming = sessions.filter { Self.upcomingStates.contains($0.state) && inThisWeek($0.scheduledFor) }.count
        completedThisWeek = completed
        plannedThisWeek = completed + upcoming

        let latest = (try? await ChatRepository.messages(groupID: group.id, limit: 3)) ?? []
        chatPreview = latest.reversed().compactMap { message in
            switch message.kind {
            case .image: return "Photo"
            case .audio: return "Voice message"
            case .text, .soundboardEcho, .systemPR, .systemSession, .systemLate, .systemLeaderboard:
                return message.body
            }
        }
    }

    // MARK: - Labels

    private static func whenLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }

    private static func countdownLabel(to date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "NOW" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "IN \(days) DAY\(days == 1 ? "" : "S") \(hours) HR\(hours == 1 ? "" : "S")" }
        if hours > 0 { return "IN \(hours) HR\(hours == 1 ? "" : "S")" }
        let minutes = max(seconds / 60, 1)
        return "IN \(minutes) MIN"
    }
}

// MARK: - CrewIronPlate

// One routine the crew completed together — always uniform iron (design
// value #53585F), never one member's color. 20×74 with chamfered edges:
// light on top/leading, dark on trailing/bottom.
private struct CrewIronPlate: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(roomHex: 0x53585F))
            .frame(width: 20, height: 74)
            .overlay(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.20)).frame(width: 1.5).padding(.vertical, 2)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(.black.opacity(0.38)).frame(width: 2).padding(.vertical, 2)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.09)).frame(height: 2).padding(.horizontal, 2)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.30)).frame(height: 2).padding(.horizontal, 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - GSPixelBannerShape

// A hung pixel-cloth banner: swallowtail cut, highlight band, shaded tails.
// Cloths are crew identity decor; chevrons join when the perfect-week
// system ships (drawing unearned ones would lie).
private struct GSPixelBannerShape: View {
    let cloth: Color

    var body: some View {
        ZStack(alignment: .top) {
            BannerCloth()
                .fill(cloth)
            BannerCloth()
                .stroke(.black.opacity(0.5), lineWidth: 1)
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 15, height: 13)
                .offset(y: 6)
        }
        .frame(width: 30, height: 45)
        .shadow(color: Color(roomHex: 0x0C0E11), radius: 0, x: 0, y: 3)
        .shadow(color: .black.opacity(0.4), radius: 4.5, x: 0, y: 7)
    }

    private struct BannerCloth: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width
            let h = rect.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.1, y: 0))
            path.addLine(to: CGPoint(x: w * 0.9, y: 0))
            path.addLine(to: CGPoint(x: w * 0.9, y: h))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.84))
            path.addLine(to: CGPoint(x: w * 0.1, y: h))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - CampaignCreateSheet

// Minimal real campaigns (owner decision 2026-08-11): name + weeks. The
// meter runs from these two numbers; trainer-lite content layers on later.
private struct CampaignCreateSheet: View {
    let group: GymGroup
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @State private var name = ""
    @State private var weeks = 8
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CAMPAIGN NAME")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .kerning(1.1)
                        .foregroundStyle(theme.neutral700)
                    TextField("Summer Campaign", text: $name)
                        .font(GSFont.body(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .tint(theme.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
                }
                Stepper(value: $weeks, in: 1...52) {
                    Text("\(weeks) WEEK\(weeks == 1 ? "" : "S")")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                }
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await create() }
                } label: {
                    Text(saving ? "STARTING…" : "START THE CAMPAIGN")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(16)
            .background(theme.bg)
            .navigationTitle("New Campaign")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
        }
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            try await CampaignRepository.create(groupID: group.id, name: name, weeks: weeks)
            onCreated()
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// GSTheme's `Color(hex:)` is fileprivate to its own file (GSAccent solves
// this the same way) — distinctly named to avoid ever colliding with it.
private extension Color {
    init(roomHex: UInt32) {
        let r = Double((roomHex >> 16) & 0xff) / 255.0
        let g = Double((roomHex >> 8) & 0xff) / 255.0
        let b = Double(roomHex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
