import SwiftUI
import AppKit
import UserNotifications

@main
struct ODMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("ODM", id: "main") {
            ContentView()
                .environmentObject(DownloadManager.shared)
                .frame(minWidth: 860, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ODM") { Author.showAboutPanel() }
                Button("Check for Updates…") { Updater.shared.check(userInitiated: true) }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Download…") {
                    NotificationCenter.default.post(name: .showAddDownload, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Downloads") {
                Button("Resume All") { DownloadManager.shared.resumeAll() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Pause All") { DownloadManager.shared.pauseAll() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Clear Completed") { DownloadManager.shared.clearCompleted() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(DownloadManager.shared)
        }

        MenuBarExtra("ODM", systemImage: "arrow.down.circle") {
            MenuBarView()
                .environmentObject(DownloadManager.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var server: LocalServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        _ = DownloadManager.shared

        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        // Browser extension bridge on 127.0.0.1:9614
        let server = LocalServer(
            onAdd: { request in DownloadManager.shared.addFromBrowser(request) },
            onVideo: { request in DownloadManager.shared.addVideoFromBrowser(request) },
            onPrefetch: { request in DownloadManager.shared.prefetchFromBrowser(request) }
        )
        server.start()
        self.server = server

        // Updates from GitHub Releases, and keep the unpacked Chrome extension in sync with this build
        Updater.shared.start()
        DownloadManager.shared.syncChromeExtension()

        // odm://add?url=…&filename=…  (for bookmarklets / other apps)
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let comps = URLComponents(string: s),
              let link = comps.queryItems?.first(where: { $0.name == "url" })?.value else { return }
        let name = comps.queryItems?.first(where: { $0.name == "filename" })?.value
        DownloadManager.shared.add(urlString: link, fileName: name)
    }

    // Keep running in the menu bar when the window is closed, like IDM in the tray.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        DownloadManager.shared.save()
    }

    // Show "Download complete" banners even while the app is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
