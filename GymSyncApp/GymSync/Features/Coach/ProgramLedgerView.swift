import SwiftUI

// MARK: - ProgramLedgerView
//
// The MY PROGRAM destination. Owner 2026-08-27: "It should open up into
// a catalogue or ledger of all my previous programming... if it's a
// completed program, then I should be able to open that up and have a
// conversation with coach about the performance, but if it's my current
// program, I should be at the very top set aside from the ledger."
//
// The current block is PINNED and opens the live schedule page (where
// you are, what's coming, the reasoning, the calendar). Every past
// block is a row in the ledger below — completed or abandoned, dated,
// honest — and opens an after-action conversation with Coach carrying
// that block's computed payload. Abandoned blocks are shown, not
// hidden: they are part of the story of what drove the next block.
struct ProgramLedgerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var enrollments: [ProgramEnrollment] = []
    @State private var loading = true
    /// A past block whose after-action thread is being prepared/pushed.
    @State private var aar: AARTarget?
    @State private var buildingAAR: UUID?
    /// A block was just built from the ledger; push a FRESH schedule
    /// page (the calendar's proven pattern).
    @State private var builtFromHere = false

    private struct AARTarget: Identifiable, Hashable {
        let id: UUID
        let title: String
        let opener: String
    }

    private var current: ProgramEnrollment? {
        enrollments.first { $0.endedAt == nil }
    }
    private var past: [ProgramEnrollment] {
        enrollments.filter { $0.endedAt != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().tint(theme.accent)
                        Text("READING YOUR LEDGER")
                            .font(GSFont.bold(13, relativeTo: .headline))
                            .tracking(0.9)
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gs3DCard(cornerRadius: GSMetrics.radiusSm)
                } else {
                    if let current {
                        currentCard(current)
                    } else {
                        noBlockCard
                    }

                    buildDoor

                    if !past.isEmpty {
                        Text("THE LEDGER")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.neutral500)
                            .padding(.top, 6)
                        ForEach(past) { enrollment in
                            pastRow(enrollment)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .navigationDestination(item: $aar) { target in
            CoachThreadLauncher(title: target.title, opener: target.opener)
                .background(theme.bg)
        }
        .navigationDestination(isPresented: $builtFromHere) {
            ProgramScheduleView()
                .background(theme.bg)
        }
    }

    // MARK: Current block — pinned, set aside from the ledger

    private func currentCard(_ enrollment: ProgramEnrollment) -> some View {
        let week = ProgramMath.currentWeek(startedOn: enrollment.startedOn,
                                           weeks: enrollment.weeks)
        return NavigationLink {
            ProgramScheduleView()
                .background(theme.bg)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CURRENT BLOCK")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                Text(displayName(enrollment))
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Week \(week) of \(enrollment.weeks) — where you are, what's coming, and the why behind it.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("SCHEDULE · CALENDAR · TALK IT OVER")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
    }

    private var noBlockCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO BLOCK ON THE BAR")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("Build one below and it takes this spot — the ledger keeps every block you finish.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// The way to the builder lives HERE now — MY PROGRAM opens the
    /// ledger, and building is one deliberate act inside it.
    private var buildDoor: some View {
        NavigationLink {
            CoachWizardView(onCreated: {
                builtFromHere = true
                return .handled
            })
            .background(theme.bg)
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(current == nil ? "BUILD A PROGRAM" : "PLAN THE NEXT BLOCK")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.6)
                    .foregroundStyle(theme.text)
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
    }

    // MARK: The ledger rows

    private func pastRow(_ enrollment: ProgramEnrollment) -> some View {
        Button {
            guard buildingAAR == nil else { return }
            buildingAAR = enrollment.id
            Task {
                defer { buildingAAR = nil }
                guard let userID = appState.currentProfile?.id else { return }
                let opener = await BlockAAR.payload(enrollment: enrollment,
                                                    userID: userID)
                aar = AARTarget(id: enrollment.id,
                                title: displayName(enrollment),
                                opener: opener)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(enrollment))
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(statusLine(enrollment))
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(enrollment.endedReason == "completed"
                                         ? theme.accent : theme.neutral500)
                }
                Spacer()
                if buildingAAR == enrollment.id {
                    ProgressView().tint(theme.accent)
                } else {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityLabel("\(displayName(enrollment)), \(statusLine(enrollment)) — open the after-action with Coach")
    }

    private func displayName(_ enrollment: ProgramEnrollment) -> String {
        let raw = enrollment.template?.name ?? enrollment.templateSlug
        return raw.hasPrefix("Coach · ")
            ? String(raw.dropFirst("Coach · ".count)) : raw
    }

    /// Honest per-row status. Abandoned blocks say where they stopped —
    /// they are evidence, not embarrassments.
    private func statusLine(_ enrollment: ProgramEnrollment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let started = formatter.string(from: enrollment.startedOn)
        guard let endedAt = enrollment.endedAt else {
            return "RUNNING — STARTED \(started.uppercased())"
        }
        let ended = formatter.string(from: endedAt)
        if enrollment.endedReason == "completed" {
            return "COMPLETED — \(started.uppercased()) TO \(ended.uppercased())"
        }
        let weeksRun = max(0, Calendar.current.dateComponents(
            [.weekOfYear], from: enrollment.startedOn, to: endedAt).weekOfYear ?? 0)
        return "ABANDONED WK \(min(weeksRun + 1, enrollment.weeks)) OF \(enrollment.weeks) — \(started.uppercased())"
    }

    private func load() async {
        enrollments = (try? await ProgramRepository.history()) ?? []
        loading = false
    }
}
