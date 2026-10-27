import Foundation
import AppKit
import SwiftUI

/// Keeps ODM up to date from GitHub Releases.
///
/// Every push to the main branch builds a new ODM.app on GitHub Actions and publishes it as a
/// release tagged "build-<number>". ODM checks the latest release on launch and every few hours;
/// when its build number is higher than ours it offers the update. Installing downloads the zip,
/// swaps the app in place and relaunches. Unfinished downloads continue after the restart.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release {
        let build: Int
        let title: String
        let notes: String
        let zipURL: URL
        let pageURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var state: State = .idle
    @Published var dismissedBuild = UserDefaults.standard.integer(forKey: "updateDismissedBuild")
    @Published var showNotes = false      // "What's New" popover (no @State: builds without Xcode)

    private let latestURL = URL(string: "https://api.github.com/repos/niruvai/odm/releases/latest")!
    private var timer: Timer?
    private var progressObservation: NSKeyValueObservation?

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    /// Show the banner unless the user said "Later" for this exact build.
    var showBanner: Bool {
        guard let a = available else { return false }
        return a.build != dismissedBuild
    }

    // MARK: Checking

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) {
        if case .downloading = state { return }
        if state == .installing { return }
        state = .checking

        var req = URLRequest(url: latestURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ODM/\(currentBuild)", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let release = data.flatMap { Updater.parse($0) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let r = release, r.build > self.currentBuild {
                    self.available = r
                    self.state = .idle
                    if userInitiated { self.dismissedBuild = 0 }
                } else if release != nil || (response as? HTTPURLResponse)?.statusCode == 404 {
                    self.available = nil
                    self.state = userInitiated ? .upToDate : .idle
                } else {
                    let msg = error?.localizedDescription ?? "Could not reach GitHub."
                    self.state = userInitiated ? .failed(msg) : .idle
                }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let build = Int(tag.replacingOccurrences(of: "build-", with: "")),
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String) == "ODM.zip" }),
              let urlString = zip["browser_download_url"] as? String,
              let url = URL(string: urlString) else { return nil }
        let title = json["name"] as? String ?? "ODM build \(build)"
        let notes = (json["body"] as? String ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("Co-Authored-By") && !$0.hasPrefix("Claude-Session") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        return Release(build: build, title: title, notes: notes, zipURL: url, pageURL: page)
    }

    func later() {
        guard let a = available else { return }
        dismissedBuild = a.build
        UserDefaults.standard.set(a.build, forKey: "updateDismissedBuild")
    }

    // MARK: Installing

    func install() {
        guard let release = available else { return }
        state = .downloading(0)

        let task = URLSession.shared.downloadTask(with: release.zipURL) { [weak self] tmp, response, error in
            guard let self = self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let tmp = tmp, code == 200 else {
                self.fail(error?.localizedDescription ?? "Download failed (HTTP \(code)).")
                return
            }
            do {
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("odm-update-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("ODM.zip")
                try FileManager.default.moveItem(at: tmp, to: zip)
                DispatchQueue.main.async { self.state = .installing }
                try self.unzip(zip, into: work)
                let newApp = work.appendingPathComponent("ODM.app")
                guard let bundle = Bundle(url: newApp),
                      bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw DMError.message("The downloaded update is not a valid ODM app.")
                }
                DispatchQueue.main.async { self.relaunch(into: newApp) }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                if case .downloading = self?.state { self?.state = .downloading(p.fractionCompleted) }
            }
        }
        task.resume()
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { self.state = .failed(message) }
    }

    private func unzip(_ zip: URL, into dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DMError.message("Could not unpack the update.") }
    }

    /// Replaces this app with `newApp` after ODM quits, then opens it again.
    private func relaunch(into newApp: URL) {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .failed("ODM can't write to \(parent.path). Move ODM to Applications and try again.")
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target.path)"
        /usr/bin/ditto --norsrc --noextattr "\(newApp.path)" "\(target.path)"
        /usr/bin/xattr -cr "\(target.path)" 2>/dev/null
        /usr/bin/open "\(target.path)"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        do {
            try p.run()
        } catch {
            state = .failed("Could not start the installer: \(error.localizedDescription)")
            return
        }
        DownloadManager.shared.save()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Banner shown at the top of the main window

struct UpdateBanner: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        if updater.showBanner, let release = updater.available {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A new version of ODM is ready")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle(release))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
                if !release.notes.isEmpty {
                    Button("What's New") { updater.showNotes.toggle() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white)
                        .popover(isPresented: $updater.showNotes) {
                            ScrollView {
                                Text(release.notes)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .frame(width: 380, height: 220)
                        }
                }
                actionArea
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch updater.state {
        case .downloading(let p):
            ProgressView(value: p)
                .frame(width: 120)
                .tint(.white)
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.white)
            }
        case .failed(let msg):
            HStack(spacing: 8) {
                Text(msg).font(.caption).foregroundStyle(.white).lineLimit(2)
                Button("Retry") { updater.install() }
            }
        default:
            HStack(spacing: 8) {
                Button("Later") { updater.later() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.9))
                Button("Update Now") { updater.install() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func subtitle(_ r: Release) -> String {
        let first = r.notes.components(separatedBy: "\n").first ?? ""
        return first.isEmpty ? "Build \(r.build) — ODM restarts and your downloads continue."
                             : "\(first) — ODM restarts and your downloads continue."
    }

    typealias Release = Updater.Release
}

/// Settings → About: version and a manual check.
struct UpdateStatusView: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        HStack(spacing: 10) {
            switch updater.state {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking for updates…").font(.caption)
            case .upToDate:
                Label("ODM is up to date", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .failed(let msg):
                Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
            case .downloading(let p):
                ProgressView(value: p).frame(width: 120)
            case .installing:
                Text("Installing…").font(.caption)
            case .idle:
                if let a = updater.available {
                    Text("Build \(a.build) is available").font(.caption)
                }
            }
            if updater.available != nil, updater.state == .idle || isFailed {
                Button("Update Now") { updater.install() }
            } else {
                Button("Check for Updates") { updater.check(userInitiated: true) }
                    .disabled(updater.state == .checking)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = updater.state { return true }
        return false
    }
}
