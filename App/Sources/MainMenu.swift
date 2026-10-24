import AppKit

/// The menu bar, built in code (no nib to load at launch).
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "Vids")
        app.addItem(item("About Vids", #selector(AppDelegate.showAbout(_:))))
        app.addItem(.separator())
        app.addItem(item("Hide Vids", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Vids", #selector(NSApplication.terminate(_:)), "q"))

        let file = submenu(in: main, title: "File")
        file.addItem(item("Open…", #selector(AppDelegate.showOpenPanel(_:)), "o"))
        file.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        file.addItem(.separator())
        file.addItem(item("Show in Finder", #selector(PlayerWindowController.showInFinder(_:)), "r", [.command, .shift]))

        // For text fields in the Open panel.
        let edit = submenu(in: main, title: "Edit")
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        let playback = submenu(in: main, title: "Playback")
        playback.addItem(item("Play", #selector(PlayerWindowController.togglePlayback(_:)), " ", []))
        playback.addItem(.separator())
        playback.addItem(item("Skip Forward 5 Seconds", #selector(PlayerWindowController.skipForward(_:)), arrow(NSRightArrowFunctionKey), []))
        playback.addItem(item("Skip Back 5 Seconds", #selector(PlayerWindowController.skipBackward(_:)), arrow(NSLeftArrowFunctionKey), []))
        playback.addItem(.separator())
        playback.addItem(item("Volume Up", #selector(PlayerWindowController.volumeUp(_:)), arrow(NSUpArrowFunctionKey), []))
        playback.addItem(item("Volume Down", #selector(PlayerWindowController.volumeDown(_:)), arrow(NSDownArrowFunctionKey), []))
        playback.addItem(item("Mute", #selector(PlayerWindowController.toggleMute(_:)), "m", []))
        playback.addItem(.separator())
        playback.addItem(trackMenu("Audio", subtitles: false))
        playback.addItem(trackMenu("Subtitles", subtitles: true))

        let view = submenu(in: main, title: "View")
        view.addItem(item("Half Size", #selector(PlayerWindowController.halfSize(_:)), "0"))
        view.addItem(item("Actual Size", #selector(PlayerWindowController.actualSize(_:)), "1"))
        view.addItem(item("Double Size", #selector(PlayerWindowController.doubleSize(_:)), "2"))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let window = submenu(in: main, title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window

        return main
    }

    private static func trackMenu(_ title: String, subtitles: Bool) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.delegate = TrackMenuFiller.shared
        menu.identifier = NSUserInterfaceItemIdentifier(subtitles ? "subtitles" : "audio")
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }
}

/// Lists the front video's tracks when the Audio or Subtitles menu opens.
@MainActor
final class TrackMenuFiller: NSObject, NSMenuDelegate {
    static let shared = TrackMenuFiller()

    func menuNeedsUpdate(_ menu: NSMenu) {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        guard let controller = window?.windowController as? PlayerWindowController else {
            menu.removeAllItems()
            menu.addItem(NSMenuItem(title: "None", action: nil, keyEquivalent: ""))
            return
        }
        controller.fillTrackMenu(menu, subtitles: menu.identifier?.rawValue == "subtitles")
    }
}
