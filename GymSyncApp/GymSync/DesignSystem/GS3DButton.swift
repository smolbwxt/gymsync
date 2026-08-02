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
// overlaying black at 0.45 over the face. NOTE: `theme.accent700` is a
// LIGHTER tint in every palette ramp (see GSTheme.swift — #7dd3fc on
// midnight/onyx), so it is NOT a valid lip; the derived darker overlay is
// the default path for accent faces.
//
// Face color: NEVER `theme.surface` or `theme.bg` — on the dark palettes
// they sit so close to the page ground that the derived lip cannot read
// (owner field report 2026-08: "not seeing the 3D buttons"). Neutral
// (non-accent) buttons use the theme-tuned raised pair instead:
// `face: theme.raised3DFace, lip: theme.raised3DLip` (GSTheme.swift) —
// face clearly lighter than the ground, lip clearly darker, per palette.
public struct GS3DButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let face: Color
    let lip: Color?
    let cornerRadius: CGFloat
    let lipHeight: CGFloat

    public init(face: Color,
                lip: Color? = nil,
                cornerRadius: CGFloat = 16,
                lipHeight: CGFloat = 7) {
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
    /// black 0.45 overlay in the same rounded shape.
    @ViewBuilder
    private var lipLayer: some View {
        if let lip {
            RoundedRectangle(cornerRadius: cornerRadius).fill(lip)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius).fill(face)
                RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.45))
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
                     lipHeight: CGFloat = 7) -> GS3DButtonStyle {
        GS3DButtonStyle(face: face, lip: lip, cornerRadius: cornerRadius, lipHeight: lipHeight)
    }
}

// MARK: - GS3DCard (widget extrusion, 2026-08 "every widget gets depth")
//
// The card-class sibling of `GS3DButtonStyle`: the same face-on-lip anatomy
// applied to WIDGETS — the chunky rounded containers (You grid, Shop tiles,
// Home cards, lobby cards). Two forms:
//
//   * `.gs3DCard(...)` (ViewModifier) — static containers. Face + lip, no
//     press travel.
//   * `.buttonStyle(.gs3DCardStyle(...))` — tappable cards (Button /
//     NavigationLink labels). Same geometry plus the press-sink, so a
//     tappable widget animates exactly like the RACK IT button.
//
// Conventions (mirror the button precedent):
//   * Default lip is 6pt — one step quieter than the 7pt buttons.
//   * `face`/`lip` default to nil = the theme's tuned neutral raised pair
//     (`theme.raised3DFace`/`theme.raised3DLip`). An EXPLICIT non-neutral
//     face (accent, gold) with no explicit lip derives its lip the way
//     accent buttons do: face + black 0.45 overlay.
//   * The face REPLACES `theme.surface` and the old 1pt neutral500 stroke
//     disappears — the lip is what delineates the card now.
//   * The lip lives INSIDE the composite's frame: give a fixed-height card
//     a face of (total − lipHeight) so the layout footprint never grows
//     (Shop's 172pt tiles keep 172).
//   * Content + face are clipped to the rounded shape (the `GSCard`
//     behavior the converted widgets relied on for full-bleed inner rows).

private struct GS3DCardChrome {
    let cornerRadius: CGFloat
    let lipHeight: CGFloat
    let face: Color?
    let lip: Color?

    func faceColor(_ theme: GSTheme) -> Color {
        face ?? theme.raised3DFace
    }

    /// The lip layer under the face. Explicit lip wins; a neutral (default)
    /// face falls back to the theme's raised pair; an explicit face with no
    /// explicit lip derives a darker lip (face + black 0.45 — the accent
    /// button path; `accent700` is a LIGHTER tint, never a lip).
    @ViewBuilder
    func lipLayer(_ theme: GSTheme) -> some View {
        if let lip {
            RoundedRectangle(cornerRadius: cornerRadius).fill(lip)
        } else if let face {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius).fill(face)
                RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.45))
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius).fill(theme.raised3DLip)
        }
    }
}

/// Static extruded card — see the GS3DCard MARK above.
public struct GS3DCardModifier: ViewModifier {
    @Environment(\.gsTheme) private var theme

    private let chrome: GS3DCardChrome

    public init(cornerRadius: CGFloat = 16,
                lipHeight: CGFloat = 6,
                face: Color? = nil,
                lip: Color? = nil) {
        chrome = GS3DCardChrome(cornerRadius: cornerRadius, lipHeight: lipHeight,
                                face: face, lip: lip)
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: chrome.cornerRadius)
                    .fill(chrome.faceColor(theme))
            )
            .clipShape(RoundedRectangle(cornerRadius: chrome.cornerRadius))
            .padding(.bottom, chrome.lipHeight)
            .background(chrome.lipLayer(theme))
    }
}

public extension View {
    /// `.gs3DCard()` — static extruded widget card (face + lip, no travel).
    /// See the GS3DCard MARK in GS3DButton.swift.
    func gs3DCard(cornerRadius: CGFloat = 16,
                  lipHeight: CGFloat = 6,
                  face: Color? = nil,
                  lip: Color? = nil) -> some View {
        modifier(GS3DCardModifier(cornerRadius: cornerRadius, lipHeight: lipHeight,
                                  face: face, lip: lip))
    }
}

/// Interactive extruded card — the tappable-widget companion of
/// `GS3DCardModifier`: identical geometry, plus the RACK IT press-sink.
/// Content = the card's own label (the caller supplies padding/frames; the
/// face hugs the label, exactly like `GS3DButtonStyle`).
public struct GS3DCardStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let chrome: GS3DCardChrome

    public init(cornerRadius: CGFloat = 16,
                lipHeight: CGFloat = 6,
                face: Color? = nil,
                lip: Color? = nil) {
        chrome = GS3DCardChrome(cornerRadius: cornerRadius, lipHeight: lipHeight,
                                face: face, lip: lip)
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: chrome.cornerRadius)
                    .fill(chrome.faceColor(theme))
            )
            .clipShape(RoundedRectangle(cornerRadius: chrome.cornerRadius))
            .opacity(isEnabled ? 1 : 0.5)
            .offset(y: pressed ? chrome.lipHeight : 0)
            .padding(.bottom, chrome.lipHeight)
            .background(chrome.lipLayer(theme))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

public extension ButtonStyle where Self == GS3DCardStyle {
    /// `.buttonStyle(.gs3DCardStyle())` — see GS3DCardStyle.
    static func gs3DCardStyle(cornerRadius: CGFloat = 16,
                              lipHeight: CGFloat = 6,
                              face: Color? = nil,
                              lip: Color? = nil) -> GS3DCardStyle {
        GS3DCardStyle(cornerRadius: cornerRadius, lipHeight: lipHeight,
                      face: face, lip: lip)
    }
}
