import SwiftUI
import AppKit

// MARK: - Is the browser extension talking to ODM?

/// Remembers when the ODM browser extension last contacted the app, so the setup guide and
/// Settings can show "Chrome extension connected". Used only on the main thread.
final class ExtensionStatus: ObservableObject {
    static let shared = ExtensionStatus()

    @Published private(set) var lastSeen: Date?
    @Published private(set) var version: String?

    private static let everKey = "extensionEverConnected"

    var everConnected: Bool { UserDefaults.standard.bool(forKey: Self.everKey) }

    func seen(version: String?) {
        lastSeen = Date()
        if let v = version, !v.isEmpty { self.version = v }
        UserDefaults.standard.set(true, forKey: Self.everKey)
    }
}

// MARK: - Guide state (an object instead of @State, so ODM builds without Xcode)

final class ChromeGuideState: ObservableObject {
    static let shared = ChromeGuideState()
    @Published var copied: String?

    func copy(_ text: String, tag: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = tag
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.copied == tag { self?.copied = nil }
        }
    }
}

enum ChromeHelper {
    static let extensionsPage = "chrome://extensions"
    static let bundleIDs = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]

    static var browserURL: URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return nil
    }

    static var browserName: String {
        guard let url = browserURL else { return "Chrome" }
        return url.deletingPathExtension().lastPathComponent
    }

    static var folderPath: String {
        FileUtil.appSupportDir.appendingPathComponent("ChromeExtension").path
    }

    static var folderDisplayPath: String {
        (folderPath as NSString).abbreviatingWithTildeInPath
    }

    /// Opens chrome://extensions in the user's Chrome (Edge/Brave open it the same way).
    /// Also copies the address, in case the browser refuses to open it from another app.
    static func openExtensionsPage() {
        ChromeGuideState.shared.copy(extensionsPage, tag: "page")
        guard let app = browserURL, let url = URL(string: extensionsPage) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - The guide shown after the first-run setup

struct ChromeGuideView: View {
    @ObservedObject private var status = ExtensionStatus.shared
    @ObservedObject private var guide = ChromeGuideState.shared
    @EnvironmentObject var manager: DownloadManager
    let finish: () -> Void

    private var connected: Bool { status.lastSeen != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 0) {
                    stepRow(1, "Open the extensions page",
                            "ODM opens it in \(ChromeHelper.browserName) for you. The address is also copied — paste it into the address bar if the page doesn't open.") {
                        HStack(spacing: 8) {
                            Button("Open Extensions Page") { ChromeHelper.openExtensionsPage() }
                                .disabled(ChromeHelper.browserURL == nil)
                            copyButton(ChromeHelper.extensionsPage, tag: "page")
                        }
                    }
                    Divider().padding(.leading, 64)
                    stepRow(2, "Turn on “Developer mode”",
                            "It's the switch in the top-right corner of the extensions page.") {
                        EmptyView()
                    }
                    Divider().padding(.leading, 64)
                    stepRow(3, "Add the ODM extension",
                            "Click “Load unpacked” and choose the ODM extension folder. In the folder window, press ⌘⇧G and paste the path. Or simply drag the folder from Finder onto the extensions page.") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ChromeHelper.folderDisplayPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
                            HStack(spacing: 8) {
                                Button("Show Folder in Finder") { manager.revealChromeExtension() }
                                copyButton(ChromeHelper.folderPath, tag: "path")
                            }
                        }
                    }
                    Divider().padding(.leading, 64)
                    connectionRow
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
                .frame(maxWidth: 640)

                footer
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.accentColor)
            Text("Connect ODM to Chrome")
                .font(.largeTitle.weight(.semibold))
            Text("With the extension, Chrome downloads go to ODM automatically and video pages get an ODM download button. It takes about a minute.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
    }

    private func stepRow<Actions: View>(_ n: Int, _ title: String, _ detail: String,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(n)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var connectionRow: some View {
        HStack(spacing: 16) {
            Group {
                if connected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.system(size: 26))
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(connected ? "Chrome extension connected" : "Waiting for the extension…")
                    .font(.headline)
                    .foregroundStyle(connected ? Color.green : Color.primary)
                Text(connected
                     ? "Everything is ready\(status.version.map { " (extension \($0))" } ?? "")."
                     : "This turns green as soon as the extension is added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !connected {
                Button("Skip for Now") { finish() }
                    .help("You can open this guide again from Settings → Browser.")
            }
            Button(connected ? "Start Using ODM" : "Done") { finish() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private func copyButton(_ text: String, tag: String) -> some View {
        Button {
            guide.copy(text, tag: tag)
        } label: {
            Label(guide.copied == tag ? "Copied" : "Copy", systemImage: guide.copied == tag ? "checkmark" : "doc.on.doc")
        }
    }
}
