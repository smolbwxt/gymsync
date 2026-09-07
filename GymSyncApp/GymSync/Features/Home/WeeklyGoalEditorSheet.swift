import SwiftUI

/// The week's goal, edited by the person whose week it is.
///
/// Design: `docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
/// -goal-design.md` §B, "The goal editor (tap the strip)". Plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-production-plan.md`, task C3.
///
/// Reached by tapping `HomeWeeklyGoalStrip` — including its invitation line,
/// which is the one state where there is no goal to edit yet and this sheet
/// is where the first one gets made.
///
/// **PROPOSE ONLY** (owner answer 3). Coach detects a goal and writes it with
/// `source = .coach`; once a person has set one, Coach may never overwrite
/// it. What it may do is ask, and this sheet is where the asking lands: a
/// `Proposal` replaces the header's copy line with Coach's own sentence and
/// an `ACCEPT` beside it. Accepting does not save — it switches the editor to
/// the kind Coach suggested and leaves the person in front of the levers,
/// with `SAVE THIS WEEK'S GOAL` still the thing that commits. A proposal that
/// wrote itself in would be an overwrite wearing a button.
///
/// **ONE ACCENT BUTTON** (design language rule 4). `SAVE THIS WEEK'S GOAL` is
/// the accent primary; `LET COACH SET IT` and `ACCEPT` are raised faces.
/// Everything between the header and the footer is FURNITURE and stays flat
/// (rule 1): the kind chips, the activity and type chips, the ± steppers, the
/// lift rows.
///
/// Hermetic by construction. Every input arrives through the initializer —
/// the goal, the repository, the proposal, the profile's standing weekly
/// goal, the focus lifts, the clock and the display unit — so a catalog
/// capture is a value, not a fetch. `loadsCatalog: false` is the one switch a
/// frame needs; with it the sheet makes no network call at all.
struct WeeklyGoalEditorSheet: View {

    // MARK: - Inputs

    /// A change Coach wants made to a goal the person already set.
    struct Proposal: Equatable, Sendable {
        /// What Coach would switch the week to. `ACCEPT` selects this kind
        /// in the editor; it does not save.
        let kind: WeeklyGoalKind
        /// The whole copy line, beginning "Coach suggests". It replaces the
        /// header's standing sentence rather than sitting under it: a sheet
        /// cannot both explain that Coach set this goal and ask to change
        /// the one you set instead.
        let sentence: String
        /// The goal Coach is actually proposing — the levers, not just the
        /// kind.
        ///
        /// `ACCEPT` seeds them. Without this a proposal was only a kind: a
        /// person who accepted "Coach suggests muscle sets" landed on six
        /// rows reading zero, which is not a suggestion, and one tap on the
        /// primary would have written a goal with no targets. Empty here is
        /// legal — the levers keep whatever they held and the primary stays
        /// disabled until they say something — but a proposal worth showing
        /// carries its numbers.
        var params: WeeklyGoalParams = WeeklyGoalParams()
    }

    /// One row of the lift picker: the block's focus lifts first, then the
    /// catalog. A flat value rather than an `Exercise` so a catalog frame can
    /// build the picker without a repository.
    struct LiftOption: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        /// The row's kicker — `FOCUS LIFT` for the block's own, else the
        /// muscle group the lift belongs to.
        let detail: String
    }

    /// This week's row, or nil when there is none yet (the strip's
    /// invitation state).
    let goal: WeeklyGoal?
    /// Whose week it is. Needed to build a `WeeklyGoal` when `goal` is nil;
    /// otherwise `goal.userID` and this must agree.
    let userID: UUID
    /// `WeekMath.weekStartString(_:)`'s value for the week being edited.
    /// Passed rather than computed so the sheet has no clock of its own.
    let weekStart: String
    /// Where a save goes. `StubWeeklyGoalRepository` until integration task
    /// I1 swaps the binding to Stream A's live one.
    var repository: any WeeklyGoalRepository = StubWeeklyGoalRepository()
    /// Coach's standing suggestion, when there is one.
    var proposal: Proposal? = nil
    /// The profile's **standing** weekly session goal — `Profile
    /// .weeklySessionGoal`, what next week will be, which is the value the
    /// streak sheet edits and the value this sheet's `days` stepper edits
    /// too.
    ///
    /// It is the seed for that stepper, and it is deliberately NOT
    /// `goal.params.count`: the `days` kind and the streak goal are ONE
    /// number, held in `profiles.weekly_session_goal`, and a second copy
    /// inside `weekly_goals.params` would let the two editors walk each
    /// other backwards. `WeeklyGoalSheet` (`HomeView.swift:1035`) seeds from
    /// exactly this field, with exactly this fallback, and says why: the
    /// standing goal "is the value being edited", not the effective one.
    var weeklySessionGoal: Int = 3
    /// The block's focus lifts, shown at the top of the lift picker.
    var focusLifts: [LiftOption] = []
    /// Whether to load the full exercise catalog behind the focus lifts.
    /// False in a catalog frame, which must not touch the network.
    var loadsCatalog: Bool = true
    /// The clock, injected. Stamps `setAt` on a save and frames the by-date
    /// picker; a fixture value makes the whole sheet deterministic.
    var today: Date = .now
    /// The display unit, for a frame that must not read a global.
    ///
    /// Nil — the shipping default — reads `ThemeStore.shared.weightUnit`,
    /// which is the live setting and the right answer on a device. It is
    /// overridable because frames 90 and 91 were otherwise the one input
    /// this sheet did not receive: today they render `MILES` and `lb`
    /// because a fresh simulator has no cached settings row and the store
    /// falls back to `.lbs`, which is deterministic by accident rather than
    /// by construction.
    var unitOverride: WeightUnit? = nil
    /// Called with the goal that now stands — the saved one, the re-derived
    /// one after `LET COACH SET IT`, or nil if that derivation produced
    /// nothing.
    /// **AND THE PROFILE, when the `days` lever wrote one** (final review
    /// finding 5). The `days` kind's number is `profiles.weekly_session_goal`
    /// — one column, two editors — and `WeeklyGoalSheet` hands its caller the
    /// updated `Profile` back (`HomeView.swift`'s `onSaved { profile =
    /// updated }`). This one used to discard it, so saving 5 here left Home's
    /// `profile` at the old value: reopen the sheet in the same visit and the
    /// stepper seeded from the stale number and would write it back. nil
    /// whenever no profile write happened, which is every other kind and a
    /// `days` save that did not move the stepper.
    var onSaved: (WeeklyGoal?, Profile?) -> Void = { _, _ in }

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var kind: WeeklyGoalKind
    @State private var muscleTargets: [MuscleGroup: Int]
    @State private var activity: String
    /// In the DISPLAY unit, which is what `WeeklyGoalParams.distanceTarget`
    /// stores (its own comment: "in the user's unit — mi with lbs, km with
    /// kg"). Nothing converts, because nothing is canonical.
    @State private var distanceTarget: Int
    @State private var sessionType: String
    @State private var sessionCount: Int
    @State private var dayCount: Int
    @State private var exerciseID: UUID?
    /// CANONICAL POUNDS, unlike the distance target — `Models/Units.swift`'s
    /// rule is that every stored weight is pounds, and
    /// `WeeklyGoalParams.targetWeightLbs` says so in its name. The stepper
    /// converts at the edge, in both directions.
    @State private var targetWeightLbs: Decimal
    @State private var byDate: Date
    @State private var catalog: [LiftOption] = []
    @State private var liftQuery = ""
    @State private var saving = false
    @State private var errorText: String?

    init(goal: WeeklyGoal?,
         userID: UUID,
         weekStart: String,
         repository: any WeeklyGoalRepository = StubWeeklyGoalRepository(),
         proposal: Proposal? = nil,
         weeklySessionGoal: Int = 3,
         focusLifts: [LiftOption] = [],
         loadsCatalog: Bool = true,
         today: Date = .now,
         unitOverride: WeightUnit? = nil,
         onSaved: @escaping (WeeklyGoal?, Profile?) -> Void = { _, _ in }) {
        self.goal = goal
        self.userID = userID
        self.weekStart = weekStart
        self.repository = repository
        self.proposal = proposal
        self.weeklySessionGoal = weeklySessionGoal
        self.focusLifts = focusLifts
        self.loadsCatalog = loadsCatalog
        self.today = today
        self.unitOverride = unitOverride
        self.onSaved = onSaved

        // Every lever is seeded, including the ones this goal's kind does
        // not use: switching from `days` to `a lift` must land on a usable
        // picker rather than on an empty one, and a lever the person never
        // visits is never written (see `params()`).
        let params = goal?.params ?? WeeklyGoalParams()
        _kind = State(initialValue: goal?.kind ?? .muscleSets)
        _muscleTargets = State(initialValue: Self.seedMuscleTargets(params))
        _activity = State(initialValue: params.activity ?? Self.activities[0])
        _distanceTarget = State(initialValue: Self.seedInt(params.distanceTarget, default: 15))
        _sessionType = State(initialValue: params.sessionType ?? Self.sessionTypes[0])
        // `count` is one column serving two kinds, so it is only this kind's
        // count when this kind is the one that wrote it.
        _sessionCount = State(initialValue: goal?.kind == .sessionsOfType ? (params.count ?? 3) : 3)
        // NEVER from `params.count` — see `weeklySessionGoal`. The profile's
        // standing goal is the number; the goal row does not hold a second
        // copy of it.
        _dayCount = State(initialValue: Self.clampDays(weeklySessionGoal))
        _exerciseID = State(initialValue: params.exerciseID ?? focusLifts.first?.id)
        _targetWeightLbs = State(initialValue: params.targetWeightLbs ?? 225)
        // Clamped forward: the picker's range is `today...`, and a goal whose
        // by-date has already passed would otherwise seed the selection
        // outside its own range — an ill-defined state on a real stale row.
        _byDate = State(initialValue: max(params.byDate ?? Self.defaultByDate(from: today), today))
    }

    // MARK: - Vocabulary
    //
    // The strings `WeeklyGoalParams` documents for `activity` and
    // `sessionType`, in the order the design's pickers list them. Declared
    // once here so the chips, the seed defaults and the saved params cannot
    // drift into three different spellings of "hiit".

    private static let activities = ["run", "bike", "row", "walk"]
    private static let sessionTypes = ["hiit", "mobility", "cardio", "class"]

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                kindChips
                levers
                if let errorText = errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
        .safeAreaInset(edge: .bottom) { footer }
        // `.large` because five kinds by six muscle rows does not fit
        // `.medium` (the plan says so, and the lift picker is taller still).
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Keyed on `kind` so the 1,300-row catalog is fetched when — and
        // only when — the lift picker is on screen. `RoutinePickerSheet`'s
        // own `ExerciseRepository.fetchAll()` is the precedent for the call;
        // the difference is that this sheet has four other kinds that never
        // need it.
        .task(id: kind) { await loadCatalogIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your goal this week")
                .font(GSFont.heading(20, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if let proposal = proposal {
                Text(proposal.sentence)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 0) {
                    Button { accept(proposal) } label: {
                        Text("ACCEPT")
                            .font(GSFont.bold(12, relativeTo: .caption))
                            .tracking(1.0)
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                    .accessibilityHint("Switches this week's goal to what Coach suggests. Nothing is saved until you save.")

                    Spacer(minLength: 0)
                }
            } else {
                // The design's copy line, verbatim.
                Text("Coach set this from your block. Change it here; Coach follows your lead for the rest of the week.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The kinds

    /// A segmented row: five equal chips, one per kind, in
    /// `WeeklyGoalKind`'s own order.
    ///
    /// Equal widths rather than a horizontal scroller, because a scroller
    /// puts `A LIFT` off the right edge of a 375 pt device — and off the
    /// right edge of the capture that is supposed to prove the lift editor
    /// renders. Flat, 999 radius, the selected one `theme.text` on
    /// `theme.neutral300`: chips are furniture (rule 1) and a selected chip
    /// is not a primary action.
    private var kindChips: some View {
        HStack(spacing: 6) {
            ForEach(WeeklyGoalKind.allCases, id: \.self) { candidate in
                chip(label: Self.chipLabel(candidate, unit: unit),
                     selected: candidate == kind) { kind = candidate }
            }
        }
    }

    /// `MUSCLE SETS · MILES · SESSIONS · DAYS · A LIFT`, the design's own
    /// list — except that the distance chip follows owner answer 2 rather
    /// than the design's literal word: a chip reading `MILES` on a device set
    /// to kilograms names a unit the rest of the screen does not use.
    private static func chipLabel(_ kind: WeeklyGoalKind, unit: WeightUnit) -> String {
        switch kind {
        case .muscleSets:     return "MUSCLE SETS"
        case .distance:       return unit == .kg ? "KM" : "MILES"
        case .sessionsOfType: return "SESSIONS"
        case .days:           return "DAYS"
        case .lift:           return "A LIFT"
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(selected ? theme.text : theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? theme.neutral300 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.pill))
                // An unselected chip carries a hairline so the row reads as a
                // segmented control rather than as one filled pill floating
                // in space. Concrete branch first, `nil` second — the shape
                // `HomeWeeklyGoalStrip.chipView`'s own optional overlay uses,
                // so the wrapped type is inferred from a real view rather
                // than from the empty side of the ternary.
                .overlay(
                    !selected
                        ? RoundedRectangle(cornerRadius: GSMetrics.pill)
                            .strokeBorder(theme.divider, lineWidth: 1)
                        : nil
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - The levers

    @ViewBuilder
    private var levers: some View {
        switch kind {
        case .muscleSets:     muscleLevers
        case .distance:       distanceLevers
        case .sessionsOfType: sessionLevers
        case .days:           dayLevers
        case .lift:           liftLevers
        }
    }

    /// Six rows, one per group, whatever the block asked for. All six are
    /// shown rather than only the tracked ones: a person adding chest to a
    /// pull-only week should not have to guess that the row exists, and a
    /// group at 0 simply is not written (`params()`).
    private var muscleLevers: some View {
        VStack(spacing: 8) {
            ForEach(MuscleGroup.allCases, id: \.self) { group in
                stepperRow(title: group.rawValue.uppercased(),
                           value: muscleTargets[group] ?? 0,
                           suffix: "SETS",
                           canDecrease: (muscleTargets[group] ?? 0) > 0,
                           canIncrease: (muscleTargets[group] ?? 0) < 40) { delta in
                    muscleTargets[group] = max(0, min(40, (muscleTargets[group] ?? 0) + delta))
                }
            }
        }
    }

    private var distanceLevers: some View {
        VStack(spacing: 8) {
            pickerRow(options: Self.activities, selection: activity) { activity = $0 }

            stepperRow(title: "TARGET",
                       value: distanceTarget,
                       suffix: unit == .kg ? "KM" : "MI",
                       canDecrease: distanceTarget > 1,
                       canIncrease: distanceTarget < 200) { delta in
                distanceTarget = max(1, min(200, distanceTarget + delta))
            }
        }
    }

    private var sessionLevers: some View {
        VStack(spacing: 8) {
            pickerRow(options: Self.sessionTypes, selection: sessionType) { sessionType = $0 }

            stepperRow(title: "PER WEEK",
                       value: sessionCount,
                       suffix: sessionCount == 1 ? "SESSION" : "SESSIONS",
                       canDecrease: sessionCount > 1,
                       canIncrease: sessionCount < 14) { delta in
                sessionCount = max(1, min(14, sessionCount + delta))
            }
        }
    }

    /// One stepper, and the anti-goalpost sentence the streak sheet already
    /// ships (`HomeView.WeeklyGoalSheet`), verbatim.
    ///
    /// **THE PROFILE IS THE NUMBER.** The `days` kind and the streak tile's
    /// weekly goal are one figure, and it lives in
    /// `profiles.weekly_session_goal`. This stepper edits that column and
    /// nothing else: it seeds from `weeklySessionGoal` (never from
    /// `params.count`), and a save writes it through
    /// `ProfileRepository.updateWeeklySessionGoal` — whose anti-goalpost
    /// snapshot lands the change NEXT week (owner 2026-08-12). The week's
    /// `weekly_goals` row still gets written, so the strip switches to the
    /// `days` reading straight away, but it carries **no `count`**: a second
    /// copy of one number, saved with a different effective date, is how the
    /// note below and the button above came to contradict each other.
    ///
    /// So the sentence is true as written, and it is the streak sheet's own
    /// sentence, word for word, because two editors of one number may not
    /// disagree about when it takes effect.
    ///
    /// The range is the design's 1–7 where the streak sheet's is 1–14 (it
    /// counts SESSIONS; this counts DAYS, and a week has seven). A standing
    /// goal above 7 therefore seeds clamped — and `save()` writes the
    /// profile only when the stepper actually moved, so opening this sheet
    /// on a 10-session goal and saving a different kind cannot quietly cut
    /// it to 7.
    private var dayLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepperRow(title: "PER WEEK",
                       value: dayCount,
                       suffix: dayCount == 1 ? "DAY" : "DAYS",
                       canDecrease: dayCount > 1,
                       canIncrease: dayCount < 7) { delta in
                dayCount = max(1, min(7, dayCount + delta))
            }

            Text("Takes effect next week. This week's goal stays locked — no moving the goalposts mid-week.")
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liftLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            liftPicker

            weightRow

            HStack(spacing: 8) {
                Text("BY")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.0)
                    .foregroundStyle(theme.neutral500)

                Spacer(minLength: 6)

                DatePicker("", selection: $byDate, in: today...,
                           displayedComponents: .date)
                    .labelsHidden()
                    .tint(theme.accent)
                    .font(GSFont.bold(14, relativeTo: .body))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        }
    }

    /// Focus lifts first, then the catalog — the plan's order, and the one
    /// that matters: the lift a block is built around is the lift a lift goal
    /// is nearly always about.
    ///
    /// A search field and a bounded inner scroll, because the catalog is over
    /// 1,300 rows (`ExerciseRepository.fetchAll()`'s own doc comment records
    /// why it pages). The cap is on what is DRAWN, not on what is searched.
    private var liftPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search lifts", text: $liftQuery)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                    .strokeBorder(theme.divider, lineWidth: 1))

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(visibleLifts) { option in
                        liftRow(option)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func liftRow(_ option: LiftOption) -> some View {
        let selected = option.id == exerciseID
        return Button { exerciseID = option.id } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(option.detail)
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(1.0)
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
            .overlay(
                selected
                    ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.accent, lineWidth: 1.5)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The target weight, stepped in the person's own unit and stored in
    /// pounds. `Units` converts at both edges — `fromPounds` to draw and to
    /// step, `toPounds` to keep — which is the whole of that file's contract
    /// (`Models/Units.swift:7-12`) and the reason a kg lifter's ladder has kg
    /// rungs rather than converted pound ones.
    private var weightRow: some View {
        stepperRow(title: "TARGET",
                   text: Units.format(pounds: targetWeightLbs, unit: unit),
                   canDecrease: Units.fromPounds(targetWeightLbs, to: unit) > unit.displayIncrement,
                   canIncrease: true) { delta in
            let step = unit.displayIncrement
            let current = Units.fromPounds(targetWeightLbs, to: unit)
            let next = Units.roundToIncrement(current + Decimal(delta) * step, unit: unit)
            targetWeightLbs = Units.toPounds(max(step, next), from: unit)
        }
    }

    // MARK: - Furniture

    /// A picker of short words as equal chips — the activity row and the
    /// session-type row are the same control with different vocabulary.
    private func pickerRow(options: [String], selection: String,
                           onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                chip(label: option.uppercased(), selected: option == selection) {
                    onSelect(option)
                }
            }
        }
    }

    private func stepperRow(title: String, value: Int, suffix: String,
                            canDecrease: Bool, canIncrease: Bool,
                            onStep: @escaping (Int) -> Void) -> some View {
        stepperRow(title: title, text: "\(value) \(suffix)",
                   canDecrease: canDecrease, canIncrease: canIncrease,
                   onStep: onStep)
    }

    /// Name on the left, reading in the middle, `−` and `+` on the right.
    /// Flat on `theme.surface`: a row inside a sheet is furniture, and rule 1
    /// spends extrusion on the object rather than on every row in it.
    private func stepperRow(title: String, text: String,
                            canDecrease: Bool, canIncrease: Bool,
                            onStep: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(text)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            stepButton(systemName: "minus", enabled: canDecrease) { onStep(-1) }
            stepButton(systemName: "plus", enabled: canIncrease) { onStep(1) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(text)")
    }

    private func stepButton(systemName: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? theme.text : theme.neutral500)
                .frame(width: 30, height: 30)
                .background(theme.neutral300)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "plus" ? "Increase" : "Decrease")
    }

    // MARK: - Footer

    /// `LET COACH SET IT` raised, `SAVE THIS WEEK'S GOAL` accent — one accent
    /// button on the sheet (rule 4). Stacked rather than side by side: the
    /// primary's label is twenty-one characters and half a phone is not
    /// enough of a button for it.
    ///
    /// The primary is GATED on the chosen kind being complete, and says why
    /// rather than only going dim — a disabled button with no reason is a
    /// dead end, and the two reachable degenerate goals (muscle sets with no
    /// groups, a lift with no lift) are both one tap away from a state the
    /// person can fix.
    private var footer: some View {
        VStack(spacing: 8) {
            if let incompleteReason = incompleteReason {
                Text(incompleteReason)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { Task { await letCoachSetIt() } } label: {
                Text("LET COACH SET IT")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(1.0)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
            .disabled(saving)

            Button { Task { await save() } } label: {
                Text(saving ? "SAVING…" : "SAVE THIS WEEK'S GOAL")
                    .font(GSFont.bold(14, relativeTo: .body))
                    .tracking(1.0)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
            .disabled(saving || incompleteReason != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(theme.bg)
    }

    // MARK: - Reads

    /// One read of the unit setting for the whole sheet —
    /// `AnchorEntryView.unit`'s idiom (:37), and the reason no label here
    /// spells "mi" or "lb" itself. An injected `unitOverride` wins, so a
    /// frame can be a value rather than a global.
    private var unit: WeightUnit { unitOverride ?? ThemeStore.shared.weightUnit }

    /// Why the primary is disabled, or nil when the goal is complete.
    ///
    /// Two kinds can be under-specified, and both were reachable:
    ///
    ///   * **muscle sets with no groups.** The rows seed only from the
    ///     EXISTING goal's params, so switching to `MUSCLE SETS` from any
    ///     other kind leaves all six at zero — the path `ACCEPT` opened
    ///     before proposals carried their levers. `params()` would have
    ///     written `muscleTargets = [:]`, which the strip renders as a
    ///     kicker row over an empty chip row.
    ///   * **a lift with no lift.** `exerciseID` is nil when the block has
    ///     no focus lifts and the catalog has not returned; a goal with a
    ///     target weight, a date and no exercise is one Stream A cannot
    ///     compute an e1RM against.
    ///
    /// `distance`, `sessionsOfType` and `days` cannot be incomplete: every
    /// lever they use is seeded to a legal value and the steppers are
    /// bounded away from zero.
    private var incompleteReason: String? {
        switch kind {
        case .muscleSets:
            return muscleTargets.values.contains { $0 > 0 }
                ? nil
                : "Give at least one muscle group a target."
        case .lift:
            return exerciseID == nil ? "Pick the lift this goal is about." : nil
        case .distance, .sessionsOfType, .days:
            return nil
        }
    }

    /// Focus lifts first, then the catalog with the focus lifts removed so
    /// nothing appears twice, then a display cap.
    private var visibleLifts: [LiftOption] {
        let query = liftQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let focusIDs = Set(focusLifts.map(\.id))
        let rest = catalog.filter { !focusIDs.contains($0.id) }
        let all = focusLifts + rest
        let matched = query.isEmpty ? all : all.filter { $0.name.lowercased().contains(query) }
        return Array(matched.prefix(40))
    }

    // MARK: - Writes

    /// `ACCEPT` — select the kind Coach proposed AND seed the levers it
    /// proposed with it. Still no save: propose-only means the person is
    /// left in front of the levers with `SAVE THIS WEEK'S GOAL` the only
    /// thing that commits (owner answer 3).
    ///
    /// Seeding is what makes accepting an answer rather than a jump. Before
    /// it, accepting "Coach suggests muscle sets" landed on six rows reading
    /// zero — a suggestion with nothing in it, one tap from a goal with no
    /// targets. A field the proposal does not carry is left alone rather
    /// than reset, so accepting cannot wipe a lever the person already set.
    ///
    /// `days` seeds nothing on purpose: that number is the profile's, and a
    /// proposal does not get to move it (`dayLevers`).
    private func accept(_ proposal: Proposal) {
        kind = proposal.kind
        let params = proposal.params

        switch proposal.kind {
        case .muscleSets:
            let seeded = Self.seedMuscleTargets(params)
            if !seeded.isEmpty { muscleTargets = seeded }
        case .distance:
            if let activity = params.activity { self.activity = activity }
            if let target = params.distanceTarget {
                // I1 (review-stream-C-r1.md residual nit 2): clamped to the
                // stepper's own 1...200 range (`:380`) — `seedInt` alone only
                // rejects non-finite/non-positive/`>= 1_000` values, which
                // left a 201...999 proposal writing a value the stepper
                // itself can never reach or step back down from.
                distanceTarget = max(1, min(200, Self.seedInt(target, default: distanceTarget)))
            }
        case .sessionsOfType:
            if let sessionType = params.sessionType { self.sessionType = sessionType }
            if let count = params.count { sessionCount = max(1, min(14, count)) }
        case .days:
            break
        case .lift:
            if let exerciseID = params.exerciseID { self.exerciseID = exerciseID }
            // I1 (residual nit 2): the weight stepper (`:555`) has no upper
            // bound of its own — `canIncrease` is unconditionally `true` —
            // so the only real invariant to enforce here is the one the
            // stepper's own `canDecrease` gate enforces: positive and
            // finite. An unvalidated proposal could otherwise write zero,
            // negative, NaN or infinite pounds.
            if let weight = params.targetWeightLbs, weight.isFinite, weight > 0 {
                targetWeightLbs = weight
            }
            if let byDate = params.byDate { self.byDate = max(byDate, today) }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        errorText = nil

        let edited = WeeklyGoal(userID: goal?.userID ?? userID,
                                weekStartString: weekStart,
                                kind: kind,
                                params: params(),
                                source: .user,
                                setAt: today)
        guard await repository.save(edited) else {
            errorText = "That didn't save. Check your connection and try again."
            return
        }

        // ONE SOURCE OF TRUTH for the days number. The row above carries
        // `kind = .days` and NO count; the number itself lives in
        // `profiles.weekly_session_goal` and is written here, through the
        // same static the streak sheet calls, so both editors inherit the
        // one anti-goalpost snapshot and the note beside the stepper stays
        // true.
        //
        // Only when the stepper actually moved. The design's range is 1–7
        // and the profile's is 1–14, so a person holding themselves to ten
        // sessions a week sees this stepper seeded at seven; writing that
        // back unasked would cut their goal for opening a sheet.
        //
        // Best-effort, like every other Coach-adjacent write: a goal that
        // saved must not be reported as a failure because a second, slower
        // write did not land.
        //
        // The updated `Profile` is HANDED BACK rather than dropped (final
        // review finding 5): Home holds one, `WeeklyGoalSheet` already
        // returns one for this same column, and the two editors of one number
        // have to leave the caller holding the same number.
        var updatedProfile: Profile? = nil
        if kind == .days, dayCount != Self.clampDays(weeklySessionGoal) {
            updatedProfile = try? await ProfileRepository.updateWeeklySessionGoal(dayCount)
        }

        onSaved(edited, updatedProfile)
        dismiss()
    }

    /// The footer's other half: delete the row and let detection re-derive
    /// it. `source` goes back to `.coach`, which is what makes Coach free to
    /// write this week again.
    ///
    /// **This one cannot report a failure, and that is the interface, not an
    /// oversight.** `clearToCoach` returns `WeeklyGoal?` and does not throw
    /// (`WeeklyGoalRepository` is `async` with no `throws` on purpose — every
    /// Home fetch in this app is best-effort). So a nil means either "the row
    /// is gone and detection produced nothing" or "the network dropped", and
    /// nothing here can tell them apart. Rather than invent an error message
    /// that might be a lie, it hands `onSaved(nil, nil)` back and dismisses: Home
    /// re-reads on its next refresh, and the strip shows whatever actually
    /// stands. If the two ever need distinguishing, the protocol has to say
    /// so first — that is Stream A's file, and I1's call.
    private func letCoachSetIt() async {
        saving = true
        defer { saving = false }
        errorText = nil

        let derived = await repository.clearToCoach(weekStart: weekStart)
        // No profile write on this path — LET COACH SET IT re-derives the
        // goal row and never touches `profiles.weekly_session_goal`.
        onSaved(derived, nil)
        dismiss()
    }

    /// Only the chosen kind's fields are written. `WeeklyGoalParams` encodes
    /// with `encodeIfPresent`, so a `distance` goal persists
    /// `{"activity":"run","distanceTarget":15}` and not seven nulls beside
    /// it — and a lift the person picked while browsing does not ride along
    /// inside it.
    ///
    /// **`days` writes NOTHING.** Its params are empty on purpose: the number
    /// is `profiles.weekly_session_goal` and there is exactly one of it (see
    /// `dayLevers`). The row still says `kind = .days`, which is all the
    /// strip needs to switch readings; A4 reads the target from
    /// `Profile.effectiveWeeklyGoal`.
    ///
    /// `targetSource` is left nil on every user save. Its documented values
    /// are `"titration"` and `"routines"`, and both describe where COACH got
    /// a number; carrying the old one forward would claim the block chose
    /// targets the person just typed over.
    private func params() -> WeeklyGoalParams {
        var params = WeeklyGoalParams()
        switch kind {
        case .muscleSets:
            var targets: [String: Int] = [:]
            for (group, sets) in muscleTargets where sets > 0 {
                targets[group.rawValue] = sets
            }
            params.muscleTargets = targets
        case .distance:
            params.activity = activity
            params.distanceTarget = Double(distanceTarget)
        case .sessionsOfType:
            params.sessionType = sessionType
            params.count = sessionCount
        case .days:
            break
        case .lift:
            params.exerciseID = exerciseID
            params.targetWeightLbs = targetWeightLbs
            params.byDate = byDate
        }
        return params
    }

    private func loadCatalogIfNeeded() async {
        guard loadsCatalog, kind == .lift, catalog.isEmpty else { return }
        let rows = (try? await ExerciseRepository.fetchAll()) ?? []
        catalog = rows
            // Aliases resolve history but must not appear in a picker — the
            // same exclusion `Exercise.aliasOf`'s own comment describes for
            // the generator's selection pool.
            .filter { $0.aliasOf == nil }
            .map { exercise in
                LiftOption(id: exercise.id,
                           name: exercise.name,
                           detail: MuscleGroup.group(exercise.primaryMuscle)?.rawValue.uppercased()
                               ?? exercise.primaryMuscle.uppercased())
            }
    }

    // MARK: - Seeds

    private static func seedMuscleTargets(_ params: WeeklyGoalParams) -> [MuscleGroup: Int] {
        var seeded: [MuscleGroup: Int] = [:]
        for (raw, sets) in params.muscleTargets ?? [:] {
            guard let group = MuscleGroup(rawValue: raw.lowercased()) else { continue }
            seeded[group] = max(0, min(40, sets))
        }
        return seeded
    }

    private static func seedInt(_ value: Double?, default fallback: Int) -> Int {
        guard let value = value, value.isFinite, value > 0, value < 1_000 else { return fallback }
        return Int(value.rounded())
    }

    /// The profile's standing goal, brought into the `days` stepper's range.
    /// Used for the seed AND for the "did the stepper move?" comparison in
    /// `save()`, so the two can never diverge.
    private static func clampDays(_ goal: Int) -> Int { max(1, min(7, goal)) }

    /// Six weeks out — a block's length, and the horizon a lift goal is
    /// written against when the person has not named one.
    private static func defaultByDate(from today: Date) -> Date {
        today.addingTimeInterval(6 * 7 * 24 * 60 * 60)
    }
}
