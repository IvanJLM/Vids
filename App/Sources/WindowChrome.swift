import AppKit

/// Hides the title bar into the video, as IINA does: the close, minimize and
/// zoom buttons appear while the mouse moves over the window and fade out
/// two seconds after it stops. The playback controls follow the same rhythm:
/// they exist while the mouse moves or the video is paused, and are taken
/// away while the video plays untouched, because AVKit keeps redrawing its
/// hidden time slider every frame (two thirds of Vids's CPU with 4K video).
/// Nothing runs while the mouse is still: the timer exists only while the
/// mouse has just moved.
@MainActor
final class WindowChrome: NSResponder {
    static let idleDelay: TimeInterval = 2
    /// Height of the band at the top that keeps the buttons visible.
    private static let titleBand: CGFloat = 40

    private weak var window: NSWindow?
    private let shade = TopShade()
    private(set) var hideTimer: Timer?
    private(set) var isShown = true
    /// True in full screen, where macOS manages the title bar itself.
    private var isSuspended = false
    /// Asked before hiding the pointer and the playback controls.
    var isPlaying: () -> Bool = { false }
    /// Adds (true) or removes (false) the playback controls.
    var showControls: (Bool) -> Void = { _ in }

    init(window: NSWindow) {
        self.window = window
        super.init()
        guard let content = window.contentView else { return }
        shade.frame = NSRect(x: 0, y: content.bounds.height - TopShade.height, width: content.bounds.width, height: TopShade.height)
        shade.autoresizingMask = [.width, .minYMargin]
        content.addSubview(shade)
        content.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var titlebar: NSView? { window?.standardWindowButton(.closeButton)?.superview }

    /// Shows the buttons and the controls, and starts the countdown to hide them.
    func show() {
        showControls(true)
        if !isShown && !isSuspended {
            isShown = true
            titlebar?.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                titlebar?.animator().alphaValue = 1
                shade.animator().alphaValue = 1
            }
        }
        restartTimer()
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        if isPlaying() { showControls(false) }
        guard isShown, !isSuspended else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            titlebar?.animator().alphaValue = 0
            shade.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.titlebar?.isHidden = true  // no clicks on invisible buttons
            }
        })
    }

    /// Paused: the controls come back. Playing with the mouse still: they go.
    func playbackChanged() {
        if !isPlaying() {
            showControls(true)
        } else if hideTimer == nil {
            showControls(false)
        }
    }

    /// Full screen: macOS shows the title bar when the pointer reaches the top.
    func suspend() {
        isSuspended = true
        isShown = true
        titlebar?.isHidden = false
        titlebar?.alphaValue = 1
        shade.alphaValue = 0
    }

    func resume() {
        isSuspended = false
        shade.alphaValue = 1
        show()
    }

    /// The window is closing: no timer outlives it.
    func stop() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func restartTimer() {
        let fire = Date().addingTimeInterval(Self.idleDelay)
        if let timer = hideTimer, timer.isValid {
            timer.fireDate = fire
        } else {
            let timer = Timer(timeInterval: Self.idleDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideIfIdle() }
            }
            timer.tolerance = 0.2  // lets macOS group the wake-up with others
            RunLoop.main.add(timer, forMode: .common)
            hideTimer = timer
        }
    }

    private func hideIfIdle() {
        hideTimer = nil
        guard let window, let content = window.contentView else { return }
        let point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = content.bounds.contains(point)
        if inside && point.y > content.bounds.height - Self.titleBand && !isSuspended {
            // The pointer rests on the buttons: they stay until it moves again,
            // without waking up every two seconds to check.
            if isPlaying() { showControls(false) }
            return
        }
        hide()
        if inside && window.isKeyWindow && isPlaying() { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    override func mouseEntered(with event: NSEvent) { show() }
    override func mouseMoved(with event: NSEvent) { show() }
    override func mouseExited(with event: NSEvent) { hide() }
}

/// A soft dark band behind the title bar buttons, so they read on bright video.
private final class TopShade: NSView {
    static let height: CGFloat = 64

    override init(frame: NSRect) {
        super.init(frame: frame)
        let gradient = CAGradientLayer()
        gradient.colors = [NSColor(white: 0, alpha: 0.45).cgColor, NSColor.clear.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer = gradient
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
