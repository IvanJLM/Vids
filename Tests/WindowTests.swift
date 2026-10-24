import AppKit
import AVKit
import XCTest
@testable import Vids

/// The window's life: controls only while they can be seen, nothing left
/// behind when it closes, and windows opened together side by side.
@MainActor
final class WindowTests: XCTestCase {
    private func openWindow(_ url: URL, cascadeFrom other: NSWindow? = nil) async -> PlayerWindowController {
        let controller = PlayerWindowController(cascadeFrom: other)
        let done = expectation(description: "loaded")
        controller.onReady = { _ in done.fulfill() }
        controller.onFailure = { _, _, _ in done.fulfill() }
        controller.open(url)
        await fulfillment(of: [done], timeout: 10)
        return controller
    }

    private func wait(_ seconds: Double) async {
        let idle = expectation(description: "wait")
        idle.isInverted = true
        await fulfillment(of: [idle], timeout: seconds)
    }

    func testMacOSNeverQuitsVidsBehindAHiddenWindow() {
        // With automatic termination, macOS may kill an app whose windows are
        // hidden or on another space, even while a video plays.
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSSupportsAutomaticTermination"))
    }

    func testControlsOnlyWhileTheyCanBeSeen() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        let chrome = WindowChrome(window: window)
        var playing = true
        var controls: [Bool] = []
        chrome.isPlaying = { playing }
        chrome.showControls = { controls.append($0) }

        chrome.show()
        XCTAssertEqual(controls.last, true, "the mouse moved: controls")
        let timer = try? XCTUnwrap(chrome.hideTimer)
        XCTAssertGreaterThan(timer?.tolerance ?? 0, 0, "the hide timer may be grouped with other wake-ups")

        chrome.hide()
        XCTAssertEqual(controls.last, false, "playing and idle: no controls")
        XCTAssertNil(chrome.hideTimer)

        playing = false
        chrome.playbackChanged()
        XCTAssertEqual(controls.last, true, "paused: controls back")
        chrome.hide()
        XCTAssertEqual(controls.last, true, "paused: controls stay when the buttons fade")

        playing = true
        chrome.playbackChanged()
        XCTAssertEqual(controls.last, false, "playing again with the mouse still: controls go")

        chrome.show()
        chrome.playbackChanged()
        XCTAssertEqual(controls.last, true, "playing while the mouse moves: controls stay")
        chrome.stop()
        XCTAssertNil(chrome.hideTimer, "no timer outlives the window")
    }

    func testPlayingVideoDropsItsControlsWhenIdle() async throws {
        let url = try await Fixtures.video(in: try Fixtures.folder(self), seconds: 10)
        let controller = await openWindow(url)
        defer { controller.close() }
        let view = try XCTUnwrap(controller.window?.contentView?.subviews.first as? AVPlayerView)
        XCTAssertEqual(view.controlsStyle, .floating, "controls when the window opens")
        await wait(WindowChrome.idleDelay + 0.6)
        XCTAssertEqual(controller.player.timeControlStatus, .playing)
        XCTAssertEqual(view.controlsStyle, .none, "playing untouched: AVKit's controls are gone")
        controller.player.pause()
        await wait(0.3)
        XCTAssertEqual(view.controlsStyle, .floating, "paused: controls back")
    }

    func testClosingAWindowFreesIt() async throws {
        let url = try await Fixtures.video(in: try Fixtures.folder(self))
        for round in 0..<3 {
            weak var freedController: PlayerWindowController?
            weak var freedWindow: NSWindow?
            var controller: PlayerWindowController? = await openWindow(url)
            freedController = controller
            freedWindow = controller?.window
            controller?.close()
            controller = nil
            await wait(0.1)
            XCTAssertNil(freedController, "controller \(round) freed")
            XCTAssertNil(freedWindow, "window \(round) freed")
        }
    }

    func testVideosOpenedTogetherDoNotStack() async throws {
        // Finder opening several files: the second window is created before
        // the first one is on screen.
        let folder = try Fixtures.folder(self)
        let a = try await Fixtures.video(in: folder, name: "a.mp4")
        let b = try await Fixtures.video(in: folder, name: "b.mp4")
        let first = PlayerWindowController(cascadeFrom: nil)
        let second = PlayerWindowController(cascadeFrom: first.window)
        defer { first.close(); second.close() }
        let loaded = [expectation(description: "a"), expectation(description: "b")]
        for (controller, done) in zip([first, second], loaded) {
            controller.onReady = { _ in done.fulfill() }
            controller.onFailure = { _, _, _ in done.fulfill() }
        }
        first.open(a)
        second.open(b)
        await fulfillment(of: loaded, timeout: 10)
        let one = try XCTUnwrap(first.window?.frame), two = try XCTUnwrap(second.window?.frame)
        XCTAssertNotEqual(one.origin, two.origin)
    }

    func testShortcutsAreMenuKeysThatThePictureLeavesAlone() async throws {
        // Space, the arrows and M reach the player through the menu bar. The
        // picture (AVKit) must not claim them first.
        let url = try await Fixtures.video(in: try Fixtures.folder(self))
        let controller = await openWindow(url)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let menu = try XCTUnwrap(NSApp.mainMenu)
        func item(_ action: Selector) -> NSMenuItem? {
            menu.items.lazy.compactMap { $0.submenu?.items.first { $0.action == action } }.first
        }
        let arrows: [(Selector, Int, UInt16)] = [
            (#selector(PlayerWindowController.skipForward(_:)), NSRightArrowFunctionKey, 124),
            (#selector(PlayerWindowController.skipBackward(_:)), NSLeftArrowFunctionKey, 123),
            (#selector(PlayerWindowController.volumeUp(_:)), NSUpArrowFunctionKey, 126),
            (#selector(PlayerWindowController.volumeDown(_:)), NSDownArrowFunctionKey, 125),
        ]
        var keys: [(Selector, String, UInt16, NSEvent.ModifierFlags)] = arrows.map {
            ($0.0, String(Character(UnicodeScalar(UInt16($0.1))!)), $0.2, [.function, .numericPad])
        }
        keys.append((#selector(PlayerWindowController.togglePlayback(_:)), " ", 49, []))
        keys.append((#selector(PlayerWindowController.toggleMute(_:)), "m", 46, []))
        for (action, characters, code, flags) in keys {
            let entry = try XCTUnwrap(item(action), "\(action) is in the menu bar")
            XCTAssertEqual(entry.keyEquivalent, characters, "\(action)")
            XCTAssertEqual(entry.keyEquivalentModifierMask, [], "\(action) needs no modifier")
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            XCTAssertFalse(window.performKeyEquivalent(with: event), "the picture leaves \(action) to the menu")
        }
    }
}
