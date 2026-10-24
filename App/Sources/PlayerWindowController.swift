import AppKit
import AVFoundation
import AVKit

/// One window playing one video.
@MainActor
final class PlayerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static let skipSeconds: Double = 5
    static let volumeStep: Float = 0.1
    private static let volumeKey = "Volume"

    var onClose: ((PlayerWindowController) -> Void)?
    /// Called when a video can't be played; the window is not shown.
    var onFailure: ((PlayerWindowController, URL, Error) -> Void)?
    /// Called each time a video starts playing (used by the tests).
    var onReady: ((PlayerWindowController) -> Void)?

    let player = AVPlayer()
    private let playerView = PlayerView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    private var chrome: WindowChrome!
    /// The video asked for last; the one playing once it loads.
    private(set) var requestedURL: URL?
    private(set) var playingURL: URL?
    /// Size of the picture at 100 %, in points.
    private(set) var videoSize = CGSize(width: 640, height: 360)
    private var audioTracks: AVMediaSelectionGroup?
    private var subtitles: AVMediaSelectionGroup?
    private var statusObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private weak var cascadeSource: NSWindow?

    init(cascadeFrom other: NSWindow?) {
        let window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        let content = DropView(frame: playerView.frame)
        playerView.autoresizingMask = [.width, .height]
        content.addSubview(playerView)
        window.contentView = content
        window.initialFirstResponder = playerView
        super.init(window: window)
        window.delegate = self
        content.onDrop = { [weak self] url in self?.open(url) }
        chrome = WindowChrome(window: window)
        chrome.isPlaying = { [weak self] in self?.player.timeControlStatus == .playing }
        chrome.showControls = { [weak self] show in self?.playerView.showControls(show) }
        cascadeSource = other
        let defaults = UserDefaults.standard
        player.volume = defaults.object(forKey: Self.volumeKey) == nil ? 1 : defaults.float(forKey: Self.volumeKey)
        playerView.player = player
        playbackObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.chrome.playbackChanged() } }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Opening

    /// Plays `url` in this window. If it can't be played, the video already
    /// in the window keeps playing.
    func open(_ url: URL) {
        requestedURL = url
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let asset = AVURLAsset(url: url)
            do {
                let info = try await VideoInfo.load(asset)
                guard let self, !Task.isCancelled else { return }
                self.present(asset, info: info, url: url)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.fail(url, error)
            }
        }
    }

    private func present(_ asset: AVURLAsset, info: VideoInfo, url: URL) {
        guard let window else { return }
        let firstVideo = playingURL == nil
        playingURL = url
        videoSize = info.displaySize ?? CGSize(width: 640, height: 360)
        audioTracks = info.audioTracks
        subtitles = info.subtitles

        let item = AVPlayerItem(asset: asset)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error ?? PlaybackError.unsupportedFormat
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fail(url, error) } }
        }
        player.replaceCurrentItem(with: item)

        window.title = url.lastPathComponent
        window.representedURL = url
        window.contentAspectRatio = videoSize
        window.contentMinSize = WindowSizing.minimum(for: videoSize)
        if firstVideo {
            // Videos opened together load in any order: when the window this one
            // was meant to follow is not on screen yet, follow the front video.
            let source = cascadeSource.flatMap { $0.isVisible ? $0 : nil }
                ?? NSApp.orderedWindows.first { $0 !== window && $0 is PlayerWindow && $0.isVisible }
            let visible = (source?.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let size = WindowSizing.fit(videoSize, in: CGSize(width: visible.width * 0.9, height: visible.height * 0.9))
            window.setContentSize(size)
            if let source {
                window.setFrameTopLeftPoint(NSPoint(x: source.frame.minX + 24, y: source.frame.maxY - 24))
                window.setFrame(window.constrainFrameRect(window.frame, to: source.screen), display: false)
            } else {
                window.center()
            }
            showWindow(nil)
        } else if !window.styleMask.contains(.fullScreen) {
            // A video dropped on the window: keep its width, take the new shape.
            resize(to: CGSize(width: window.frame.width, height: window.frame.width * videoSize.height / videoSize.width))
        }
        window.makeFirstResponder(playerView)
        chrome.show()
        player.play()
        onReady?(self)
    }

    private func fail(_ url: URL, _ error: Error) {
        if let playingURL, playingURL != url, let window {
            // A dropped file that can't play: say so and keep the current video.
            requestedURL = playingURL
            let message = PlaybackError.message(for: url, error: error)
            let alert = NSAlert()
            alert.messageText = message.title
            alert.informativeText = message.detail
            alert.beginSheetModal(for: window)
            return
        }
        player.pause()
        onFailure?(self, url, error)
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        statusObservation = nil
        playbackObservation = nil
        chrome.stop()
        UserDefaults.standard.set(player.volume, forKey: Self.volumeKey)
        player.pause()
        player.replaceCurrentItem(with: nil)
        onClose?(self)
    }

    func windowWillEnterFullScreen(_ notification: Notification) { chrome.suspend() }
    func windowDidExitFullScreen(_ notification: Notification) { chrome.resume() }

    /// Zoom (the green button with ⌥, or a double-click on the title bar):
    /// the largest size that fits the screen with the video's shape.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let size = WindowSizing.fit(videoSize, scale: 100, in: newFrame.size)
        return WindowSizing.centered(size, on: newFrame)
    }

    /// Resizes the window around its center, kept on screen.
    private func resize(to size: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let fitted = WindowSizing.fit(size, in: screen.visibleFrame.size)
        let frame = WindowSizing.centered(fitted, on: window.frame)
        window.setFrame(window.constrainFrameRect(frame, to: screen), display: true, animate: true)
    }

    // MARK: Actions

    @objc func togglePlayback(_ sender: Any?) {
        if player.timeControlStatus == .paused {
            if let item = player.currentItem, item.duration.isNumeric,
               item.currentTime().seconds >= item.duration.seconds - 0.1 {
                player.seek(to: .zero)  // at the end: play again from the start
            }
            player.play()
        } else {
            player.pause()
        }
    }

    @objc func skipForward(_ sender: Any?) { skip(by: Self.skipSeconds) }
    @objc func skipBackward(_ sender: Any?) { skip(by: -Self.skipSeconds) }

    private func skip(by seconds: Double) {
        guard let item = player.currentItem else { return }
        var target = item.currentTime().seconds + seconds
        if item.duration.isNumeric { target = min(target, item.duration.seconds) }
        player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @objc func volumeUp(_ sender: Any?) { setVolume(player.volume + Self.volumeStep) }
    @objc func volumeDown(_ sender: Any?) { setVolume(player.volume - Self.volumeStep) }

    private func setVolume(_ volume: Float) {
        player.isMuted = false
        player.volume = (min(1, max(0, volume)) * 10).rounded() / 10
        UserDefaults.standard.set(player.volume, forKey: Self.volumeKey)
    }

    @objc func toggleMute(_ sender: Any?) { player.isMuted.toggle() }

    @objc func halfSize(_ sender: Any?) { resize(to: WindowSizing.fit(videoSize, scale: 0.5, in: .init(width: 1e5, height: 1e5))) }
    @objc func actualSize(_ sender: Any?) { resize(to: videoSize) }
    @objc func doubleSize(_ sender: Any?) { resize(to: WindowSizing.fit(videoSize, scale: 2, in: .init(width: 1e5, height: 1e5))) }

    @objc func showInFinder(_ sender: Any?) {
        guard let playingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([playingURL])
    }

    // MARK: Audio and subtitle tracks

    /// Fills the Audio or Subtitles menu with this video's tracks.
    func fillTrackMenu(_ menu: NSMenu, subtitles wantsSubtitles: Bool) {
        menu.removeAllItems()
        guard let group = wantsSubtitles ? subtitles : audioTracks, let item = player.currentItem else {
            menu.addItem(NSMenuItem(title: "None", action: nil, keyEquivalent: ""))
            return
        }
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        if wantsSubtitles {
            let off = NSMenuItem(title: "Off", action: #selector(selectTrack(_:)), keyEquivalent: "")
            off.target = self
            off.representedObject = TrackChoice(group: group, option: nil)
            off.state = selected == nil || selected?.hasMediaCharacteristic(.containsOnlyForcedSubtitles) == true ? .on : .off
            menu.addItem(off)
        }
        let options = group.options.filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
        for (index, option) in options.enumerated() {
            let repeated = options.filter { $0.displayName == option.displayName }.count > 1
            let title = repeated ? "\(option.displayName) (\(index + 1))" : option.displayName
            let entry = NSMenuItem(title: title, action: #selector(selectTrack(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = TrackChoice(group: group, option: option)
            entry.state = option == selected ? .on : .off
            menu.addItem(entry)
        }
    }

    @objc private func selectTrack(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? TrackChoice else { return }
        player.currentItem?.select(choice.option, in: choice.group)
    }

    // MARK: Menus

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasVideo = player.currentItem != nil
        switch menuItem.action {
        case #selector(togglePlayback(_:)):
            menuItem.title = player.timeControlStatus == .paused ? "Play" : "Pause"
            return hasVideo
        case #selector(toggleMute(_:)):
            menuItem.state = player.isMuted ? .on : .off
            return hasVideo
        case #selector(halfSize(_:)), #selector(actualSize(_:)), #selector(doubleSize(_:)):
            return hasVideo && window?.styleMask.contains(.fullScreen) == false
        default:
            return hasVideo
        }
    }
}

private final class TrackChoice: NSObject {
    let group: AVMediaSelectionGroup
    let option: AVMediaSelectionOption?
    init(group: AVMediaSelectionGroup, option: AVMediaSelectionOption?) {
        self.group = group
        self.option = option
    }
}

/// The window's content: black behind the video, and a target for dropped videos.
final class DropView: NSView {
    var onDrop: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func video(in info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: VideoTypes.declared.map(\.identifier),
        ]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        video(in: sender) == nil ? [] : .generic
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = video(in: sender) else { return false }
        onDrop?(url)
        return true
    }
}
