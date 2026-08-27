import SwiftUI

// MARK: - AnchorEntryView
//
// The five-rep probe as CONTROLS, not a sentence. Owner 2026-08-27: "a
// drop-down menu of curated lifts... a weight incrementer, like the one
// on the live session page, and a plus button."
//
// The old free-text field ("bench 135, squat 185") had to be parsed, and
// the parse dropped anything it could not read without saying so. A row
// is a lift picked from the same four slugs LiftAnchorMath seeds from,
// and a weight stepped in the athlete's own unit at the same increment
// the live session uses — so what is recorded is exactly what was shown.
//
// Pounds are the storage unit throughout the app (UserSettings.liftAnchors
// is in pounds); the display converts on the way out and the steps
// convert on the way in.
struct AnchorEntry: Identifiable, Equatable {
    let id = UUID()
    var slug: String
    var pounds: Decimal
}

struct AnchorEntryView: View {
    @Binding var entries: [AnchorEntry]

    @Environment(\.gsTheme) private var theme

    /// The curated lifts — the anchor slugs the rest of the app reads.
    static let lifts: [(slug: String, name: String, seedPounds: Decimal)] = [
        ("bench-press", "Bench press", 95),
        ("back-squat",  "Back squat",  135),
        ("deadlift",    "Deadlift",    135),
        ("ohp",         "Overhead press", 65),
    ]

    private var unit: WeightUnit { ThemeStore.shared.weightUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($entries) { $entry in
                row($entry)
            }
            if entries.count < Self.lifts.count {
                Button { add() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(entries.isEmpty ? "ADD A LIFT" : "ADD ANOTHER LIFT")
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .tracking(0.8)
                    }
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: 15))
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ entry: Binding<AnchorEntry>) -> some View {
        HStack(spacing: 10) {
            // The lift: a menu over the curated four, never a text field.
            Menu {
                ForEach(Self.lifts, id: \.slug) { lift in
                    Button(lift.name) { entry.wrappedValue.slug = lift.slug }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(name(for: entry.wrappedValue.slug).uppercased())
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .tracking(0.4)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            Spacer(minLength: 4)
            // The incrementer — the live session's shape: minus, number, plus.
            stepButton("minus") { step(entry, by: -1) }
            Text(Units.format(pounds: entry.wrappedValue.pounds, unit: unit,
                              rounded: true, includeUnit: true))
                .font(GSFont.bold(15, relativeTo: .headline).monospacedDigit())
                .foregroundStyle(theme.text)
                .frame(minWidth: 74)
            stepButton("plus") { step(entry, by: 1) }
            Button {
                entries.removeAll { $0.id == entry.wrappedValue.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.neutral500)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(name(for: entry.wrappedValue.slug))")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 15)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(GS3DButtonStyle(face: theme.raised3DFace,
                                     lip: theme.raised3DLip,
                                     cornerRadius: 10, lipHeight: 3))
    }

    // MARK: Wire

    private func add() {
        let taken = Set(entries.map(\.slug))
        guard let next = Self.lifts.first(where: { !taken.contains($0.slug) }) else { return }
        entries.append(AnchorEntry(slug: next.slug, pounds: next.seedPounds))
    }

    /// One display-unit increment, converted to pounds, rounded so the
    /// stored anchor is a weight the athlete can actually load.
    private func step(_ entry: Binding<AnchorEntry>, by direction: Int) {
        let stepPounds = Units.toPounds(unit.displayIncrement, from: unit)
        let raw = entry.wrappedValue.pounds + stepPounds * Decimal(direction)
        let rounded = Units.roundToIncrement(raw, unit: unit)
        entry.wrappedValue.pounds = max(stepPounds, rounded)
    }

    private func name(for slug: String) -> String {
        Self.lifts.first(where: { $0.slug == slug })?.name ?? slug
    }
}
