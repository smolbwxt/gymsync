import SwiftUI
import AVKit

// MARK: - FormClipReviewSheet
//
// The NO-RETENTION path (owner ruling: "no retention if not pro"): the
// athlete just filmed a set, reviews it here once, and the file is
// deleted when the sheet closes. Nothing is ever uploaded on this path -
// the honesty line below says exactly that.
struct FormClipReviewSheet: View {
    @Environment(\.gsTheme) private var theme
    let url: URL
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("One-time review — this clip isn't kept. Saving form clips for your coach to scrub needs PRO or a linked coach.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .background(theme.bg)
            .navigationTitle("Form check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
