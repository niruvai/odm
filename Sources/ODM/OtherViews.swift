import SwiftUI
import AppKit

// MARK: - Add download sheet

struct AddDownloadView: View {
    @EnvironmentObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ui = UIState.shared

    private var lines: [String] {
        ui.addLinks.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add Download", systemImage: "arrow.down.circle.fill")
                .font(.title2.weight(.semibold))

            Text("Paste one or more links — one per line.")
                .foregroundStyle(.secondary)

            TextEditor(text: $ui.addLinks)
                .font(.system(.body, design: .monospaced))
                .frame(height: 96)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Download as", selection: $ui.addKind) {
                Text("Auto").tag("auto")
                Text("File").tag("file")
                Text("Video page (yt-dlp)").tag("video")
            }
            .pickerStyle(.segmented)
            .help("Auto sends YouTube, Facebook, Vimeo… pages to yt-dlp and everything else to the file downloader.")

            if ui.addKind != "file" {
                Picker("Video quality", selection: $ui.addQuality) {
                    ForEach(VideoQuality.options) { q in
                        Text(q.label).tag(q.id)
                    }
                }
            }

            if ui.addKind != "video" {
                TextField("Save as (optional — for a single file link)", text: $ui.addFileName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(lines.count > 1)
            }

            Toggle("Start downloading right away", isOn: $ui.addStartNow)

            if let e = ui.addError {
                Text(e).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Text("Saving to \(Prefs.downloadFolder)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(ui.addStartNow ? "Download" : "Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(lines.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            ui.addLinks = ""
            ui.addFileName = ""
            ui.addError = nil
            ui.addKind = "auto"
            ui.addQuality = Prefs.videoQuality
            if let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               clip.lowercased().hasPrefix("http") {
                ui.addLinks = clip
            }
        }
    }

    private func submit() {
        let single = lines.count == 1
        var added = 0
        for line in lines {
            let kind: DownloadKind? = ui.addKind == "file" ? .file : (ui.addKind == "video" ? .video : nil)
            if manager.add(urlString: line, fileName: single ? ui.addFileName : nil, startNow: ui.addStartNow,
                           kind: kind, quality: ui.addQuality) != nil {
                added += 1
            }
        }
        if added == 0 {
            ui.addError = "No valid http:// or https:// link found."
        } else {
            dismiss()
        }
    }
}

// MARK: - Detail panel under the table

struct DetailPanel: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: FileIcon.icon(for: item.fileName))
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                actionButtons
            }

            SegmentBar(segments: item.segments, total: item.totalBytes, completed: item.status == .completed)
                .frame(height: 14)

            HStack(alignment: .top, spacing: 22) {
                info("Downloaded", "\(Fmt.bytes(item.downloadedBytes)) of \(Fmt.bytes(item.totalBytes))")
                info("Speed", item.status == .downloading ? (Fmt.speed(item.speed).isEmpty ? "—" : Fmt.speed(item.speed)) : "—")
                info("Time left", item.status == .downloading ? (Fmt.eta(item.eta).isEmpty ? "—" : Fmt.eta(item.eta)) : "—")
                info("Connections", item.status == .downloading ? "\(item.connections)" : "—")
                if item.kind == .video {
                    info("Source", "yt-dlp · \(VideoQuality.label(for: item.videoQuality))")
                } else {
                    info("Resume", item.totalBytes < 0 && item.status != .completed ? "—" : (item.resumable ? "Supported" : "Not supported"))
                }
                info("Folder", (item.directory as NSString).abbreviatingWithTildeInPath)
            }

            if item.status == .failed, let e = item.errorMessage {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
                if item.kind == .video, needsCookies(e) {
                    HStack(spacing: 10) {
                        Button {
                            UserDefaults.standard.set(true, forKey: Prefs.browserCookiesKey)
                            manager.resume(item)
                        } label: {
                            Label(Prefs.useBrowserCookies ? "Retry with my browser sign-in" : "Use my browser sign-in and retry",
                                  systemImage: "person.badge.key")
                        }
                        .controlSize(.small)
                        Text("Uses your sign-in from the ODM Chrome extension.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.bar)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            switch item.status {
            case .downloading, .connecting, .queued:
                Button { manager.pause(item) } label: { Label("Pause", systemImage: "pause.fill") }
            case .paused, .failed:
                Button { manager.resume(item) } label: { Label("Resume", systemImage: "play.fill") }
            case .completed:
                Button { manager.open(item) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
            }
            Button { manager.reveal(item) } label: { Label("Show in Finder", systemImage: "folder") }
        }
        .controlSize(.small)
    }

    /// yt-dlp errors that a signed-in browser session usually fixes.
    private func needsCookies(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("not a bot") || m.contains("sign in") || m.contains("cookies")
            || m.contains("403") || m.contains("confirm your age") || m.contains("age-restricted")
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// IDM-style bar: one block per connection range, filled as it downloads.
struct SegmentBar: View {
    let segments: [Segment]
    let total: Int64
    let completed: Bool

    var body: some View {
        Canvas { ctx, size in
            let full = CGRect(origin: .zero, size: size)
            ctx.fill(Path(full), with: .color(Color.secondary.opacity(0.18)))
            if completed {
                ctx.fill(Path(full), with: .color(.green.opacity(0.8)))
                return
            }
            guard total > 0 else { return }
            let scale = size.width / CGFloat(total)
            for s in segments {
                let x = CGFloat(s.start) * scale
                let w = CGFloat(s.downloaded) * scale
                ctx.fill(Path(CGRect(x: x, y: 0, width: max(0, w), height: size.height)),
                         with: .color(.accentColor))
            }
            // Thin markers where each connection's range starts
            for s in segments where s.start > 0 {
                let x = CGFloat(s.start) * scale
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                         with: .color(Color.primary.opacity(0.35)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var manager: DownloadManager
    @AppStorage(Prefs.connectionsKey) private var connections = 8
    @AppStorage(Prefs.concurrentKey) private var maxConcurrent = 3
    @AppStorage(Prefs.folderKey) private var folder = Prefs.defaultFolder
    @AppStorage(Prefs.categorizeKey) private var categorize = true
    @AppStorage(Prefs.notifyKey) private var notify = true

    var body: some View {
        TabView {
            Form {
                Stepper("Connections per download: \(connections)", value: $connections, in: 1...32)
                Text("More connections = faster on most servers. 8–16 is a good range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Downloads at the same time: \(maxConcurrent)", value: $maxConcurrent, in: 1...10)

                LabeledContent("Download folder") {
                    HStack {
                        Text((folder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                }
                Toggle("Sort into folders by type (Video, Music, Programs…)", isOn: $categorize)
                Toggle("Notify and play a sound when a download finishes", isOn: $notify)
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            VideoSettingsView()
                .tabItem { Label("Video", systemImage: "film") }

            VStack(alignment: .leading, spacing: 12) {
                Label("Chrome / Edge / Brave extension", systemImage: "puzzlepiece.extension")
                    .font(.headline)
                Text("""
                1. Click the button below to show the extension folder.
                2. In Chrome open chrome://extensions and turn on Developer mode.
                3. Click “Load unpacked” and choose the ChromeExtension folder.
                Now every download in Chrome goes to ODM while the app is running.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                Button("Show Extension Folder") { manager.revealChromeExtension() }
                Text("Bridge listening on 127.0.0.1:\(String(LocalServer.port))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .tabItem { Label("Browser", systemImage: "globe") }
        }
        .frame(width: 560, height: 400)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }
}

// MARK: - Video settings (yt-dlp / ffmpeg)

struct VideoSettingsView: View {
    @ObservedObject private var ytdlp = YtDlp.shared
    @AppStorage(Prefs.videoQualityKey) private var quality = "1080"
    @AppStorage(Prefs.browserCookiesKey) private var useCookies = false

    var body: some View {
        Form {
            Picker("Default video quality", selection: $quality) {
                ForEach(VideoQuality.options) { q in
                    Text(q.label).tag(q.id)
                }
            }

            LabeledContent("yt-dlp") {
                HStack {
                    if let v = ytdlp.version {
                        Label("Installed (\(v))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Added automatically on first video")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(ytdlp.version == nil ? "Install Tools" : "Update") { ytdlp.install() }
                        .disabled(ytdlp.isInstalling)
                }
            }
            toolRow("Deno", path: ytdlp.denoPath, missing: "Needed for YouTube — added automatically")
            toolRow("ffmpeg", path: ytdlp.ffmpegPath, missing: "Needed for HD — added automatically")

            if let s = ytdlp.status {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(s).font(.caption)
                }
            }
            if let e = ytdlp.lastError {
                Text(e).font(.caption).foregroundStyle(.red)
            }

            Toggle("Use my browser sign-in (fixes “confirm you're not a bot” and HTTP 403)", isOn: $useCookies)
            Text("Uses the cookies the ODM Chrome extension sends when you press its Download button. If there are none yet, yt-dlp reads Chrome directly and macOS asks once — choose “Always Allow”.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Only download videos you have the right to save — your own uploads, Creative Commons videos, or with the owner's permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .onAppear { ytdlp.refreshVersion() }
        .id(ytdlp.toolsChanged)
    }

    private func toolRow(_ name: String, path: String?, missing: String) -> some View {
        LabeledContent(name) {
            if let path = path {
                Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(missing).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var manager: DownloadManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let running = manager.items.filter { $0.status.isActive }
        if running.isEmpty {
            Text("No active downloads")
        } else {
            ForEach(Array(running.prefix(8))) { item in
                MenuRow(item: item)
            }
        }
        Divider()
        Button("Open ODM") { showMain() }
        Button("Add Download…") {
            showMain()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .showAddDownload, object: nil)
            }
        }
        Divider()
        Button("Resume All") { manager.resumeAll() }
        Button("Pause All") { manager.pauseAll() }
        Divider()
        Button("Quit ODM") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMain() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct MenuRow: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        let pct = item.totalBytes > 0 ? "\(Int(item.progress * 100))%" : Fmt.bytes(item.downloadedBytes)
        let speed = Fmt.speed(item.speed)
        Text("\(pct)  \(item.fileName)\(speed.isEmpty ? "" : "  ·  " + speed)")
    }
}
