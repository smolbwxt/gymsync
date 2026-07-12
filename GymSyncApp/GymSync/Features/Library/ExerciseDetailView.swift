import SwiftUI

// Canvas: Bench Press detail — hero name at top, surface demo placeholder,
// "Muscles worked" section (accent tag for primary, neutral tags for secondary),
// equipment + "your best" stat cards side by side, Add to Routine CTA at bottom.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(\.gsTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Canvas: demo placeholder block (no photos yet — grayscale rule N/A)
                ZStack {
                    theme.surface
                    VStack(spacing: 6) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(theme.neutral500)
                        Text("WATCH DEMO")
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral500)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                // Canvas: Muscles worked section header + accent/neutral tags
                VStack(alignment: .leading, spacing: 8) {
                    Text("MUSCLES WORKED")
                        .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)

                    FlowLayout(spacing: 6) {
                        GSTag(text: "\(exercise.primaryMuscle.capitalized) · primary",
                              style: .accent)
                        ForEach(exercise.secondaryMuscles, id: \.self) { m in
                            GSTag(text: m.localizedCapitalized, style: .neutral)
                        }
                    }
                }

                // Canvas: Equipment + "Your best" side-by-side stat tiles
                HStack(spacing: 8) {
                    statTile(kicker: "Equipment", value: exercise.equipment.capitalized)
                    statTile(kicker: "Category", value: exercise.category.capitalized)
                }

                if let url = exercise.demoVideoURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Text("Watch Demo")
                    }
                    .buttonStyle(GSGhostButtonStyle())
                }

                Spacer(minLength: 32)
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Canvas: sticky "Add to Routine" CTA at bottom — deferred (no route in current app)
    }

    // Canvas: small bordered stat tile — kicker + bold value
    private func statTile(kicker: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker.uppercased())
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral700)
            Text(value)
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }
}

// MARK: - FlowLayout helper (wrapping HStack)
// Zero-dep row-wrap for tag clouds (used only in ExerciseDetailView).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
