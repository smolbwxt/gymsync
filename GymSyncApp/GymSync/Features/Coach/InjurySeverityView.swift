import SwiftUI

// MARK: - InjurySeverityView
//
// "How bad is it?" — one row per joint the athlete just named, two
// answers. Owner 2026-08-27: "let's think more critically about what
// each injury means. I'm not squatting or deadlifting if my hip is
// severely injured."
//
// The two answers are two different LEVERS, and the copy says which:
//   WORKING AROUND IT — a caution. Lifts that load the joint sort last in
//                       selection; they can still appear when nothing
//                       else fills the slot.
//   INJURED           — an exclusion. Every lift that loads the joint is
//                       out of the block; the pattern it rules out gets
//                       no main lift.
// Selection carries "joint=severe" for injured joints; an unmarked joint
// is a caution.
struct InjurySeverityView: View {
    let joints: [String]
    @Binding var selection: Set<String>

    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            ForEach(joints, id: \.self) { joint in
                row(joint)
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ joint: String) -> some View {
        let token = "\(joint)=severe"
        let injured = selection.contains(token)
        return VStack(alignment: .leading, spacing: 8) {
            Text(ConsultVocabulary.display(joint))
                .font(GSFont.bold(15, relativeTo: .headline))
                .tracking(0.3)
                .foregroundStyle(theme.text)
            HStack(spacing: 8) {
                choice("WORKING AROUND IT",
                       detail: "I steer clear where I can",
                       picked: !injured) { selection.remove(token) }
                choice("INJURED",
                       detail: "Nothing that loads it, at all",
                       picked: injured) { selection.insert(token) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 15)
    }

    private func choice(_ label: String, detail: String, picked: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(picked ? theme.bg : theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(GSFont.body(10, relativeTo: .caption2))
                    .foregroundStyle(picked ? theme.bg.opacity(0.8) : theme.neutral700)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.gs3D(face: picked ? theme.accent : theme.raised3DFace,
                           lip: theme.raised3DLip,
                           cornerRadius: 10, lipHeight: 3))
    }
}
