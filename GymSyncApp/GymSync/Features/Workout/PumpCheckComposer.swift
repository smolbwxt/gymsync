import SwiftUI
import UIKit

// MARK: - Pump Check composer (spec 2026-07-27, P2)
//
// The BeReal-style moment: mounts at the top of a recap with a live 1:00
// countdown. Capture inside the window posts clean; capture after it posts
// with a "late" badge (spec decision 1 — the countdown is urgency, not a
// wall). The composer lives ONLY in the recap: dismiss without posting and
// the moment is gone. Skip is always one tap; nothing nags.

/// Post-ready payload built by the SESSION view (which holds the raw
/// state); the recap only renders and posts it — the same display-ready
/// convention as every other recap field.
struct PumpCheckContext {
    let sessionID: UUID
    let summary: PostSummary
    let avgBpm: Int?
    let maxBpm: Int?
    /// Spec decision 2: the HR toggle's starting position — the caller
    /// derives it from the user's share_heart_rate setting (and whether HR
    /// stats exist at all).
    let includeHRDefault: Bool
    /// The moment the recap appeared — anchor of the 1:00 window.
    let windowStart: Date
}

struct PumpCheckComposerCard: View {
    let context: PumpCheckContext

    @Environment(\.gsTheme) private var theme

    @State private var showCamera = false
    @State private var photo: UIImage?
    /// Stamped when a capture lands — late is a fact about WHEN you shot
    /// it, not when you tapped Post.
    @State private var capturedLate = false
    @State private var includeHR: Bool
    @State private var isPosting = false
    @State private var posted = false
    @State private var skipped = false
    @State private var errorText: String?

    init(context: PumpCheckContext) {
        self.context = context
        _includeHR = State(initialValue: context.includeHRDefault)
    }

    private var windowEnd: Date { context.windowStart.addingTimeInterval(60) }
    private var windowOpen: Bool { Date() < windowEnd }

    var body: some View {
        if !skipped {
            GSCard(bordered: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if posted {
                        postedRow
                    } else if let photo {
                        reviewBlock(photo)
                    } else {
                        captureRow
                    }
                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    photo = image
                    capturedLate = Date() > windowEnd
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Idle: CTA + live countdown

    private var captureRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text("Pump check")
                        .font(GSFont.bold(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    if windowOpen {
                        // Live countdown, no Timer — same
                        // Text(timerInterval:) idiom as the rest timer.
                        Text(timerInterval: context.windowStart...windowEnd,
                             countsDown: true)
                            .font(GSFont.bold(13, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(theme.accent700)
                    } else {
                        GSTag(text: "late", style: .neutral)
                    }
                }
                Text("Snap it now — your friends see the photo and the receipts.")
                    .font(GSFont.body(11.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer(minLength: 8)
            Button {
                showCamera = true
            } label: {
                Text("Snap")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 13, verticalPadding: 9))
            Button {
                withAnimation(.easeOut(duration: 0.15)) { skipped = true }
            } label: {
                Text("Skip")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Review: thumbnail + HR toggle + post

    private func reviewBlock(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Looking strong")
                            .font(GSFont.bold(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        if capturedLate {
                            GSTag(text: "late", style: .neutral)
                        }
                    }
                    Text("Posts to friends only, with your workout summary.")
                        .font(GSFont.body(11.5, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    if context.avgBpm != nil {
                        Toggle(isOn: $includeHR) {
                            Text("Include heart rate")
                                .font(GSFont.body(12.5, relativeTo: .caption))
                                .foregroundStyle(theme.text)
                        }
                        .tint(theme.accent)
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    Task { await post(image) }
                } label: {
                    if isPosting {
                        ProgressView().tint(theme.bg)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Post").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 11))
                .disabled(isPosting)
                Button {
                    photo = nil
                    showCamera = true
                } label: {
                    Text("Retake")
                        .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isPosting)
            }
        }
    }

    private var postedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text("Shared with your friends")
                .font(GSFont.bold(13.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
        }
    }

    // MARK: - Post

    @MainActor
    private func post(_ image: UIImage) async {
        guard !isPosting else { return }
        isPosting = true
        defer { isPosting = false }
        // UIImage → JPEG re-encode strips EXIF (incl. GPS); jpegForUpload
        // then bounds the dimensions like every other upload in the app.
        guard let raw = image.jpegData(compressionQuality: 0.9),
              let jpeg = ImageProcessor.jpegForUpload(from: raw, maxDimension: 1600) else {
            errorText = "That photo couldn't be processed."
            return
        }
        do {
            _ = try await WorkoutPostRepository.create(
                sessionID: context.sessionID,
                summary: context.summary,
                photoJPEG: jpeg,
                includesHR: includeHR && context.avgBpm != nil,
                avgBpm: context.avgBpm,
                maxBpm: context.maxBpm,
                isLate: capturedLate)
            errorText = nil
            withAnimation(.easeOut(duration: 0.2)) { posted = true }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Camera capture

/// Minimal camera wrapper — front camera by default (it's a selfie moment).
/// Falls back to the photo library where no camera exists (Simulator),
/// which is also what makes the flow QA-able in captures.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .front
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
