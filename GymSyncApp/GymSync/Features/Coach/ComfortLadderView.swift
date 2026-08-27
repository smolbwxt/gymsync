import SwiftUI

// MARK: - ComfortLadderView
//
// The complexity probe as a LADDER, not a checklist. Owner 2026-08-27:
// "the complexity question hides any exercise the joint answer just
// invalidated... re-populate their slots with exercises that their joints
// allow them to do in the same complexity bucket... have the selections
// disappear after saying yeah I can do that and then re-populate with
// more in order to fine tune until we're confident on a float."
//
// How it climbs: three exercises from the current level are on screen.
// Tapping one means "I can do that" — it disappears and the next
// candidate at the SAME level takes its slot. Once the level's quota is
// confirmed the ladder steps up a rung and shows harder lifts. "THAT'S
// MY LIMIT" stops the climb; at the starting rung with nothing confirmed
// it steps DOWN once instead, so a true beginner gets asked about the
// simplest movements rather than being scored on ones they never saw.
//
// The pool is the catalog with the athlete's constraints already applied:
// no alias rows, nothing that loads a joint they just named, nothing on
// equipment they said they lack. A probe that offers a lift the previous
// answer ruled out is asking a question whose answer cannot be used.
//
// What it reports (the values ConsultAnswers reads):
//   cap=N     the highest rung FULLY confirmed — the integer cap the
//             generator already understands (derivedComplexityCap)
//   float=X   cap + the fraction confirmed on the rung above, recorded
//             for the day the generator learns to tilt within a level
//   <uuid>…   every exercise they said yes to, for the record
struct ComfortLadderView: View {
    let catalog: [Exercise]
    let avoidJoints: Set<String>
    let equipment: Set<String>?
    let onFinish: ([String]) -> Void

    @Environment(\.gsTheme) private var theme

    @State private var level = Self.startRung
    @State private var shown: [Exercise] = []
    @State private var confirmed: [Int: Int] = [:]
    @State private var confirmedIDs: [UUID] = []
    @State private var used: Set<UUID> = []
    @State private var steppedDown = false
    @State private var started = false

    private static let startRung = 2
    private static let topRung = 5
    private static let quota = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rungLine
            ForEach(shown) { exercise in
                chip(exercise)
            }
            if shown.isEmpty && started {
                Text("That's every lift in the library at this level.")
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral700)
            }
            Button { stop() } label: {
                Text(stopLabel)
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.8)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.raised3DFace,
                                         lip: theme.raised3DLip,
                                         cornerRadius: 14))
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .onAppear(perform: start)
    }

    // MARK: Pieces

    private var rungLine: some View {
        HStack {
            Text("LEVEL \(level) OF \(Self.topRung)")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Spacer()
            Text("\(confirmed[level] ?? 0) OF \(capacity(level)) CONFIRMED")
                .font(GSFont.bold(10, relativeTo: .caption2).monospacedDigit())
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 2)
    }

    private func chip(_ exercise: Exercise) -> some View {
        Button { accept(exercise) } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name.uppercased())
                        .font(GSFont.bold(15, relativeTo: .headline))
                        .tracking(0.3)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.leading)
                    Text("\(ConsultVocabulary.display(exercise.primaryMuscle)) · \(ConsultVocabulary.display(exercise.equipment))")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                Spacer(minLength: 0)
                Text("I CAN DO THAT")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: 15))
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var stopLabel: String {
        if (confirmed[level] ?? 0) == 0 {
            return level == Self.startRung && !steppedDown ? "NONE OF THESE" : "THAT'S MY LIMIT"
        }
        return "THAT'S MY LIMIT"
    }

    // MARK: The pool

    /// Catalog rows this athlete can be asked about at all.
    private var pool: [Exercise] {
        catalog.filter { ex in
            guard ex.aliasOf == nil, ex.complexity != nil else { return false }
            if !avoidJoints.isEmpty,
               !Set(ex.jointStress ?? []).isDisjoint(with: avoidJoints) { return false }
            if let equipment, !equipment.isEmpty,
               !equipment.contains(ex.equipment),
               !["bodyweight", "none", ""].contains(ex.equipment.lowercased()) { return false }
            return true
        }
    }

    private func candidates(at rung: Int) -> [Exercise] {
        pool.filter { $0.complexity == rung }
    }

    /// How many confirmations a rung needs: the quota, or every lift the
    /// library has at that rung when there are fewer.
    private func capacity(_ rung: Int) -> Int {
        min(Self.quota, candidates(at: rung).count)
    }

    // MARK: Climb

    private func start() {
        guard !started else { return }
        started = true
        refill()
    }

    private func refill() {
        var next = shown
        for candidate in candidates(at: level) where next.count < Self.quota {
            if !used.contains(candidate.id) && !next.contains(where: { $0.id == candidate.id }) {
                next.append(candidate)
            }
        }
        withAnimation(.easeOut(duration: 0.18)) { shown = next }
        // A rung the library cannot populate at all is skipped upward —
        // nothing to ask means nothing to confirm.
        if shown.isEmpty, level < Self.topRung, candidates(at: level).isEmpty {
            level += 1
            refill()
        }
    }

    private func accept(_ exercise: Exercise) {
        used.insert(exercise.id)
        confirmedIDs.append(exercise.id)
        confirmed[level, default: 0] += 1
        withAnimation(.easeOut(duration: 0.18)) {
            shown.removeAll { $0.id == exercise.id }
        }
        if (confirmed[level] ?? 0) >= capacity(level) {
            if level < Self.topRung {
                level += 1
                shown = []
                refill()
            } else {
                finish()
            }
        } else {
            refill()
        }
    }

    private func stop() {
        // Nothing confirmed at the starting rung: step down once so the
        // simplest movements get asked before the cap is decided.
        if level == Self.startRung, (confirmed[level] ?? 0) == 0, !steppedDown {
            steppedDown = true
            level = 1
            shown = []
            refill()
            if !shown.isEmpty { return }
        }
        finish()
    }

    private func finish() {
        // The cap is the highest rung FULLY confirmed. Level 1 is implied
        // by starting at 2 unless the athlete stepped down and confirmed
        // nothing there either.
        var cap = steppedDown ? 0 : 1
        for rung in 1...Self.topRung where capacity(rung) > 0 {
            if (confirmed[rung] ?? 0) >= capacity(rung) { cap = rung }
        }
        cap = max(1, cap)
        var fraction = 0.0
        let above = cap + 1
        if above <= Self.topRung, capacity(above) > 0 {
            fraction = Double(confirmed[above] ?? 0) / Double(capacity(above))
        }
        let float = Double(cap) + fraction
        var values = ["cap=\(cap)", String(format: "float=%.2f", float)]
        values.append(contentsOf: confirmedIDs.map(\.uuidString))
        onFinish(values)
    }
}
