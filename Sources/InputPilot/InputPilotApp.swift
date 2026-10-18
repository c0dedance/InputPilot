import AppKit
import SwiftUI

@main
struct InputPilotApp: App {
    @NSApplicationDelegateAdaptor(PilotAppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            PilotMenu(appDelegate: appDelegate)
        } label: {
            PilotMenuLabel(model: appDelegate.model)
        }
    }
}

private struct PilotMenuLabel: View {
    @ObservedObject var model: AppModel
    private static let menuIcon: NSImage = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            fatalError("Missing required MenuBarIcon.pdf in application resources")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Label {
            Text(model.menuTitle)
        } icon: {
            if model.hasError {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(nsImage: Self.menuIcon)
            }
        }
    }
}

@MainActor
final class PilotAppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var settingsWindow: NSWindow?

    override convenience init() {
        self.init(model: AppModel())
    }

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "自动切换输入法设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: RulesView(model: model))
            window.center()
            settingsWindow = window
        }
        settingsWindow!.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem {
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
}

private struct PilotMenu: View {
    let appDelegate: PilotAppDelegate

    var body: some View {
        Button("显示主界面") {
            appDelegate.showSettings()
        }.keyboardShortcut(",")
        Divider()
        Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
