import SwiftUI

/// Global layout tokens for the near-black redesign. Uniform across the app
/// (not per-palette) — the whole app is rounded and elevated now, unlike the
/// old zero-radius, flat Modernist system these tokens replace. Consume these
/// from every redesigned component rather than hard-coding numbers, so a future
/// retune happens in one place.
public enum GSMetrics {
    /// Corner radius for small controls (buttons, chips, tiles).
    public static let radiusSm: CGFloat = 16
    /// Corner radius for the standard widget/card.
    public static let radiusMd: CGFloat = 24
    /// Fully-rounded (pills, avatars).
    public static let pill: CGFloat = 999

    // Spacing scale — matches the proof mockups' 4/8/11/16/24 rhythm.
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 11
    public static let space4: CGFloat = 16
    public static let space6: CGFloat = 24
}

public extension View {
    /// The standard widget elevation — a soft ink shadow tuned for the
    /// near-black ground. Apply to floating cards/widgets.
    func gsElevation() -> some View {
        shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 8)
    }
}
