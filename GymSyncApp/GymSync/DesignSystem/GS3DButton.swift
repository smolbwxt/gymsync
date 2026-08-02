import SwiftUI

// MARK: - GS3DButtonStyle
//
// The extruded press-down button (2026-08 visual-language redesign,
// Duolingo reference): a filled rounded face sitting on a slightly darker
// bottom lip of the same hue. Pressing sinks the face down onto the lip —
// vertical travel only, no scale. The style owns geometry and travel; the
// LABEL is whatever the caller provides (size it with frames/padding at
// the call site — the face hugs the label).
//
// Lip color: pass `lip:` explicitly, or leave nil to derive it by
// overlaying black at 0.35 over the face. NOTE: `theme.accent700` is a
// LIGHTER tint in every palette ramp (see GSTheme.swift — #7dd3fc on
// midnight/onyx), so it is NOT a valid lip; the derived darker overlay is
// the default path for accent faces.
public struct GS3DButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let face: Color
    let lip: Color?
    let cornerRadius: CGFloat
    let lipHeight: CGFloat

    public init(face: Color,
                lip: Color? = nil,
                cornerRadius: CGFloat = 16,
                lipHeight: CGFloat = 5) {
        self.face = face
        self.lip = lip
        self.cornerRadius = cornerRadius
        self.lipHeight = lipHeight
    }

    public func makeBody(configuration: Configuration) -> some View {
        // Disabled: face at half opacity, no travel.
        let pressed = configuration.isPressed && isEnabled
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius).fill(face)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .offset(y: pressed ? lipHeight : 0)
            .padding(.bottom, lipHeight)
            .background(lipLayer)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    /// The full-frame bottom layer the face lands on. When no explicit lip
    /// color is given, derive one by darkening the face: face fill + a
    /// black 0.35 overlay in the same rounded shape.
    @ViewBuilder
    private var lipLayer: some View {
        if let lip {
            RoundedRectangle(cornerRadius: cornerRadius).fill(lip)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius).fill(face)
                RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.35))
            }
        }
    }
}

// MARK: - Call-site sugar

public extension ButtonStyle where Self == GS3DButtonStyle {
    /// `.buttonStyle(.gs3D(face: theme.accent))` — see GS3DButtonStyle.
    static func gs3D(face: Color,
                     lip: Color? = nil,
                     cornerRadius: CGFloat = 16,
                     lipHeight: CGFloat = 5) -> GS3DButtonStyle {
        GS3DButtonStyle(face: face, lip: lip, cornerRadius: cornerRadius, lipHeight: lipHeight)
    }
}
