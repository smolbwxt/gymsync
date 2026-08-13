import Foundation

/// The hosted legal documents (V0 App Store requirement — ASC wants a
/// public privacy-policy URL, and the sign-in agreement text must actually
/// link somewhere). Source of truth lives in-repo at `docs/legal/`;
/// these URLs are where GitHub Pages serves them from. ONE place on
/// purpose: SignInView's footer and Settings' legal rows can never drift.
enum LegalLinks {
    static let privacy = URL(string: "https://smolbwxt.github.io/gymsync-legal/privacy.html")!
    static let terms = URL(string: "https://smolbwxt.github.io/gymsync-legal/terms.html")!
}
