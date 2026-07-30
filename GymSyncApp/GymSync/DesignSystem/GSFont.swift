import SwiftUI

// MARK: - GSFont

/// Static helpers for the GymSync Archivo type scale.
/// Every helper uses `.custom(_:size:relativeTo:)` so the system can
/// scale sizes with Dynamic Type (`UIFontMetrics`-equivalent).
public enum GSFont {

    /// Archivo SemiBold — used for headings / display copy.
    public static func heading(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .headline) -> Font {
        .custom("Archivo-SemiBold", size: size, relativeTo: textStyle)
    }

    /// Archivo Regular — used for body copy.
    public static func body(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Archivo-Regular", size: size, relativeTo: textStyle)
    }

    /// Archivo Medium — used for emphasis within body copy.
    public static func bodyMedium(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Archivo-Medium", size: size, relativeTo: textStyle)
    }

    /// Archivo Bold — used for strong emphasis / call-to-action labels.
    public static func bold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Archivo-Bold", size: size, relativeTo: textStyle)
    }

    /// Archivo Bold at a FIXED size — deliberately exempt from Dynamic Type.
    ///
    /// For big numerals that live inside hard-framed rows on the live
    /// session's fixed (non-scrolling) page: the 52pt heart-rate readout, the
    /// 36pt weight/reps entry values, the RPE track numerals. These frames
    /// cannot grow with the Settings slider, so a `relativeTo:` font inside
    /// them CLIPS at large text sizes — the exact defect that condemned the
    /// old RPESegmentBar (hard 30pt frame + scaling label). Their meaning is
    /// carried redundantly by adjacent `relativeTo:`-scaling labels
    /// (WEIGHT · LBS, RPE) and by VoiceOver, so accessibility is preserved
    /// while the numeral stays geometrically honest.
    ///
    /// Use ONLY where the container's height is a design constant; everywhere
    /// else, use `bold(_:relativeTo:)`.
    public static func boldFixed(_ size: CGFloat) -> Font {
        .custom("Archivo-Bold", fixedSize: size)
    }
}
