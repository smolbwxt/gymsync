import SwiftUI

// MARK: - GSPlateToken
//
// The soundboard token, v6 (owner 2026-08-14: "the plate idea was cheeky,
// but it doesn't fit anymore — rounded edges, extruded buttons, short
// text, colors within the same palette as the accent"). The face-on
// barbell plate becomes a compact EXTRUDED TILE in the app-wide gs3D
// language: rounded face + lip via the shared `gs3DCard` modifier (the
// same anatomy every widget wears, so the soundboard can never drift),
// with the duration class expressed as an ACCENT-STRENGTH wash — quick
// sounds wear a light tint, the heavy 45s run deep. One palette, four
// weights, whichever accent the user chose in Appearance.
//
// The name stays the public API of the sound; waveform + duration render
// only in the full (non-compact) form. Total footprint is still
// size × size — the face gives up `lipHeight` so face + lip lands on the
// exact frame every call site already lays out.
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
    /// Compact face: wash + name only — no waveform, no duration. For
    /// shop tiles and small previews.
    var compact: Bool = false

    private var plateClass: PlateClass { PlateClass.forDuration(ms: durationMs) }

    /// The class's accent weight — heavier class, deeper wash. The class
    /// system's meaning (longer sound = heavier plate = slower re-rack)
    /// survives the palette change intact.
    private var classWashOpacity: Double {
        switch plateClass {
        case .five: 0.14
        case .ten: 0.26
        case .twentyFive: 0.40
        case .fortyFive: 0.55
        }
    }

    private var lipHeight: CGFloat { max(3, size * 0.08) }
    private var cornerRadius: CGFloat { size * 0.22 }
    private var faceHeight: CGFloat { size - lipHeight }

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
        ZStack(alignment: .top) {
            // Class wash — the accent at this class's strength, flooding
            // the face (gs3DCard clips it to the rounded shape).
            theme.accent.opacity(classWashOpacity)

            // Short text, centered.
            VStack(spacing: size * 0.06) {
                Text(name.uppercased())
                    .font(GSFont.boldFixed(size * 0.15))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, size * 0.08)
                if !compact {
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(Array(waveformBars.enumerated()), id: \.offset) { pair in
                            Capsule().fill(theme.text.opacity(0.55))
                                .frame(width: 2, height: max(2, CGFloat(pair.element) / 8 * size * 0.16))
                        }
                    }
                    .frame(height: size * 0.16, alignment: .bottom)
                    Text(durationText)
                        .font(GSFont.boldFixed(size * 0.11))
                        .foregroundStyle(theme.text.opacity(0.6))
                }
            }
            .frame(width: size, height: faceHeight)

            cooldownVeil
        }
        .frame(width: size, height: faceHeight)
        .gs3DCard(cornerRadius: cornerRadius, lipHeight: lipHeight)
        .opacity(cooldownUntil != nil ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(compact ? "\(name) sound" : "\(name), \(durationText) sound")
    }

    /// The re-rack veil (v6 form of the draining rim): a dark sheet over
    /// the face that shrinks upward as the cooldown expires — the tile
    /// visibly "recharges" from the bottom.
    @ViewBuilder
    private var cooldownVeil: some View {
        if let cooldownUntil {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let remaining = max(0, cooldownUntil.timeIntervalSince(ctx.date))
                let frac = min(1, remaining / plateClass.cooldown)
                theme.bg.opacity(0.65)
                    .frame(width: size, height: faceHeight * frac)
            }
        }
    }
}
