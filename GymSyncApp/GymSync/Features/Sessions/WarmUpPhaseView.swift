import SwiftUI

// MARK: - Warm-up phase & transit windows (2026-08 user-approved feature)
//
// A WARM-UP window precedes lifting: the organizer sets `warmup_minutes` in
// the lobby (0 = no warm-up, exactly the pre-feature flow); once the session
// starts, every PRESENT participant votes "I'm warm" (mark_warmup_ready) —
// the last vote begins lifting for everyone, and the organizer can
// force-start (start_lifting). Effective lifting start: `lifting_started_at`
// if set, else `started_at + warmup_minutes` (the clock alone can end it).
//
// This file is the feature's shared home: the phase page itself
// (`WarmUpPhaseView`, rendered by BOTH GroupSessionLiveView and the solo
// WorkoutSessionView), the solo duration setting (`SoloWarmupStore`), and
// the TRANSIT constant the rest windows read (`TransitWindow`).

/// TRANSIT windows: when the NEXT set is a DIFFERENT exercise from the one
/// just completed, the rest window is extended by this many seconds and the
/// whole window is labelled "TRANSIT · SET UP YOUR STATION" — time to strip
/// the bar, walk to the next station, and set up. Same-exercise turns are
/// unchanged. ONE constant, read by both rest computations
/// (GroupSessionLiveView's self-rotation interlude and WorkoutSessionView's
/// solo rest window) — never a scattered literal.
enum TransitWindow {
    static let seconds = 120
}

/// UserDefaults-backed solo warm-up duration — `HeartRatePrimeStore`'s
/// key-owned-here shape. DEFAULT 0 (`integer(forKey:)` on an absent key):
/// solo behavior is unchanged until the lifter opts in, and the − / +
/// control on the warm-up page itself is the only writer.
enum SoloWarmupStore {
    static let defaultsKey = "solo.warmupMinutes.v1"

    static var minutes: Int {
        // Owner field report 2026-08-21 ("no warm up timer on solo"):
        // never-configured now defaults to 5 minutes — the phase appears
        // and its −/+ or SKIP teaches the control. An explicit 0 still
        // means "off"; only the unset state changed.
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else { return 5 }
        return UserDefaults.standard.integer(forKey: defaultsKey)
    }

    static func set(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: defaultsKey)
    }

    /// Whether the athlete has ever touched the duration control - the
    /// mobility bump (owner 2026-08-22) only applies to the UNSET state;
    /// an explicit choice is always respected.
    static var isConfigured: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) != nil
    }
}

// MARK: - WarmupMobility
//
// Owner 2026-08-22: the warm-up window doubles as the mobility slot -
// "display a mobility circuit for them to do during the warm-up." Pure
// selection: the day's muscles pick the region, the window divides
// across the moves. Names are coach-speak, not catalog rows - this is
// guided time, not logged sets.
enum WarmupMobility {
    struct Move: Identifiable, Equatable {
        let name: String
        let detail: String
        var id: String { name }
    }

    static let lowerMoves = [
        Move(name: "90/90 hip switches", detail: "slow, both directions"),
        Move(name: "Deep squat hold", detail: "heels down, chest tall"),
        Move(name: "Couch stretch", detail: "each side — hip flexors"),
        Move(name: "Leg swings", detail: "front-back, then side-side"),
    ]
    static let upperMoves = [
        Move(name: "Arm circles", detail: "small to big, both ways"),
        Move(name: "Doorway pec stretch", detail: "each arm, easy lean"),
        Move(name: "Wall slides", detail: "ribs down, slow reps"),
        Move(name: "Thoracic rotations", detail: "on all fours, each side"),
    ]

    /// The circuit for a session whose work hits `muscles` (lowercased
    /// primary muscles of the day's exercises). Mixed days interleave.
    static func circuit(for muscles: [String]) -> [Move] {
        let lowerSet: Set<String> = ["quads", "hamstrings", "glutes", "calves",
                                     "adductors", "lower_back"]
        let hitsLower = muscles.contains { lowerSet.contains($0) }
        let upperSet: Set<String> = ["chest", "shoulders", "back", "lats",
                                     "triceps", "biceps", "traps", "forearms"]
        let hitsUpper = muscles.contains { upperSet.contains($0) }
        switch (hitsLower, hitsUpper) {
        case (true, false): return lowerMoves
        case (false, true): return upperMoves
        default:
            return [lowerMoves[0], upperMoves[0], lowerMoves[1], upperMoves[2]]
        }
    }
}

/// The warm-up phase page. Plain values + closures only — no session
/// repositories inside (GroupSessionLiveView is at its type-checker limit;
/// this view must stay independently checkable and reusable by the solo
/// screen). The caller supplies the countdown target (`started_at +
/// warmup_minutes`), the PRESENT participants (the same subset the server
/// counts toward unanimity — online/ready/late; no_shows and leavers are
/// never shown because they can never block the vote), and the callbacks.
struct WarmUpPhaseView: View {

    /// One present participant's warm-up status. `id` = user id.
    struct Member: Identifiable, Equatable {
        let id: UUID
        let name: String
        let avatarURL: URL?
        let isReady: Bool
    }

    enum Mode: Equatable {
        /// Group vote semantics: "I'M WARM — LET'S RIDE" → inert waiting
        /// card after my vote; organizer gets the quiet force-start row.
        case group
        /// Solo: no vote — the CTA is "SKIP WARM-UP" and a − / + control
        /// adjusts (and persists) the duration. Carries the current minutes
        /// for display.
        case solo(minutes: Int)
    }

    let mode: Mode
    /// The countdown target — effective lifting start if nothing votes it
    /// open earlier.
    let countdownEndsAt: Date
    /// PRESENT participants only (display subset == voter subset).
    let members: [Member]
    let isOrganizer: Bool
    /// My own recorded vote — flips the CTA to the inert waiting card.
    let myReady: Bool
    /// Group: "I'm warm" vote. Solo: skip warm-up.
    let onReady: () -> Void
    /// Organizer force-start (group only; nil hides the row).
    var onForceStart: (() -> Void)? = nil
    /// Solo only: ± minutes (the caller clamps and persists).
    var onAdjustMinutes: ((Int) -> Void)? = nil
    /// The mobility circuit to run during the window (owner 2026-08-22);
    /// empty renders nothing - group callers pass none today.
    var mobilityCircuit: [WarmupMobility.Move] = []

    @Environment(\.gsTheme) private var theme

    private var isSolo: Bool {
        if case .solo = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            countdownBlock
            if case .solo(let minutes) = mode, onAdjustMinutes != nil {
                Color.clear.frame(height: 20)
                soloAdjustRow(minutes: minutes)
            }
            Spacer(minLength: 16)
            mobilityBlock
            if !mobilityCircuit.isEmpty { Spacer(minLength: 16) }
            if !members.isEmpty {
                memberRow
                Spacer(minLength: 16)
            }
            primaryCTA
            if !isSolo, isOrganizer, onForceStart != nil {
                Color.clear.frame(height: 10)
                forceStartRow
            }
            Color.clear.frame(height: 8)
        }
        .padding(.horizontal, 16)
        .background(theme.bg)
    }

    // MARK: - Countdown

    /// K-label + big fixed-size numeral. TimelineView drives the once-a-
    /// second re-render (the periodic idiom — HomeView's session candidate
    /// row); `boldFixed` because the numeral lives in this page's fixed
    /// vertical rhythm (GSFont's own "design constant" rule), with the
    /// meaning carried redundantly by the scaling WARM-UP label and the
    /// accessibility value.
    private var countdownBlock: some View {
        VStack(spacing: 10) {
            Text("WARM-UP")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(theme.neutral700)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.remainingText(until: countdownEndsAt, now: context.date))
                    .font(GSFont.boldFixed(56).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityLabel("Warm-up time remaining")
        }
        .frame(maxWidth: .infinity)
    }

    /// The guided mobility circuit under the countdown — what the window
    /// is FOR, not a second to-do list. Divide the moves across the
    /// clock; no logging, no checkboxes.
    @ViewBuilder
    private var mobilityBlock: some View {
        if !mobilityCircuit.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("WHILE YOU WARM UP")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.3)
                    .foregroundStyle(theme.neutral700)
                    .padding(.bottom, 8)
                ForEach(mobilityCircuit) { move in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 5, height: 5)
                        Text(move.name)
                            .font(GSFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text(move.detail)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 7)
                }
                Text("Easy effort — this is grease, not work. Skip anything that pinches.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        }
    }

    /// "12:34" — clamped at 0:00 once the window lapses (the parent's own
    /// wake-up flips the page; this never renders a negative).
    static func remainingText(until end: Date, now: Date) -> String {
        let remaining = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    // MARK: - Solo duration control

    private func soloAdjustRow(minutes: Int) -> some View {
        HStack(spacing: 14) {
            adjustButton(systemName: "minus", delta: -5)
            Text(minutes == 0 ? "OFF" : "\(minutes) MIN")
                .font(GSFont.bold(13, relativeTo: .footnote).monospacedDigit())
                .tracking(0.8)
                .foregroundStyle(theme.text.opacity(0.78))
                .frame(minWidth: 64)
            adjustButton(systemName: "plus", delta: 5)
        }
        .frame(maxWidth: .infinity)
    }

    private func adjustButton(systemName: String, delta: Int) -> some View {
        Button { onAdjustMinutes?(delta) } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.neutral700)
                .frame(width: 36, height: 36)
                .background(theme.surface)
                .overlay(Circle().strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Longer warm-up" : "Shorter warm-up")
    }

    // MARK: - Crew readiness

    /// Present participants with ready pips — small accent checkmark ring
    /// once their vote is in, neutral otherwise. Solo shows the lone avatar
    /// without a pip (there is no vote to report).
    private var memberRow: some View {
        HStack(spacing: 0) {
            ForEach(members) { member in
                VStack(spacing: 6) {
                    GSInitialsAvatar(name: member.name, avatarURL: member.avatarURL, size: 40)
                        .overlay(alignment: .bottomTrailing) {
                            if !isSolo { readyPip(isReady: member.isReady) }
                        }
                    Text(member.name)
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(member.isReady || isSolo ? theme.text.opacity(0.78) : theme.neutral700)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func readyPip(isReady: Bool) -> some View {
        Circle()
            .strokeBorder(isReady ? theme.accent : theme.neutral500, lineWidth: 1.5)
            .background(Circle().fill(theme.bg))
            .frame(width: 16, height: 16)
            .overlay {
                if isReady {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .offset(x: 4, y: 4)
            .accessibilityLabel(isReady ? "Warmed up" : "Still warming up")
    }

    // MARK: - CTAs

    /// The primary action — the START SET CTA idiom (full-width, 64pt
    /// total, radius 16), now wearing the extruded 3D style: 57pt face +
    /// 7pt lip. The group vote rides the accent face; the solo skip is a
    /// QUIET raised face (skipping is permission, not a push). After my
    /// group vote it becomes an INERT surface card: the decision is made,
    /// the crew is what's pending.
    @ViewBuilder
    private var primaryCTA: some View {
        if isSolo {
            surfaceCTAButton(title: "SKIP WARM-UP", action: onReady)
        } else if myReady {
            Text("WARMED UP · WAITING ON THE CREW")
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(0.9)
                .foregroundStyle(theme.neutral700)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            ctaButton(title: "I'M WARM — LET'S RIDE", action: onReady)
        }
    }

    private func ctaButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GSFont.bold(17, relativeTo: .body))
                .tracking(0.9)
                .foregroundStyle(theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 57)   // + 7pt lip = the 64pt CTA rhythm
        }
        .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 16))
    }

    /// Raised-faced 3D variant (solo skip) — same 64pt footprint, quiet
    /// hue on the theme's raised pair (theme.surface could not read as 3D
    /// against the page ground — owner field report).
    private func surfaceCTAButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GSFont.bold(17, relativeTo: .body))
                .tracking(0.9)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 57)   // + 7pt lip = the 64pt CTA rhythm
        }
        .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 16))
    }

    /// The organizer's AFK escape hatch — deliberately QUIET (raised
    /// face, never accent): the unanimous vote is the intended path.
    /// Label bumped neutral700 → text.opacity(0.78): the lighter raised
    /// face needs the stronger ink to stay legible at 12pt.
    private var forceStartRow: some View {
        Button { onForceStart?() } label: {
            Text("START LIFTING NOW")
                .font(GSFont.bold(12, relativeTo: .caption))
                .tracking(0.9)
                .foregroundStyle(theme.text.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 37)   // + 7pt lip = the row's 44pt footprint
        }
        .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 12))
    }
}
