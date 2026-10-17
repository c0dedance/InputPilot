import AppKit
import SwiftUI

@main
struct InputPilotApp: App {
    @NSApplicationDelegateAdaptor(PilotAppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    private static let menuIcon: NSImage = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            fatalError("Missing required MenuBarIcon.pdf in application resources")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            PilotMenu()
        } label: {
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
        Window("自动切换输入法设置", id: "settings") {
            RulesView(model: model)
                .onAppear {
                    appDelegate.openSettings = {
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(width: 500, height: 640)
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class PilotAppDelegate: NSObject, NSApplicationDelegate {
    var openSettings: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let openSettings else { return true }
        openSettings()
        return false
    }
}

private struct PilotMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示主界面") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",")
        Divider()
        Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
