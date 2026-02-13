import SwiftUI

@main
struct AgentAlertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        MenuBarExtra("AgentAlert", systemImage: "bell.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .frame(width: 500, height: 400)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        URLSchemeHandler.shared.registerHandler()
        NotificationOverlayManager.shared.setup()
    }
}
