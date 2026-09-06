import SwiftUI

/// Lifetime volume against a landmark, as a TILE (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// Kicker `LIFETIME`, the total at 22 pt, the share of the landmark under
/// it, and a three-segment bar filled to that share. Design language rule 8
/// keeps the full milestone treatment (the height ladder, the mass vessel,
/// the Blender renders in `tools/milestone-render/`) for the You hero and
/// says one milestone at a time, blended in — so Home gets the SMALLEST
/// possible form of it: a number, a percentage, and a bar. No render is
/// loaded and the app draws no plates.
///
/// The bar is in the 45 lb plate's competition blue (`#2F6FD0`, the same
/// value `GSBarLoader`'s plate ramp uses for a 45). Rule 2 makes plate
/// colours DATA colour, exempt from the accent/gold/green rules — which is
/// exactly why a progress bar can be coloured at all here without competing
/// with the one button.
///
/// Three segments rather than one continuous track: a single bar at 29 %
/// reads as "nearly nothing", three read as "the first of three, most of the
/// way". Same v2 tile styling as `HomeLastLiftTile`.
struct HomeMilestoneTile: View {
    @Environment(\.gsTheme) private var theme

    /// Lifetime volume, already formatted, e.g. `1.31M lb`.
    let total: String
    /// The landmark line, e.g. `29% of Mount Fuji`.
    let line: String
    /// Share of the landmark, 0...1 — the bar's fill.
    let progress: Double
    /// Tap → the You hero's milestone.
    var action: () -> Void = {}

    /// The 45 lb plate's competition blue (design language rule 2's plate
    /// table; `GSBarLoader.swift:197` carries the same value for the same
    /// plate). Declared here rather than reached for across the design
    /// system because that one is `private` to the loader's ramp.
    private static let plateBlue = Color.gsHex(0x2F6FD0)
    private static let segments = 3

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("LIFETIME")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(1.6)
                    .foregroundStyle(theme.neutral500)

                Text(total)
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)

                Text(line)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                bar.padding(.top, 10)
            }
            .frame(maxWidth: .infinity, minHeight: HomeV3Metrics.tileMinHeight,
                   maxHeight: .infinity, alignment: .topLeading)
            .padding(HomeV3Metrics.tilePadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lifetime \(total). \(line).")
    }

    /// Three equal segments, each filled left-to-right by its own share of
    /// the whole: at 29 % the first is 87 % full and the other two are empty.
    private var bar: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.segments, id: \.self) { index in
                segment(fill: fillOfSegment(index))
            }
        }
        .frame(height: 6)
    }

    /// How much of segment `index` is filled, 0...1.
    private func fillOfSegment(_ index: Int) -> Double {
        let each = 1.0 / Double(Self.segments)
        let clamped = min(max(progress, 0), 1)
        return min(max((clamped - each * Double(index)) / each, 0), 1)
    }

    /// `GeometryReader` rather than a fixed width: the tile's width is the
    /// column's, which is the page's, which is the device's — nothing in a
    /// catalog fixture may assume one.
    private func segment(fill: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.neutral300)
                if fill > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.plateBlue)
                        .frame(width: proxy.size.width * fill)
                }
            }
        }
    }
}
