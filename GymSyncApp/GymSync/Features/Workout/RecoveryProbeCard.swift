import SwiftUI

// MARK: - RecoveryProbeCard
//
// "How's your chest from Tuesday?" — asked at the recap, about the LAST
// session's work, and asked again until the athlete says they are back.
//
// Owner 2026-08-26: "we should have a probe after every session talking
// about recovery from the previous routine and track it until recovered."
//
// ONE muscle at a time, on purpose. A session can train five, and a card
// asking about five is a form. The oldest open probe is the one shown,
// because the muscle trained longest ago is the one whose recovery time is
// closest to mattering — and answering it closes the longest-running
// question rather than the freshest.
//
// It is also skippable without penalty. VolumeTitration holds volume when
// the probe is silent (owner: "let's hold the volume until the probe has
// data"), so a skipped question costs the athlete nothing except a
// prescription that stays where it is. Nagging is not required to make the
// design work, which is exactly why it should not nag.
struct RecoveryProbeCard: View {
    @Environment(\.gsTheme) private var theme

    let probe: RecoveryProbe
    var onAnswer: (VolumeTitration.RecoveryState) -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECOVERY CHECK")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                Spacer()
                Button("SKIP", action: onSkip)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral500)
                    .buttonStyle(.plain)
            }

            Text(question)
                .font(GSFont.bold(19, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("This is how I work out how much volume you can actually take. Nothing else uses it.")
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(VolumeTitration.RecoveryState.allCases, id: \.self) { state in
                    Button { onAnswer(state) } label: {
                        HStack(spacing: 10) {
                            Text(label(for: state))
                                .font(GSFont.bold(14, relativeTo: .headline))
                                .tracking(0.4)
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 0)
                            if state.isRecovered {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: 13))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 18)
    }

    /// Names the muscle and how long ago it was trained, because "how's
    /// your chest?" and "how's your chest from four days ago?" are
    /// different questions and only the second one can be answered
    /// usefully.
    private var question: String {
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: probe.trainedAt),
            to: Calendar.current.startOfDay(for: .now)).day ?? 0
        let when: String
        switch days {
        case ...0: return "How's your \(probe.muscle) feeling after today?"
        case 1:    when = "yesterday"
        case 2...6: when = "\(days) days ago"
        default:   when = "last week"
        }
        return "How's your \(probe.muscle) from \(when)?"
    }

    private func label(for state: VolumeTitration.RecoveryState) -> String {
        switch state {
        case .fresh:   return "BACK TO NORMAL"
        case .tender:  return "SLIGHTLY TENDER"
        case .sore:    return "STILL SORE"
        case .wrecked: return "STILL WRECKED"
        }
    }
}
