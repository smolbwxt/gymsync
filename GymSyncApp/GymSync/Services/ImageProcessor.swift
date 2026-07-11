import UIKit

enum ImageProcessor {
    /// Re-renders to JPEG capped at maxDimension. Re-rendering also strips EXIF (incl. GPS).
    static func jpegForUpload(from data: Data,
                              maxDimension: CGFloat = 1600,
                              quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let largestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / largestSide)
        let targetSize = CGSize(width: image.size.width * scale,
                                height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize,
                                               format: .init(for: .init(displayScale: 1)))
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
