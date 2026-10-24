import CoreGraphics
import XCTest
@testable import Vids

final class SizingTests: XCTestCase {
    func testSmallVideosOpenAtActualSize() {
        XCTAssertEqual(WindowSizing.fit(CGSize(width: 640, height: 360), in: CGSize(width: 1500, height: 900)),
                       CGSize(width: 640, height: 360))
    }

    func testLargeVideosShrinkToFitKeepingTheirShape() {
        XCTAssertEqual(WindowSizing.fit(CGSize(width: 3840, height: 2160), in: CGSize(width: 1500, height: 900)),
                       CGSize(width: 1500, height: 844))
        XCTAssertEqual(WindowSizing.fit(CGSize(width: 1080, height: 1920), in: CGSize(width: 1500, height: 900)),
                       CGSize(width: 506, height: 900))
    }

    func testScaleIsAppliedBeforeFitting() {
        XCTAssertEqual(WindowSizing.fit(CGSize(width: 640, height: 360), scale: 0.5, in: CGSize(width: 1500, height: 900)),
                       CGSize(width: 320, height: 180))
        XCTAssertEqual(WindowSizing.fit(CGSize(width: 1280, height: 720), scale: 2, in: CGSize(width: 1500, height: 900)),
                       CGSize(width: 1500, height: 844))
    }

    func testMinimumKeepsTheShortSide() {
        XCTAssertEqual(WindowSizing.minimum(for: CGSize(width: 1920, height: 1080)), CGSize(width: 320, height: 180))
        XCTAssertEqual(WindowSizing.minimum(for: CGSize(width: 1080, height: 1920)), CGSize(width: 180, height: 320))
    }

    func testCenteredKeepsTheMiddle() {
        let frame = WindowSizing.centered(CGSize(width: 100, height: 50), on: CGRect(x: 0, y: 0, width: 300, height: 150))
        XCTAssertEqual(frame, CGRect(x: 100, y: 50, width: 100, height: 50))
    }

    func testDisplaySizeFollowsRotationAndPixelAspect() {
        let upright = CGAffineTransform(rotationAngle: .pi / 2)
        XCTAssertEqual(VideoInfo.displaySize(natural: CGSize(width: 1920, height: 1080), transform: upright, pixelAspect: 1),
                       CGSize(width: 1080, height: 1920))
        // Anamorphic PAL DVD: 720×576 stored, 16:9 shown.
        XCTAssertEqual(VideoInfo.displaySize(natural: CGSize(width: 720, height: 576), transform: .identity, pixelAspect: 64.0 / 45.0),
                       CGSize(width: 1024, height: 576))
    }
}
