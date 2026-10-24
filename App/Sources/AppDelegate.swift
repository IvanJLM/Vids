import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [PlayerWindowController] = []
    /// Launched by the install script to become the default video player.
    private let settingDefault = CommandLine.arguments.contains("--make-default")
    /// True while the app hosts the unit tests: no Open panel, no quitting.
    private let hostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            // Keep the menus to what Vids actually does.
            "NSDisabledDictationMenuItem": true,
            "NSDisabledCharacterPaletteMenuItem": true,
            "NSFullScreenMenuItemEverywhere": false,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if settingDefault {
            Task { await DefaultPlayer.makeDefault(quitWhenDone: true) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openVideo(url) }
    }

    /// Launched from the Dock or Spotlight without a file: ask for one.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !settingDefault && !hostingTests
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showOpenPanel(nil)
        return true
    }

    /// Vids runs only while a video is open, so it uses no memory otherwise.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !settingDefault && !hostingTests
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func openVideo(_ url: URL) {
        if let existing = controllers.first(where: { $0.requestedURL == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = PlayerWindowController(cascadeFrom: NSApp.keyWindow ?? controllers.last?.window)
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controller.onFailure = { [weak self] failed, url, error in
            self?.report(url, error, closing: failed)
        }
        controller.onReady = { [weak self] _ in
            guard let self, !self.settingDefault else { return }
            // Ask after the first video is on screen, never in front of it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { DefaultPlayer.offerOnFirstLaunch() }
        }
        controllers.append(controller)
        controller.open(url)
    }

    /// Explains why a video can't play and closes its window; quits if it
    /// was the only one.
    private func report(_ url: URL, _ error: Error, closing controller: PlayerWindowController) {
        let message = PlaybackError.message(for: url, error: error)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message.title
        alert.informativeText = message.detail
        NSApp.activate()
        alert.runModal()
        if controller.window?.isVisible == true {
            controller.close()
        } else {
            controllers.removeAll { $0 === controller }
        }
        if controllers.isEmpty && !hostingTests { NSApp.terminate(nil) }
    }

    @objc func showOpenPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoTypes.declared
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls { openVideo(url) }
        } else if controllers.isEmpty {
            NSApp.terminate(nil)
        }
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(
            string: "A minimal, native video player for Apple Silicon Macs.\nFree and open source under the MIT License.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(string: "github.com/IvanJLM/Vids", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://github.com/IvanJLM/Vids")!,
        ]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
