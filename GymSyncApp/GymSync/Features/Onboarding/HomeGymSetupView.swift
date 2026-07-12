import SwiftUI

/// Onboarding step 3: "Set your home gym".
/// Canvas: architectural-grid map placeholder, gym card with name/address/radius,
/// sticky bottom bar with Ghost "Skip" + Primary "Set Home Gym".
/// This is VIEW-ONLY — no geolocation or gym-search logic is wired in this pass.
/// Navigation is driven by the onSkip / onComplete callbacks from OnboardingCoordinator.
struct HomeGymSetupView: View {
    var onSkip: () -> Void
    var onComplete: () -> Void

    @Environment(\.gsTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Step indicator row
                    HStack(spacing: 10) {
                        Text("STEP 3 OF 3")
                            .font(GSFont.bold(12, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundColor(theme.neutral700)

                        Spacer()

                        HStack(spacing: 4) {
                            Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                            Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                            Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                    .padding(.bottom, 10)

                    // Heading + sub
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set your home gym")
                            .font(GSFont.bold(28, relativeTo: .title))
                            .foregroundColor(theme.text)

                        Text("We use it to confirm you're in the room at check-in. You can skip this.")
                            .font(GSFont.body(14, relativeTo: .subheadline))
                            .foregroundColor(theme.neutral700)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    // Map placeholder: architectural grid + accent pin + radius circle
                    MapPlaceholderView()
                        .frame(height: 230)
                        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    // Gym card
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Iron Temple — Downtown")
                                .font(GSFont.bold(15, relativeTo: .subheadline))
                                .foregroundColor(theme.text)

                            Text("412 Foundry St · check-in radius 200m")
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundColor(theme.neutral700)
                        }

                        Spacer()

                        Button("Edit") {}
                            .font(GSFont.bodyMedium(12, relativeTo: .caption))
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .buttonStyle(.plain)
                            .background(theme.surface)
                            .overlay(Rectangle().strokeBorder(theme.neutral300, lineWidth: 1))
                    }
                    .padding(14)
                    .background(theme.surface)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    Spacer().frame(height: 100)
                }
            }

            // Sticky bottom CTA
            VStack(spacing: 0) {
                GSDivider()
                HStack(spacing: 8) {
                    Button("Skip", action: onSkip)
                        .buttonStyle(GSGhostButtonStyle())
                        .frame(minWidth: 80)

                    Button("Set Home Gym", action: onComplete)
                        .buttonStyle(GSPrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.bottom, 22)
            }
            .background(theme.bg)
        }
    }
}

// MARK: - Map placeholder

/// Architectural-grid SVG-style map drawn in Canvas, matching the canvas design.
private struct MapPlaceholderView: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let dividerColor = UIColor(theme.divider)
            let accentColor = UIColor(theme.accent)
            let neutral400Color = UIColor(theme.neutral400)

            // Background
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(theme.surface)
            )

            // Horizontal grid lines
            let hSteps: [CGFloat] = [46, 92, 138, 184]
            for y in hSteps {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(p, with: .color(Color(dividerColor)), lineWidth: 1)
            }

            // Vertical grid lines
            let vSteps: [CGFloat] = [64, 128, 192, 256]
            for x in vSteps {
                if x <= w {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                    ctx.stroke(p, with: .color(Color(dividerColor)), lineWidth: 1)
                }
            }

            // Diagonal road
            var road = Path()
            road.move(to: CGPoint(x: 0, y: h * 0.65))
            road.addLine(to: CGPoint(x: w, y: h * 0.30))
            ctx.stroke(road, with: .color(Color(neutral400Color)), lineWidth: 6)

            // Radius circle (accent tinted, centred)
            let centre = CGPoint(x: w / 2, y: h / 2)
            let radius: CGFloat = 60
            let circleRect = CGRect(x: centre.x - radius, y: centre.y - radius,
                                    width: radius * 2, height: radius * 2)
            ctx.fill(
                Path(ellipseIn: circleRect),
                with: .color(Color(accentColor).opacity(0.12))
            )
            ctx.stroke(
                Path(ellipseIn: circleRect),
                with: .color(Color(accentColor)),
                lineWidth: 2
            )

            // Pin (simple teardrop: circle + triangle point)
            let pinR: CGFloat = 9
            let pinTop = CGPoint(x: centre.x, y: centre.y - pinR - 8)
            let pinCircle = CGRect(x: pinTop.x - pinR, y: pinTop.y,
                                   width: pinR * 2, height: pinR * 2)
            ctx.fill(Path(ellipseIn: pinCircle), with: .color(Color(accentColor)))

            var spike = Path()
            spike.move(to: CGPoint(x: pinTop.x - pinR * 0.6, y: pinTop.y + pinR * 1.4))
            spike.addLine(to: CGPoint(x: centre.x, y: centre.y - 2))
            spike.addLine(to: CGPoint(x: pinTop.x + pinR * 0.6, y: pinTop.y + pinR * 1.4))
            spike.closeSubpath()
            ctx.fill(spike, with: .color(Color(accentColor)))
        }
    }
}
