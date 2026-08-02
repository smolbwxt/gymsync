import SwiftUI

// MARK: - GSPlateToken
//
// The strap bumper (composite v5): a barbell plate, face-on, that says
// what it plays. Class-colored ring (the design system's one sanctioned
// color exception, via GSBarLoader.plateColor), a strap band carrying the
// sound's name, its real waveform underneath, the duration on the bottom
// arc, and a draining rim while it re-racks after a throw.
struct GSPlateToken: View {
    @Environment(\.gsTheme) private var theme

    let name: String
    /// 22 envelope buckets (1…8); nil draws a flat placeholder (legacy
    /// sounds imported before the envelope pipeline).
    let envelope: [Int]?
    let durationMs: Int?
    /// Kept for call-site stability; clip status no longer renders (the
    /// scissors glyph was retired in the 2026-08 visual-language pass).
    let isClipped: Bool
    /// Non-nil while re-racking — the parent clears the entry when the
    /// cooldown lapses, which also restores full opacity.
    let cooldownUntil: Date?
    var size: CGFloat = 56
    /// Compact face: class ring + strap + name only — no waveform, no
    /// duration. For shop tiles and small previews. Trailing-defaulted so
    /// every existing call site compiles unchanged.
    var compact: Bool = false

    private var plateClass: PlateClass { PlateClass.forDuration(ms: durationMs) }

    private var ringColor: Color {
        GSBarLoader.plateColor(plateClass.denomination, unit: .lbs)
    }

    private var durationText: String {
        guard let durationMs else { return "" }
        let s = (Double(durationMs) / 100).rounded() / 10
        return s == s.rounded() ? "\(Int(s))s" : "\(s)s"
    }

    /// 11 bars — every other envelope bucket, matching the mockups.
    private var waveformBars: [Int] {
        guard let envelope, !envelope.isEmpty else {
            return Array(repeating: 4, count: 11)
        }
        return stride(from: 0, to: envelope.count, by: 2).map { envelope[$0] }
    }

    var body: some View {
        ZStack {
            Circle().fill(theme.surface)
            Circle().strokeBorder(ringColor, lineWidth: size * 0.09)
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.bg.opacity(0.8))
                .frame(width: size * 0.78, height: size * 0.26)
                .offset(y: -size * 0.10)
            Text(name)
                .font(GSFont.boldFixed(size * 0.125))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: size * 0.72)
                .offset(y: -size * 0.10)
            if !compact {
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(waveformBars.enumerated()), id: \.offset) { pair in
                        Capsule().fill(theme.neutral700)
                            .frame(width: 2, height: max(2, CGFloat(pair.element) / 8 * size * 0.16))
                    }
                }
                .frame(height: size * 0.16, alignment: .bottom)
                .offset(y: size * 0.12)
                Text(durationText)
                    .font(GSFont.boldFixed(size * 0.11))
                    .foregroundStyle(theme.neutral700)
                    .offset(y: size * 0.31)
            }
            cooldownRim
        }
        .frame(width: size, height: size)
        .opacity(cooldownUntil != nil ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(compact ? "\(name) sound" : "\(name), \(durationText) sound")
    }

    /// The rim refills clockwise as the plate re-racks (composite v5) —
    /// a dark arc eats the class ring and shrinks as time passes.
    @ViewBuilder
    private var cooldownRim: some View {
        if let cooldownUntil {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let remaining = max(0, cooldownUntil.timeIntervalSince(ctx.date))
                let frac = min(1, remaining / plateClass.cooldown)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(theme.bg.opacity(0.75),
                            style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.045)
            }
        }
    }
}
