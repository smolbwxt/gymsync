import SwiftUI
import UIKit
import AVFoundation

// MARK: - FormClipCapture
//
// Form video v1 (owner rulings 2026-08-21): the system camera in movie
// mode, capped at 60s - a form check, not a vlog. Deliberately the
// stock picker rather than a custom AVCaptureSession: the athlete is
// mid-set, the fewer surprises the better, and the picker handles
// permission prompts, orientation, and storage pressure for free.
struct FormClipCapture: UIViewControllerRepresentable {
    /// Called with the recorded movie's temp URL, or nil on cancel.
    let onFinish: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 60
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

enum FormClipMath {
    /// Duration of a recorded movie, for the clip row.
    static func duration(of url: URL) -> Double? {
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// Re-encode before upload (storage v1.5): medium preset roughly
    /// halves file size at form-check quality. Returns the original URL
    /// when the export can't run - upload proceeds either way.
    static func compressed(_ url: URL) async -> URL {
        guard let export = AVAssetExportSession(
            asset: AVURLAsset(url: url),
            presetName: AVAssetExportPresetMediumQuality) else { return url }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        export.outputURL = out
        export.outputFileType = .mov
        await export.export()
        guard export.status == .completed else { return url }
        try? FileManager.default.removeItem(at: url)
        return out
    }
}
