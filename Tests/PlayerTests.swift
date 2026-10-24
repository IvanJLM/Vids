import AppKit
import AVFoundation
import UniformTypeIdentifiers
import XCTest
@testable import Vids

@MainActor
final class PlayerTests: XCTestCase {
    private func openWindow(_ url: URL) async -> (PlayerWindowController, Error?) {
        let controller = PlayerWindowController(cascadeFrom: nil)
        var failure: Error?
        let done = expectation(description: "loaded")
        controller.onReady = { _ in done.fulfill() }
        controller.onFailure = { _, _, error in failure = error; done.fulfill() }
        controller.open(url)
        await fulfillment(of: [done], timeout: 10)
        return (controller, failure)
    }

    func testPlaysAVideoInAWindowShapedLikeIt() async throws {
        let url = try await Fixtures.video(in: try Fixtures.folder(self), width: 320, height: 180)
        let (controller, failure) = await openWindow(url)
        XCTAssertNil(failure)
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.title, "clip.mp4")
        XCTAssertEqual(controller.videoSize, CGSize(width: 320, height: 180))
        XCTAssertEqual(window.contentView?.frame.size, CGSize(width: 320, height: 180), "small videos open at 100 %")
        XCTAssertNotEqual(controller.player.rate, 0, "playback starts by itself")
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "the video runs under the title bar")

        var closed = false
        controller.onClose = { _ in closed = true }
        controller.close()
        XCTAssertTrue(closed)
        XCTAssertNil(controller.player.currentItem, "closing lets go of the video")
    }

    func testPhoneVideosStandUpright() async throws {
        let url = try await Fixtures.video(in: try Fixtures.folder(self), name: "phone.mov", width: 320, height: 180,
                                           transform: CGAffineTransform(rotationAngle: .pi / 2), codec: .hevc)
        let (controller, failure) = await openWindow(url)
        defer { controller.close() }
        XCTAssertNil(failure)
        XCTAssertEqual(controller.videoSize, CGSize(width: 180, height: 320))
        let size = try XCTUnwrap(controller.window?.contentView?.frame.size)
        XCTAssertEqual(size.width / size.height, 180.0 / 320.0, accuracy: 0.01)
    }

    func testFilesMacOSCantPlayAreReportedWithoutAWindow() async throws {
        let folder = try Fixtures.folder(self)
        for name in ["broken.mp4", "movie.mkv"] {
            let url = folder.appendingPathComponent(name)
            try Data(repeating: 7, count: 4096).write(to: url)
            let (controller, failure) = await openWindow(url)
            XCTAssertNotNil(failure, name)
            XCTAssertNotEqual(controller.window?.isVisible, true, name)
            if let failure {
                let message = PlaybackError.message(for: url, error: failure)
                XCTAssertTrue(message.title.contains(name))
                if name.hasSuffix(".mkv") { XCTAssertTrue(message.detail.contains("MKV")) }
            }
        }
    }

    func testSkipAndVolume() async throws {
        let url = try await Fixtures.video(in: try Fixtures.folder(self))
        let (controller, _) = await openWindow(url)
        defer { controller.close() }
        controller.player.pause()
        controller.player.volume = 0.5
        controller.volumeUp(nil)
        XCTAssertEqual(controller.player.volume, 0.6, accuracy: 0.001)
        controller.volumeDown(nil)
        controller.volumeDown(nil)
        XCTAssertEqual(controller.player.volume, 0.4, accuracy: 0.001)
        controller.toggleMute(nil)
        XCTAssertTrue(controller.player.isMuted)
        controller.volumeUp(nil)
        XCTAssertFalse(controller.player.isMuted, "changing the volume unmutes")
    }

    func testTrackMenusListWhatTheVideoHas() async throws {
        let url = try await Fixtures.video(in: try Fixtures.folder(self))
        let (controller, _) = await openWindow(url)
        defer { controller.close() }
        let menu = NSMenu()
        controller.fillTrackMenu(menu, subtitles: true)
        XCTAssertEqual(menu.items.map(\.title), ["None"], "a video without subtitles")
    }

    func testDeclaredTypesAreAllPlayableAndCoverTheCommonOnes() {
        let declared = VideoTypes.declared.map(\.identifier)
        XCTAssertFalse(declared.isEmpty)
        let playable = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))
        for identifier in declared {
            XCTAssertTrue(playable.contains(identifier), "\(identifier) is not playable by AVFoundation")
            XCTAssertTrue(UTType(identifier)?.conforms(to: .movie) == true, "\(identifier) is not a movie type")
        }
        XCTAssertTrue(Set(DefaultPlayer.commonTypes).isSubset(of: declared))
        XCTAssertFalse(declared.contains("public.movie"), "never claim formats macOS can't play")
    }
}
