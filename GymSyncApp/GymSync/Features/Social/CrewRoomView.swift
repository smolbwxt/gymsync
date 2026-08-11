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

    // MARK: - Commit card: next lift + LET'S RIDE

    private var commitCard: some View {
        HStack(alignment: .center, spacing: 12) {
            if let session = nextSession {
                NavigationLink {
                    LobbyView(session: session)
                        .id(session.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LET'S RIDE")
                            .font(GSFont.bold(15, relativeTo: .headline))
                            .kerning(-0.2)
                        Text("TAP TO COMMIT")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .opacity(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .buttonStyle(GSPrimaryButtonStyle(verticalPadding: 0))

                VStack(alignment: .leading, spacing: 5) {
                    Text("NEXT LIFT")
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .kerning(-0.1)
                        .foregroundStyle(theme.text)
                    if let when = session.scheduledFor {
                        Text(Self.whenLabel(when).uppercased())
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(theme.neutral700)
                        Text(Self.countdownLabel(to: when).uppercased())
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .kerning(1.1)
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(theme.divider).frame(width: 1)
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
            }
        }
        .padding(13)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        members = (try? await GroupRepository.members(groupID: group.id)) ?? []
        streakWeeks = (try? await StreakRepository.groupStreak(groupID: group.id))?.currentStreak ?? 0
        crewDebts = (try? await SessionRepository.burpeeLedger(groupID: group.id)) ?? []

        let sessions = (try? await SessionRepository.groupSessions(groupID: group.id)) ?? []
        nextSession = sessions
            .filter { Self.upcomingStates.contains($0.state) }
            .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
            .first

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
