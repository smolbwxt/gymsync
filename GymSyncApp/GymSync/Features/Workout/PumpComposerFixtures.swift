#if DEBUG
import UIKit

// MARK: - The pump composer's fixture world
//
// Plan task S2.6a. HERMETIC (global constraint 7): one solid-colour image
// drawn in process, one fixture summary, no clock, no camera, no HealthKit.
enum PumpComposerFixtures {

    /// A 1200 × 1200 tile standing in for a capture: a diagonal gradient with
    /// two tonal blocks over it, every value LIGHTER than the composer card's
    /// surface.
    ///
    /// IT HAS TO READ AS A PHOTO (review fix 11b). The first version was a
    /// single flat `rgb(51, 56, 64)`, which on Onyx sits almost exactly on the
    /// card surface — so the 84 pt thumbnail in frame 102 read as a failed
    /// image load, and a reviewer's first question about the frame was about
    /// the photo rather than about the picker the frame exists to show. Enough
    /// structure to be obviously an image; not enough to be worth looking at.
    ///
    /// HERMETIC (global constraint 7): drawn in process from fixed numbers —
    /// no bundled asset, no clock, no RNG — so it is byte-for-byte the same on
    /// every run.
    static let photo: UIImage = {
        let size = CGSize(width: 1200, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            let colors = [
                UIColor(red: 0.42, green: 0.45, blue: 0.52, alpha: 1).cgColor,
                UIColor(red: 0.30, green: 0.33, blue: 0.39, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: [])
            } else {
                UIColor(red: 0.36, green: 0.39, blue: 0.46, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            // Two blocks, so the tile has a subject rather than just a ramp.
            UIColor(red: 0.55, green: 0.58, blue: 0.64, alpha: 1).setFill()
            context.fill(CGRect(x: 180, y: 300, width: 380, height: 600))
            UIColor(red: 0.24, green: 0.27, blue: 0.33, alpha: 1).setFill()
            context.fill(CGRect(x: 660, y: 480, width: 300, height: 420))
        }
    }()
}
#endif
