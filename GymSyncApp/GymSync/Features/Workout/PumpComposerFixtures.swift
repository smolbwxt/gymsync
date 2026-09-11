#if DEBUG
import UIKit

// MARK: - The pump composer's fixture world
//
// Plan task S2.6a. HERMETIC (global constraint 7): one solid-colour image
// drawn in process, one fixture summary, no clock, no camera, no HealthKit.
enum PumpComposerFixtures {

    /// A 1200 × 1200 flat tile standing in for a capture. Solid, not a
    /// gradient or noise: the frame is judged on the CARD, and a photo with
    /// detail in it invites a reviewer to judge the photo.
    static let photo: UIImage = {
        let size = CGSize(width: 1200, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()
}
#endif
