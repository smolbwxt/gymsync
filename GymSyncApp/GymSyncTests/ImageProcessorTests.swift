import XCTest
import UIKit
@testable import GymSync

final class ImageProcessorTests: XCTestCase {
    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let img = renderer.image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return img.pngData()!
    }

    func testDownscalesLargeImageToMaxDimension() throws {
        let data = makeImageData(width: 4000, height: 2000)
        let jpeg = try XCTUnwrap(ImageProcessor.jpegForUpload(from: data))
        let out = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertLessThanOrEqual(max(out.size.width, out.size.height), 1600)
        XCTAssertEqual(out.size.width / out.size.height, 2.0, accuracy: 0.05,
                       "aspect ratio preserved")
    }

    func testSmallImageNotUpscaled() throws {
        let data = makeImageData(width: 300, height: 200)
        let jpeg = try XCTUnwrap(ImageProcessor.jpegForUpload(from: data))
        let out = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(out.size.width, 300, accuracy: 2)
    }

    func testGarbageDataReturnsNil() {
        XCTAssertNil(ImageProcessor.jpegForUpload(from: Data([0x00, 0x01, 0x02])))
    }
}
