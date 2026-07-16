import SwiftUI
import UIKit

// MARK: - GSDemoView
//
// Two-frame animated exercise demonstration (Phase E). The live catalog's
// `demo_video_url` points at `exercise-media/<slug>/0.jpg` in Supabase
// Storage; a sibling `1.jpg` is guaranteed to exist (the importer only
// writes the URL after both frames upload) — this view derives that second
// frame's URL, downloads both via `URLSession.shared` (default `URLCache`
// gives caching), and alternates them through `UIImageView.animationImages`
// once both arrive. Shows the standard photo-glyph placeholder while
// loading, when `url` is nil, or if frame derivation fails; falls back to a
// static frame 0 if only frame 0 downloads successfully.
struct GSDemoView: View {
    let url: URL?
    @Environment(\.gsTheme) private var theme
    @State private var frame0: UIImage?
    @State private var frame1: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(theme.neutral300)
            if let frame0, let frame1 {
                AnimatedDemoImageView(frame0: frame0, frame1: frame1)
            } else if let frame0 {
                Image(uiImage: frame0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(theme.text.opacity(0.3))
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        frame0 = nil
        frame1 = nil
        guard let url else { return }
        let url1 = Self.frame1URL(from: url)
        async let a = Self.download(url)
        async let b = Self.download(url1 ?? url)
        let (img0, img1) = await (a, b)
        frame0 = img0
        frame1 = (url1 != nil) ? img1 : nil
    }

    /// Replaces the trailing `0.jpg` with `1.jpg`. Returns nil if `url`
    /// doesn't end in `0.jpg` (shouldn't happen per the importer's contract,
    /// but the caller treats nil as "no second frame" rather than crashing).
    private static func frame1URL(from url: URL) -> URL? {
        let suffix = "0.jpg"
        let s = url.absoluteString
        guard s.hasSuffix(suffix) else { return nil }
        return URL(string: String(s.dropLast(suffix.count)) + "1.jpg")
    }

    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - AnimatedDemoImageView

private struct AnimatedDemoImageView: UIViewRepresentable {
    let frame0: UIImage
    let frame1: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        // Without a low content-hugging/compression priority the intrinsic
        // image size fights the SwiftUI frame.
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        v.stopAnimating()
        v.animationImages = [frame0, frame1]
        v.animationDuration = 2.0
        v.animationRepeatCount = 0
        v.image = frame0
        v.startAnimating()
    }
}
