import AppKit
import UniformTypeIdentifiers

/// Makes Vids the app that opens videos.
///
/// macOS asks the user to confirm every change of default app, so this runs
/// inside the normal app (never unattended) and asks only for the formats
/// that still open elsewhere, one at a time: each request waits for the
/// answer before the next. Vids never asks for the generic movie type, so
/// formats it can't play (MKV, WebM) keep opening in the app they use now.
@MainActor
enum DefaultPlayer {
    /// Formats people download, most common first.
    static let commonTypes: [String] = [
        "public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video", "public.avi",
        "public.mpeg-2-transport-stream", "public.mpeg", "public.3gpp",
    ]

    private static let askedKey = "AskedToBecomeDefault"

    static func isDefault(for identifier: String) -> Bool {
        guard let type = UTType(identifier),
              let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static var missingTypes: [String] {
        commonTypes.filter { !isDefault(for: $0) }
    }

    /// On first launch, offers once to become the default player.
    static func offerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey), !missingTypes.isEmpty else { return }
        defaults.set(true, forKey: askedKey)
        let alert = NSAlert()
        alert.messageText = "Play your videos with Vids?"
        alert.informativeText = "Vids can become the default app for MP4, MOV and other video files. macOS will ask you to confirm each format."
        alert.addButton(withTitle: "Use Vids")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await makeDefault(quitWhenDone: false) }
        }
    }

    /// Asks macOS to make Vids the default for videos, waiting for each
    /// confirmation. With `quitWhenDone` (the install script), Vids quits
    /// afterwards.
    static func makeDefault(quitWhenDone: Bool) async {
        UserDefaults.standard.set(true, forKey: askedKey)
        NSApp.activate()
        let app = Bundle.main.bundleURL
        for identifier in missingTypes {
            await request(app: app, identifier: identifier, until: { isDefault(for: identifier) })
        }
        let done = commonTypes.count - missingTypes.count
        let alert = NSAlert()
        alert.messageText = missingTypes.isEmpty ? "Vids now plays your videos." : "Vids opens \(done) of \(commonTypes.count) common video types."
        alert.informativeText = missingTypes.isEmpty ? "" : "You can change any of the others in Finder: Get Info › Open with › Change All."
        alert.runModal()
        if quitWhenDone { NSApp.terminate(nil) }
    }

    /// Sends one change request and waits (up to two minutes) for the user to
    /// answer the system confirmation.
    private static func request(app: URL, identifier: String, until applied: @escaping () -> Bool) async {
        guard let type = UTType(identifier) else { return }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
        } catch {
            return
        }
        let deadline = Date().addingTimeInterval(120)
        while !applied() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}
