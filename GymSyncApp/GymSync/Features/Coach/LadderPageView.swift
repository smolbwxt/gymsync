import SwiftUI

// MARK: - LadderPageView
//
// Spec: docs/superpowers/specs/2026-09-07-goal-first-programming-design.md
// §6, top to bottom, in the order it lists. Plan:
// docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md, task D1.
//
// The page the Home strip opens when the week's row belongs to a ladder
// (task D2). It renders a `LadderPageModel` — already worded upstream — and
// does no arithmetic of its own, for the same reason `HomeWeeklyGoalStrip`
// does none: the ladder page, the schedule card and Coach's line must not be
// three opinions about one block.
//
// **NO GOLD ANYWHERE ON THIS PAGE** (design rule 2). Gold has exactly two
// jobs — the week-streak number and the check-in window — and neither is
// here. `LadderRowStyleTests` asserts it, and asserts that no branch is red
// either: a missed week is a fact, not an error.
//
// **ONE ACCENT PRIMARY** (rule 4): the save. `LET COACH RE-LADDER` and the
// three edit levers are raised faces; `SEE THE BLOCK` is a quiet strip.

struct LadderPageView: View {

    // MARK: - Inputs

    let goalID: UUID
    /// Where the page reads from. `LiveBlockGoalRepository` (Stream A's A11)
    /// as of integration task I1's swap; `StubBlockGoalRepository` stays in
    /// the codebase for the catalog captures, which always pass a `world:`
    /// and never reach this default (see the file header).
    var repository: any BlockGoalRepository = LiveBlockGoalRepository()
    /// Rendered directly when present — the catalog's hermetic path, the same
    /// `world` seam `CalendarSchedulingView` grew for the identical reason.
    /// With one set, `load()` returns without touching the repository, so a
    /// frame is a value rather than a fetch.
    var world: LadderPageModel? = nil
    /// The milestone and its date. ONE closure for both levers on purpose:
    /// the milestone and the date it is due are one object (spec §2.1, and
    /// the door composes them together in §5), so two closures would promise
    /// two screens where there is one. I1 raises the milestone editor.
    var onEditMilestone: () -> Void = {}
    /// This week's rung — the shipped `WeeklyGoalEditorSheet`, scoped by the
    /// `RungContext` task D3 gave it.
    var onEditRung: () -> Void = {}

    @Environment(\.gsTheme) private var theme

    // MARK: - State

    /// What `load()` read. `resolved` prefers `world`, so a catalog frame
    /// never depends on this being filled.
    @State private var fetched: LadderPageModel?
    /// The milestone row behind the page, when this page is showing the goal
    /// that row belongs to. Only ever the goal whose id this page was opened
    /// for — a ladder page for a PAST block must never save over the active
    /// block's milestone.
    @State private var goal: BlockGoal?
    @State private var loading = true
    @State private var reLaddering = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var coachThread: CoachOpener?

    /// Coach's line opens a seeded thread (design rule 7). `Identifiable` so
    /// it can drive `navigationDestination(item:)`.
    private struct CoachOpener: Identifiable, Hashable {
        let id: String
        let title: String
        let opener: String
    }

    private var resolved: LadderPageModel? { world ?? fetched }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let page = resolved {
                    milestoneHeader(page)
                    coachLine(page)
                    ladderCard(page)
                    levers
                    saveRow
                    seeTheBlock
                } else if loading {
                    loadingCard
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle("The ladder")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(item: $coachThread) { opener in
            CoachThreadLauncher(title: opener.title, opener: opener.opener)
                .background(theme.bg)
        }
    }

    // MARK: - 1 and 2: the milestone, and the date

    /// The milestone IS the headline — the largest thing on the page (rule
    /// 3). The date sits under it and is **absent entirely** when empty: a
    /// held-for-the-block goal has no date, and a blank line is not a state.
    @ViewBuilder
    private func milestoneHeader(_ page: LadderPageModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(page.headline)
                .font(GSFont.heading(26, relativeTo: .title))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if !page.dateLine.isEmpty {
                Text(page.dateLine)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    // MARK: - 3: Coach's one line on standing

    /// One line, first person, tappable, opening a seeded thread (rule 7).
    ///
    /// **Accent only when the ladder cannot reach the milestone.** That line
    /// is an invitation to act — move the date, lower the target, or accept
    /// the gap — which is one of accent's three jobs (rule 2). "On track" is
    /// a readout, and a readout in accent would spend the page's one
    /// invitation on good news.
    @ViewBuilder
    private func coachLine(_ page: LadderPageModel) -> some View {
        if !page.coachLine.isEmpty {
            Button {
                coachThread = CoachOpener(id: goalID.uuidString,
                                          title: page.headline,
                                          opener: page.coachLine)
            } label: {
                HStack(spacing: 8) {
                    Text(page.coachLine)
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(page.reachesMilestone ? theme.neutral700 : theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coach: \(page.coachLine). Talk it through.")
        }
    }

    // MARK: - 4: the ladder

    /// ONE raised card with the weeks inside it flat (rule 1: one raised
    /// object per idea; furniture inside a raised box stays flat). The rows
    /// are separated by the divider rather than by extrusion, so the card
    /// reads as one ladder and not as eight tiles.
    private func ladderCard(_ page: LadderPageModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE LADDER")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
                Spacer()
                Text("WEEK \(page.weekNumber) OF \(page.weekCount)")
                    .font(GSFont.bold(10, relativeTo: .caption2).monospacedDigit())
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ForEach(Array(page.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
                ladderRow(row)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // CARD radius, not small-card (task review finding 7). Rule 1's
        // scale is "cards 24, small cards 16, strips 14, chips 999", and this
        // is the page's principal object — eight rows, the whole ladder, the
        // thing the page is named for. The coach line and SEE THE BLOCK stay
        // at the strip's 14, which is what they are.
        //
        // `LadderCard` on the schedule page keeps 16 deliberately: three rows
        // and a footer, sitting in a column of other cards, is a small card
        // by the same scale.
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    /// Week number and the target in words on the left, the implication
    /// under it, the status on the right.
    private func ladderRow(_ row: LadderRow) -> some View {
        let style = Self.style(for: row.status, theme: theme)
        let kicker = Self.kicker(for: row.status, isDeload: row.isDeload)
        let word = Self.statusWord(for: row.status)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // A KICKER, so design rule 3 governs it: "10 to 11 pt
                    // caps with 0.1 to 0.13 em tracking, in `muted`; a kicker
                    // turns `text` only when it is the CURRENT one." It used
                    // to take `style.ink` wholesale, which put weeks 4, 5, 7
                    // and 8 in the same full-strength white as week 3 and
                    // left the ring doing the entire job of marking the
                    // current rung. `met` keeps its green — rule 2's "green
                    // means done" is a fair override, and it is the one
                    // status whose colour IS the fact.
                    Text("WEEK \(row.weekNumber)")
                        .font(GSFont.bold(10, relativeTo: .caption2).monospacedDigit())
                        .tracking(1.1)
                        .foregroundStyle(Self.kickerInk(for: row.status, theme: theme))
                    if !kicker.isEmpty {
                        Text(kicker)
                            .font(GSFont.bold(9, relativeTo: .caption2))
                            .tracking(1.0)
                            .foregroundStyle(theme.neutral500)
                    }
                }
                Text(row.targetText)
                    .font(GSFont.bold(15, relativeTo: .body).monospacedDigit())
                    .foregroundStyle(style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let implication = row.implication {
                    Text(implication)
                        .font(GSFont.body(11, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(theme.neutral500)
                }
                // The generator's own decision-log line, pulled through
                // `Program.notes` (A12) — spec §6: "so the ladder says why a
                // week is what it is".
                if let note = row.note {
                    Text(note)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !word.isEmpty {
                Text(word)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(style.ink)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(rowRing(style))
        .accessibilityElement(children: .combine)
    }

    /// The current rung's 1.5 pt accent ring — accent's "current item in a
    /// pager" job, and the only accent inside the card.
    @ViewBuilder
    private func rowRing(_ style: RowStyle) -> some View {
        if let ring = style.ring {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ring, lineWidth: 1.5)
                .padding(.horizontal, 6)
        }
    }

    // MARK: - 5: the levers

    /// What the athlete owns (spec §6). Raised faces, because they are
    /// things you press and none of them is the page's primary.
    private var levers: some View {
        VStack(spacing: 8) {
            lever("EDIT THE MILESTONE", glyph: "target", action: onEditMilestone)
            lever("EDIT THE DATE", glyph: "calendar", action: onEditMilestone)
            lever("EDIT THIS WEEK'S RUNG", glyph: "slider.horizontal.3", action: onEditRung)
            lever(reLaddering ? "RE-LADDERING…" : "LET COACH RE-LADDER",
                  glyph: "arrow.triangle.2.circlepath") {
                Task { await reLadder() }
            }
        }
    }

    private func lever(_ title: String, glyph: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.6)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .disabled(reLaddering)
    }

    // MARK: - 6: the save

    /// The page's ONE accent primary (rule 4).
    ///
    /// It commits the milestone this page is showing, through the repository
    /// surface whose contract is that a save from here "always stamps
    /// `source = .user`" — the milestone and its date belong to the athlete
    /// (owner decision 8). It is INERT when there is no goal behind the page:
    /// a catalog frame renders from `world` and never fetched one, exactly as
    /// `HomeWeeklyGoalStrip`'s tap is inert in a frame.
    private var saveRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await save() }
            } label: {
                Text(saving ? "SAVING…" : "SAVE THE MILESTONE")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle())
            .disabled(saving || reLaddering)
            if let errorText {
                Text(errorText)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 7: the block, one tap away

    /// A quiet strip, not a card: the schedule is one tap from the landing
    /// (task C3), and this row is a door rather than an object to read.
    private var seeTheBlock: some View {
        NavigationLink {
            blockSchedule()
                .background(theme.bg)
                .navigationTitle("Program schedule")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 8) {
                Text("SEE THE BLOCK")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: - The two states that are not a ladder

    /// Says one true thing and no numbers — `ProgramScheduleView
    /// .loadingCard`'s own rule: a placeholder ladder would be a fiction in
    /// the one moment the athlete is least equipped to notice.
    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(theme.accent)
            Text("READING YOUR LADDER")
                .font(GSFont.bold(13, relativeTo: .headline))
                .tracking(0.9)
                .foregroundStyle(theme.neutral700)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO LADDER HERE")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("This block has no goal on it yet. Set one and Coach builds the weeks toward it.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// The block's schedule page, built with **this page's** repository
    /// (task review finding 2).
    ///
    /// The same drop `HomeView.ladderPage(for:)` fixes, one hop further out:
    /// this used to be a bare `ProgramScheduleView()`, discarding the
    /// repository the ladder page itself was handed. Home → ladder → schedule
    /// → ladder is a real path, and every hop of it now carries one
    /// repository, so I1 swaps them all together by changing one default.
    ///
    /// A FUNCTION for the same reason `ladderPage(for:)` is one: the wiring
    /// becomes a value a test can hold.
    func blockSchedule() -> ProgramScheduleView {
        ProgramScheduleView(goalRepository: repository)
    }

    // MARK: - The status -> style mapping (LadderRowStyleTests)

    /// One row's colours. A value rather than a set of modifiers so the
    /// mapping can be asserted without a view — `LadderRowStyleTests`.
    struct RowStyle: Equatable {
        /// The week number, the target and the status word all wear this.
        let ink: Color
        /// The ring around the row, or nil for every rung but the current
        /// one.
        let ring: Color?
    }

    /// Spec §6's table, and design rule 2 throughout: green means done, a
    /// missed week is muted because it is a fact, accent marks the current
    /// item, and **red appears in no branch**.
    ///
    /// It takes the palette rather than reading one: a `static` cannot see
    /// `@Environment(\.gsTheme)`, and a defaulted palette would let a caller
    /// silently draw midnight's greys on the ink theme.
    static func style(for status: RungStatus, theme: GSTheme) -> RowStyle {
        switch status {
        case .met:
            return RowStyle(ink: Color.gsSuccess, ring: nil)
        case .missed, .overridden:
            return RowStyle(ink: theme.neutral500, ring: nil)
        case .current:
            return RowStyle(ink: theme.text, ring: theme.accent)
        case .ahead:
            return RowStyle(ink: theme.text, ring: nil)
        }
    }

    /// The ink for a row's `WEEK n` kicker, which is **not** the ink for its
    /// target text (task review finding 4).
    ///
    /// Design rule 3 gives kickers their own colour law — `muted`, turning
    /// `text` only for the current one — and it is what buys the scan-down
    /// hierarchy on a page of eight rungs. `style(for:)` answers for the row
    /// as a whole and is unchanged, so `LadderRowStyleTests` still asserts
    /// what it asserted.
    ///
    /// `met` keeps `style.ink`'s green: rule 2's "green means done" is a fair
    /// override of rule 3, because it is the one status whose colour IS the
    /// fact rather than a weight.
    static func kickerInk(for status: RungStatus, theme: GSTheme) -> Color {
        switch status {
        case .met:     return Color.gsSuccess
        case .current: return theme.text
        case .ahead, .missed, .overridden: return theme.neutral500
        }
    }

    /// The kicker beside the week number, or `""` when the row has nothing
    /// extra to say.
    ///
    /// DELOAD leads when a row is both: it is a fact about the WEEK — the
    /// block's own shape, which spec §3.2 says the ladder must not smooth
    /// away — where YOURS is a fact about who typed the number. A row wears
    /// one kicker, and the muted ink already says the rung is not Coach's.
    static func kicker(for status: RungStatus, isDeload: Bool) -> String {
        if isDeload { return "DELOAD" }
        if status == .overridden { return "YOURS" }
        return ""
    }

    /// The word on the right of a row. `overridden` says nothing here — its
    /// YOURS kicker already did, and one fact stated twice reads as two.
    static func statusWord(for status: RungStatus) -> String {
        switch status {
        case .met:        return "MET"
        case .missed:     return "MISSED"
        case .current:    return "THIS WEEK"
        case .ahead:      return ""
        case .overridden: return ""
        }
    }

    // MARK: - Reads and writes

    /// **A `world` short-circuits every read.** With one injected the page is
    /// a value, so a catalog capture never opens a socket and never depends
    /// on the day CI runs.
    private func load() async {
        guard world == nil else {
            loading = false
            return
        }
        let model = await repository.page(goalID: goalID)
        let active = await repository.activeGoal()
        fetched = model
        // Only the goal this page was OPENED for. `activeGoal()` answers for
        // the active enrollment, which is not necessarily the block whose
        // ladder is on screen; saving the wrong one would move a milestone
        // the athlete is not looking at.
        goal = active?.id == goalID ? active : nil
        loading = false
    }

    /// LET COACH RE-LADDER: re-derive the remaining rungs from actuals. The
    /// repository rewrites only `ahead` and `current` rungs (spec §8), so a
    /// missed or overridden week stays visible — which is why the page simply
    /// re-reads afterwards rather than patching rows itself.
    /// **THE WORLD GUARD IS FIRST**, and that is the fix for task review
    /// finding 5. `reLadder(goalID:)` is a PERSISTING write — the protocol
    /// says so at `BlockGoalRepository.swift:30-33` — and this used to call
    /// it and only then check for a world. The seam's contract, stated in
    /// this file's header and repeated in `CatalogHostView`, is that a page
    /// with a world "never opens a socket"; the guard was protecting the
    /// re-read and leaving the write outside it. Inert today only because the
    /// catalog's repository happens to be the stub and no tap occurs in a
    /// capture — which is luck, not enforcement.
    private func reLadder() async {
        guard world == nil else { return }
        reLaddering = true
        defer { reLaddering = false }
        _ = await repository.reLadder(goalID: goalID)
        fetched = await repository.page(goalID: goalID)
    }

    /// The other write on this page, and it is world-safe **structurally**
    /// rather than by a guard: `goal` is set only in `load()`, which returns
    /// before it reads anything when a world is present, so a catalog frame
    /// can never hold one and this returns on the line below. Recorded here
    /// so the next reader does not have to re-derive it and add a guard that
    /// looks necessary — the one in `reLadder()` is, this one is not.
    private func save() async {
        guard let goal else { return }
        saving = true
        defer { saving = false }
        errorText = nil
        guard await repository.save(goal) else {
            errorText = "That didn't save. Check your connection and try again."
            return
        }
    }
}
