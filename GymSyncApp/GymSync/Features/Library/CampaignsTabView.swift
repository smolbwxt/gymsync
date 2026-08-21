import SwiftUI

// MARK: - CampaignsTabView
//
// Library's 4th sub-tab (Phase C Task 2) — completes the master spec's
// four-sub-tab Library structure (`docs/superpowers/specs/2026-06-28-
// gymsync-design.md:690`: "Routines / Exercises / Discover / Campaigns").
// Phase L Task 3 added Discover (3rd) and explicitly deferred this one
// ("Campaigns stays Phase C", `LibraryTabView.swift:6-8`) — this task is
// that deferral resolving. Same precedent this file follows for its own
// shape: `DiscoverView.swift` (Phase L Task 3's own sub-tab addition).
//
// Flow 8 (spec :864-865): "Library -> Campaigns sub-tab shows all active
// campaigns + a countdown to upcoming ones." No canvas frame exists for
// this screen — grepped `docs/design/frame-map.json` + every `.dc.html`
// canvas file for "campaign"/"Campaign": zero hits (same "undesigned ->
// system-designed + deviations" finding Discover's own entry already
// established as this repo's working pattern for an unbuilt Phase). See
// `docs/design/accepted-deviations.json`'s "campaigns-tab" entry.
//
// Row shape borrows `HomeView.upcomingCard`'s bordered-`GSCard` idiom
// (kicker + title + meta caption) rather than `LibraryTabView.packCard`'s
// image-first shelf card — a campaign has no artwork field in the schema
// (`banner_url` exists but no upload path was built for it; out of this
// task's scope) and reads better as a list row than a grid tile at this
// screen's own list-not-grid layout (matching Discover's grid choice would
// be the wrong precedent to copy — Discover's cards front an image
// placeholder that Flow 8 doesn't describe for this screen at all).
struct CampaignsTabView: View {
    @Environment(\.gsTheme) private var theme

    @State private var active: [Campaign] = []
    @State private var upcoming: [Campaign] = []
    @State private var past: [Campaign] = []
    @State private var loading = true
    @State private var errorText: String?

    // Training Programs P1 (2026-07-24-training-programs-design.md): the
    // self-assigned program surface shares this tab. Best-effort state — a
    // programs fetch failure never blanks the campaigns content (and vice
    // versa; see load()).
    @State private var programEnrollment: ProgramEnrollment?
    @State private var programFocusExercises: [Exercise] = []
    @State private var programSessionsThisWeek = 0
    // Program builder (docket #10): author a block from your own
    // routines - writes the same rows Coach's blocks write.
    @State private var showProgramBuilder = false

    #if DEBUG
    /// Debug-only: true only via the catalog fixture init below — skips
    /// `load()`'s live network fetch entirely, same idiom as `DiscoverView.
    /// catalogSkipLoad` (`Features/Library/DiscoverView.swift:32-41`).
    /// Always `false` on every other path; compiled out of release entirely.
    var catalogSkipLoad = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Full-screen loading/error only while the campaign lists are
                // EMPTY — `.task` re-fires on pop-back from a detail push, and
                // letting `loading` swap the populated scroller for a spinner
                // resets scroll to the top (ExercisesListView's afbb415 fix).
                if loading && active.isEmpty && upcoming.isEmpty && past.isEmpty {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 60)
                } else if let errorText, active.isEmpty && upcoming.isEmpty && past.isEmpty {
                    programSection
                    GSErrorCard(message: errorText) { Task { await load() } }
                        .padding(16)
                } else if active.isEmpty && upcoming.isEmpty && past.isEmpty {
                    programSection
                    // Campaigns-only empty copy — the programs section above
                    // means the tab itself is never truly empty anymore.
                    // `extruded` — static 3D card, matching the program
                    // cards above it (2026-08 3D pass).
                    GSEmptyState(
                        icon: "flag.checkered",
                        title: "No campaigns right now",
                        message: "Seasonal challenges will show up here when one opens.",
                        extruded: true
                    )
                    .padding(.top, 40)
                    .padding(.horizontal, 16)
                } else {
                    programSection
                    if !active.isEmpty {
                        GSSectionHeader("Active")
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 10)
                        ForEach(active) { campaign in
                            NavigationLink {
                                CampaignDetailView(campaign: campaign)
                            } label: {
                                campaignRow(campaign, trailing: "Active")
                            }
                            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                    if !upcoming.isEmpty {
                        GSSectionHeader("Upcoming")
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 10)
                        ForEach(upcoming) { campaign in
                            NavigationLink {
                                CampaignDetailView(campaign: campaign)
                            } label: {
                                campaignRow(campaign, trailing: countdownText(campaign))
                            }
                            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                    // "Past" — ended campaigns the user joined (Flow 8 :884's
                    // frozen final state stays reachable for participants).
                    // Opus pre-GA closeout: closes gate MINOR-2.
                    if !past.isEmpty {
                        GSSectionHeader("Past")
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 10)
                        ForEach(past) { campaign in
                            NavigationLink {
                                CampaignDetailView(campaign: campaign)
                            } label: {
                                campaignRow(campaign, trailing: "Ended")
                            }
                            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(theme.bg)
        // Dock clearance — on the ScrollView directly, not LibraryTabView's
        // Group (the Group cascade inflated Exercises' chips row).
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
    }

    // MARK: - Programs section (Training Programs P1)

    /// "Your program" card when enrolled, template gallery otherwise —
    /// always ABOVE the campaigns content (spec "UI" section).
    @ViewBuilder
    private var programSection: some View {
        if let enrollment = programEnrollment, let template = enrollment.template {
            GSSectionHeader("Your program")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            NavigationLink {
                ProgramDetailView(
                    enrollment: enrollment,
                    focusExercises: programFocusExercises,
                    sessionsThisWeek: programSessionsThisWeek,
                    onChanged: { Task { await load() } }
                )
            } label: {
                ProgramCard(
                    enrollment: enrollment,
                    template: template,
                    focusExercises: programFocusExercises,
                    sessionsThisWeek: programSessionsThisWeek
                )
            }
            // 3D pass (2026-08): tappable card — extruded face + lip +
            // press-sink. Bottom padding 6 → 10 so the 6pt lip doesn't
            // crowd the next card.
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        } else {
            GSSectionHeader("Start a program")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            ForEach(ProgramTemplate.all) { template in
                NavigationLink {
                    ProgramTemplateDetailView(
                        template: template,
                        onEnrolled: { Task { await load() } }
                    )
                } label: {
                    ProgramTemplateCard(template: template)
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        // Program builder door (docket #10): arrange your own routines
        // into a block - same rows, same shelf, same queue as Coach's.
        Button {
            showProgramBuilder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hammer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build your own")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("Arrange your routines into a multi-week program")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .sheet(isPresented: $showProgramBuilder) {
            ProgramBuilderSheet(onSaved: { Task { await load() } })
        }

        // THE PLAN — the macrocycle queue (generator wave). Self-contained:
        // renders nothing until the user has generated blocks or queue
        // entries, and its fetches never disturb the campaigns content.
        PlanQueueSection()
    }

    // MARK: - Row

    // 3D pass (2026-08): chrome comes from the NavigationLink's
    // `.gs3DCardStyle` — this is the LABEL only (the old internal GSCard
    // would have painted flat surface over the extruded face).
    private func campaignRow(_ campaign: Campaign, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CAMPAIGN")
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral700)
            Text(campaign.name)
                .font(GSFont.heading(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
            if let description = campaign.description, !description.isEmpty {
                Text(description)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(dateRangeText(campaign))
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                Text("·")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                Text(trailing)
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .foregroundStyle(theme.accent700)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func dateRangeText(_ campaign: Campaign) -> String {
        // Same `.dateTime` FormatStyle chain idiom as `HomeView.upcomingCard`
        // (`HomeView.swift:399`), just month+day (no weekday/time — a
        // campaign window is date-scale, not a specific moment).
        let start = campaign.startsAt.formatted(.dateTime.month(.abbreviated).day())
        let end = campaign.endsAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private func countdownText(_ campaign: Campaign) -> String {
        let days = campaign.daysUntilStart()
        if days <= 0 { return "Starts today" }
        return "Starts in \(days) day\(days == 1 ? "" : "s")"
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        errorText = nil
        do {
            let result = try await CampaignRepository.activeAndUpcoming()
            active = result.active
            upcoming = result.upcoming
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
        // Past challenges are additive — a failure here must never blank the
        // active/upcoming screen, so it's a best-effort fetch outside the
        // primary do/catch above (empty on failure, no error surfaced).
        past = (try? await CampaignRepository.endedParticipated()) ?? []

        // Programs (P1): best-effort, same isolation posture — a program
        // fetch failure degrades to the template gallery, never an error.
        programEnrollment = (try? await ProgramRepository.active()) ?? nil
        if let enrollment = programEnrollment {
            if let ids = enrollment.focus.exerciseIDs, !ids.isEmpty {
                let all = (try? await ExerciseRepository.fetchAll()) ?? []
                programFocusExercises = ids.compactMap { id in all.first { $0.id == id } }
            } else {
                programFocusExercises = []
            }
            if let userID = await SupabaseService.shared.currentUserID(),
               let history = try? await SessionRepository.history(userID: userID, limit: 60) {
                let week = ProgramMath.currentWeek(startedOn: enrollment.startedOn, weeks: enrollment.weeks)
                let window = ProgramMath.weekWindow(startedOn: enrollment.startedOn, week: week)
                programSessionsThisWeek = ProgramMath.sessionsCompleted(
                    completionDates: history.compactMap(\.completedAt),
                    window: window
                )
            }
        }
        loading = false
    }
}

// MARK: - Catalog fixture seam (`campaigns-tab` catalog case)

#if DEBUG
extension CampaignsTabView {
    /// Debug-only seam for the design-parity screen catalog: seeds
    /// `active`/`upcoming` directly and sets `catalogSkipLoad` so `load()`
    /// never fires its live fetch — same idiom as `DiscoverView`'s own
    /// `init(catalogFixtureWorkouts:catalogFixtureAttemptCounts:)`
    /// (`Features/Library/DiscoverView.swift:230-236`). A dedicated init
    /// (not the synthesized memberwise one) because `_active`/`_upcoming`
    /// are `private @State` — only reachable from an initializer in this
    /// same file.
    init(catalogFixtureActive active: [Campaign], catalogFixtureUpcoming upcoming: [Campaign] = [], catalogFixturePast past: [Campaign] = [],
         catalogFixtureProgram program: ProgramEnrollment? = nil,
         catalogFixtureProgramExercises programExercises: [Exercise] = [],
         catalogFixtureProgramSessions programSessions: Int = 0) {
        _active = State(initialValue: active)
        _upcoming = State(initialValue: upcoming)
        _past = State(initialValue: past)
        _programEnrollment = State(initialValue: program)
        _programFocusExercises = State(initialValue: programExercises)
        _programSessionsThisWeek = State(initialValue: programSessions)
        _loading = State(initialValue: false)
        catalogSkipLoad = true
    }
}
#endif
