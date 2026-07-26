import SwiftUI
import WebKit

// MARK: - GSYouTubeEmbed
//
// Design: docs/superpowers/specs/2026-07-26-lifting-quality-design.md,
// Phase M. Renders YouTube's OFFICIAL iframe player in a WKWebView.
//
// THE COMPLIANCE LINE, stated where the next editor will see it: the iframe
// embed is the only permitted integration. Extracting the stream URL and
// playing it in AVPlayer violates YouTube's Terms of Service and is a known
// cause of App Store removal — do not "upgrade" this to a native player, no
// matter how much nicer it would look. Ads stay; that is the deal.
//
// youtube-nocookie.com: the privacy-enhanced host — no tracking cookies
// until playback starts, which keeps the app's privacy label honest.
//
// Failure is EXPLICIT: deleted/private/region-blocked/embedding-disabled
// videos all fail silently in a bare web view (black rectangle). At 200
// exercises some links WILL rot, so the unavailable state is designed in
// from day one, not bolted on after the first complaint.

struct GSYouTubeEmbed: View {
    @Environment(\.gsTheme) private var theme

    let videoID: String

    @State private var failed = false

    var body: some View {
        ZStack {
            if failed {
                unavailable
            } else {
                YouTubeWebView(videoID: videoID, onFailure: { failed = true })
            }
        }
        .background(Color.black)
        .cornerRadius(GSMetrics.radiusSm)
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: 26))
                .foregroundStyle(theme.neutral500)
            Text("Video unavailable")
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
            Text("It may have been removed or blocked for embedding.")
                .font(GSFont.body(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface)
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let videoID: String
    let onFailure: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Inline playback, not forced fullscreen — the demo sits in a card.
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        // playsinline=1 pairs with allowsInlineMediaPlayback; rel=0 keeps
        // end-screen suggestions to the same channel (can't remove them
        // entirely — terms again).
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0"
                allow="accelerometer; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen></iframe>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFailure: () -> Void
        init(onFailure: @escaping () -> Void) { self.onFailure = onFailure }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }
    }
}
