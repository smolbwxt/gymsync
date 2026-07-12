import SwiftUI

// MARK: - SessionRecapView
//
// Canvas design (STEP 3 — Recap):
//   • Hero banner: accent fill, session name + elapsed duration + date + lifter count
//   • Per-participant rows: sets count, volume (Σ reps×weight, excluding is_penalty), penalty reps separate
//   • Done button → onDone closure (dismisses to root via the presenter)

struct SessionRecapView: View {
    let session: WorkoutSession
    let sets: [SetLog]
    let participants: [(participant: SessionParticipant, profile: Profile)]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    // MARK: - Computed stats

    private struct ParticipantStats {
        let profile: Profile
        let participant: SessionParticipant
        let setCount: Int
        let volume: Double            // Σ reps×weight, no penalty sets
        let penaltyReps: Int          // sum of reps in is_penalty rows
    }

    private var stats: [ParticipantStats] {
        participants.map { item in
            let mySets = sets.filter { $0.userID == item.participant.userID }
            let workSets = mySets.filter { !$0.isPenalty }
            let volume = workSets.reduce(0.0) { acc, log in
                guard !log.isFailed, let r = log.reps, let w = log.weight else { return acc }
                return acc + Double(r) * NSDecimalNumber(decimal: w).doubleValue
            }
            let penaltyReps = mySets.filter(\.isPenalty).compactMap(\.reps).reduce(0, +)
            return ParticipantStats(
                profile: item.profile,
                participant: item.participant,
                setCount: workSets.count,
                volume: volume,
                penaltyReps: penaltyReps
            )
        }
        .sorted { $0.volume > $1.volume }   // descending volume = leaderboard order
    }

    private var duration: TimeInterval {
        guard let start = session.startedAt, let end = session.completedAt else { return 0 }
        return max(0, end.timeIntervalSince(start))
    }

    private var durationString: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .none
        return (session.completedAt ?? session.startedAt).map { fmt.string(from: $0) } ?? ""
    }

    private var totalSets: Int { sets.filter { !$0.isPenalty }.count }

    private var totalVolume: Double {
        sets.filter { !$0.isPenalty }.reduce(0.0) { acc, log in
            guard !log.isFailed, let r = log.reps, let w = log.weight else { return acc }
            return acc + Double(r) * NSDecimalNumber(decimal: w).doubleValue
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── HERO BANNER ──────────────────────────────────────
                    heroBanner
                        .padding(.bottom, 14)

                    // ── PER-PARTICIPANT ──────────────────────────────────
                    GSSectionHeader("Results")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    ForEach(Array(stats.enumerated()), id: \.element.profile.id) { index, stat in
                        participantRow(rank: index + 1, stat: stat)

                        if index < stats.count - 1 {
                            Rectangle()
                                .fill(theme.divider)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }

                    GSDivider()
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    // ── DONE ─────────────────────────────────────────────
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
            .background(theme.bg)
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Hero banner
    // Canvas: accent fill, session name kicker, large duration, date + lifter count,
    //         aggregate stat pills (total lbs, sets)

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SESSION RECAP")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            Text(durationString)
                .font(.custom("Archivo-Bold", size: 52).monospacedDigit())
                .foregroundStyle(theme.bg)
                .lineLimit(1)

            Text("\(dateString) · \(participants.count) lifter\(participants.count == 1 ? "" : "s")")
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.bg.opacity(0.9))

            // Aggregate stats row
            HStack(spacing: 0) {
                statPill(value: formatVolume(totalVolume), label: "TOTAL LBS")
                Rectangle()
                    .fill(theme.bg.opacity(0.3))
                    .frame(width: 1, height: 32)
                statPill(value: "\(totalSets)", label: "SETS")
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(GSFont.heading(20, relativeTo: .title2))
                .foregroundStyle(theme.bg)
            Text(label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.bg.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Participant row

    private func participantRow(rank: Int, stat: ParticipantStats) -> some View {
        HStack(spacing: 10) {
            // Rank
            Text("\(rank)")
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(rank == 1 ? theme.accent : theme.neutral700)
                .frame(width: 18, alignment: .leading)

            // Avatar
            let initials = String(stat.profile.username.prefix(2)).uppercased()
            ZStack {
                Rectangle()
                    .fill(rank == 1 ? theme.accent : theme.neutral400)
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.profile.username)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)

                HStack(spacing: 6) {
                    Text("\(stat.setCount) sets")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    if stat.volume > 0 {
                        Text("·")
                            .foregroundStyle(theme.neutral500)
                            .font(GSFont.body(11, relativeTo: .caption))
                        Text("\(formatVolume(stat.volume)) lbs")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    if stat.penaltyReps > 0 {
                        Text("·")
                            .foregroundStyle(theme.neutral500)
                            .font(GSFont.body(11, relativeTo: .caption))
                        Text("\(stat.penaltyReps) penalty reps")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.accent700)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func formatVolume(_ v: Double) -> String {
        if v >= 1_000 {
            return String(format: "%.1fk", v / 1_000)
        }
        return String(format: "%.0f", v)
    }
}

