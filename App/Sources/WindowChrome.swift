import AppKit

/// Hides the title bar into the video, as IINA does: the close, minimize and
/// zoom buttons appear while the mouse moves over the window and fade out
/// two seconds after it stops. Nothing runs while the mouse is still: the
/// timer exists only while the buttons are visible.
@MainActor
final class WindowChrome: NSResponder {
    static let idleDelay: TimeInterval = 2
    /// Height of the band at the top that keeps the buttons visible.
    private static let titleBand: CGFloat = 40

    private weak var window: NSWindow?
    private let shade = TopShade()
    private var hideTimer: Timer?
    private(set) var isShown = true
    /// True in full screen, where macOS manages the title bar itself.
    private var isSuspended = false
    /// Asked before hiding the pointer along with the buttons.
    var isPlaying: () -> Bool = { false }

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

    /// Shows the buttons and starts the countdown to hide them.
    func show() {
        guard !isSuspended else { return }
        if !isShown {
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

    /// Full screen: macOS shows the title bar when the pointer reaches the top.
    func suspend() {
        hideTimer?.invalidate()
        hideTimer = nil
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

    private func restartTimer() {
        let fire = Date().addingTimeInterval(Self.idleDelay)
        if let timer = hideTimer, timer.isValid {
            timer.fireDate = fire
        } else {
            hideTimer = Timer.scheduledTimer(withTimeInterval: Self.idleDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideIfIdle() }
            }
        }
    }

    private func hideIfIdle() {
        hideTimer = nil
        guard let window, let content = window.contentView else { return }
        let point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = content.bounds.contains(point)
        if inside && point.y > content.bounds.height - Self.titleBand {
            restartTimer()  // the pointer rests on the buttons
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
