import AppKit
import AVKit

/// The video and its native floating controls (play, scrub, volume, audio and
/// subtitle tracks, full screen), as in QuickTime Player.
final class PlayerView: AVPlayerView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        controlsStyle = .floating
        videoGravity = .resizeAspect
        showsFullScreenToggleButton = true
        showsSharingServiceButton = false
        showsFrameSteppingButtons = false
        allowsPictureInPicturePlayback = false
        // No Live Text or Visual Look Up on paused frames: it runs Vision on
        // every pause and loads VisionKit, for something Vids doesn't do.
        allowsVideoFrameAnalysis = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]).isEmpty
        if plain && key == "f" {
            window?.toggleFullScreen(nil)
        } else if event.keyCode == 53, window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)  // Esc
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The video's window. A double-click on the picture toggles full screen and a
/// drag on it moves the window; clicks on the controls work as usual.
final class PlayerWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isOnPicture(event) {
            if event.clickCount == 2 {
                toggleFullScreen(nil)
                return
            }
            if event.clickCount == 1, !styleMask.contains(.fullScreen) {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    /// True when the click lands on the video itself, not on a control or a
    /// title bar button. The playback controls are drawn by AVKit in views of
    /// its own, so they are told apart by size: the picture and its
    /// transparent overlays cover the whole video, every control is smaller.
    private func isOnPicture(_ event: NSEvent) -> Bool {
        guard let content = contentView, let frameView = content.superview,
              let view = frameView.hitTest(event.locationInWindow),
              view.isDescendant(of: content) else { return false }
        let covered = view.convert(view.bounds, to: nil)
        let picture = content.convert(content.bounds, to: nil)
        return covered.width >= picture.width - 1 && covered.height >= picture.height - 1
    }
}
