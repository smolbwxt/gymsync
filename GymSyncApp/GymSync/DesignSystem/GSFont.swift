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
}
