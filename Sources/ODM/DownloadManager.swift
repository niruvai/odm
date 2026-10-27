import Foundation
import AppKit
import UserNotifications

/// Owns the download list, the queue and the running engines. Used only on the main thread.
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []

    private var engines: [UUID: DownloadEngine] = [:]
    private var videoEngines: [UUID: VideoEngine] = [:]
    private var sleepActivity: NSObjectProtocol?
    private var lastSave = Date.distantPast
    private let storeURL = FileUtil.appSupportDir.appendingPathComponent("downloads.json")

    private init() {
        Prefs.registerDefaults()
        load()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        DispatchQueue.main.async { self.schedule() }
    }

    var activeCount: Int { items.filter { $0.status.isActive }.count }

    // MARK: Adding

    @discardableResult
    func add(urlString: String, fileName: String? = nil, headers: [String: String] = [:],
             startNow: Bool = true, kind: DownloadKind? = nil, quality: String? = nil) -> DownloadItem? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = URL(string: trimmed)
            ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        guard let url = parsed, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }

        // Video pages (YouTube, Facebook…) go to yt-dlp, everything else to the file engine.
        let resolvedKind = kind ?? (YtDlp.isVideoPage(url) ? .video : .file)
        let userName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let guess = url.lastPathComponent.isEmpty || url.lastPathComponent == "/"
            ? (url.host ?? "download") : url.lastPathComponent
        let name: String
        let category: FileCategory
        if resolvedKind == .video {
            name = "Video from \(url.host ?? "web")"
            category = .video
        } else {
            name = FileUtil.sanitize(userName.isEmpty ? guess : userName)
            category = FileCategory.from(fileName: name)
        }

        let record = DownloadRecord(
            id: UUID(), url: url.absoluteString, fileName: name, directory: directory(for: category),
            nameResolved: !userName.isEmpty || resolvedKind == .video, totalBytes: -1, segments: [],
            resumable: resolvedKind == .video,
            status: startNow ? .queued : .paused, category: category, headers: headers,
            dateAdded: Date(), dateCompleted: nil, errorMessage: nil,
            kind: resolvedKind, videoQuality: quality ?? Prefs.videoQuality)
        let item = DownloadItem(record: record)
        item.wantsWindow = startNow
        items.insert(item, at: 0)
        changed()
        if startNow { schedule() }
        return item
    }

    func addFromBrowser(_ r: AddRequest) {
        var headers: [String: String] = [:]
        if let c = r.cookies, !c.isEmpty { headers["Cookie"] = c }
        if let ref = r.referrer, !ref.isEmpty { headers["Referer"] = ref }
        if let ua = r.userAgent, !ua.isEmpty { headers["User-Agent"] = ua }
        let name = (r.filename as NSString?)?.lastPathComponent
        add(urlString: r.url, fileName: name, headers: headers, startNow: true)
    }

    func addVideoFromBrowser(_ r: VideoRequest) {
        if let cookies = r.cookies, !cookies.isEmpty {
            CookieStore.save(cookies, for: r.url)
        }
        // Same video already in the list and not finished: resume it instead of adding a duplicate.
        if let existing = items.first(where: { $0.kind == .video && $0.url == r.url && $0.status != .completed }) {
            if let q = r.quality { existing.videoQuality = q }
            if !existing.status.isActive { resume(existing) }
            return
        }
        add(urlString: r.url, startNow: true, kind: .video, quality: r.quality)
    }

    /// The user opened ODM's quality menu on a video page: start getting the video info now,
    /// so the download starts faster once they pick a quality.
    func prefetchFromBrowser(_ r: VideoRequest) {
        if let cookies = r.cookies, !cookies.isEmpty {
            CookieStore.save(cookies, for: r.url)
        }
        if items.contains(where: { $0.kind == .video && $0.url == r.url && $0.status.isActive }) { return }
        VideoPrefetcher.shared.prefetch(r.url)
    }

    private func directory(for category: FileCategory) -> String {
        let base = Prefs.downloadFolder
        return Prefs.categorize ? (base as NSString).appendingPathComponent(category.title) : base
    }

    // MARK: Queue

    /// Starts queued downloads (oldest first) while there are free slots.
    func schedule() {
        var slots = Prefs.maxConcurrent - activeCount
        guard slots > 0 else { return }
        for item in items.reversed() where item.status == .queued {
            if slots <= 0 { break }
            start(item)
            slots -= 1
        }
    }

    // MARK: Start / pause / resume

    func start(_ item: DownloadItem) {
        guard engines[item.id] == nil, videoEngines[item.id] == nil,
              item.status != .completed, !item.status.isActive else { return }
        if item.wantsWindow {
            item.wantsWindow = false
            ProgressWindows.shared.show(item)
        }
        if item.kind == .video {
            item.videoAttempt = 0
            item.skipPrefetch = false
            startVideo(item)
            return
        }
        guard let url = URL(string: item.url) else {
            item.status = .failed
            item.errorMessage = "Invalid link."
            changed()
            return
        }
        let token = UUID()
        item.runToken = token
        item.status = .connecting
        item.errorMessage = nil
        changed()

        Prober.probe(url: url, headers: item.headers) { [weak self] result in
            guard let self = self, item.runToken == token, item.status == .connecting else { return }
            switch result {
            case .success(let probe):
                self.launchEngine(for: item, probe: probe, token: token)
            case .failure(let error):
                item.status = .failed
                item.errorMessage = error.localizedDescription
                self.changed()
                self.schedule()
            }
        }
    }

    // MARK: Video (yt-dlp)

    private func startVideo(_ item: DownloadItem) {
        let token = UUID()
        item.runToken = token
        item.status = .connecting
        item.errorMessage = nil
        item.stage = "Preparing…"
        if item.videoAttempt == 0 && !item.skipPrefetch {
            item.videoStartedAt = Date()
            timing(item, "start  \(item.url)")
        } else {
            timing(item, "retry (attempt \(item.videoAttempt), prefetch \(item.skipPrefetch ? "off" : "on"))")
        }
        changed()

        // Attempt 0: normal. 1: after a 403, refresh yt-dlp. 2: also try other YouTube player clients.
        let attempt = item.videoAttempt
        YtDlp.shared.prepare(forceUpdate: attempt == 1) { [weak self, weak item] result in
            guard let item = item else { return }
            guard let self = self, item.runToken == token, item.status == .connecting else { return }
            switch result {
            case .failure(let error):
                item.status = .failed
                item.errorMessage = error.localizedDescription
                self.changed()
                self.schedule()
            case .success(let binary):
                do {
                    try FileManager.default.createDirectory(atPath: item.directory, withIntermediateDirectories: true)
                } catch {
                    item.status = .failed
                    item.errorMessage = "Can't create folder \(item.directory): \(error.localizedDescription)"
                    self.changed()
                    self.schedule()
                    return
                }
                self.timing(item, "tools ready")

                // Starts yt-dlp, with prefetched info when there is some (faster) or the page link.
                let launch: (URL?) -> Void = { [weak self, weak item] info in
                    guard let self = self, let item = item,
                          item.runToken == token, item.status == .connecting else { return }
                    item.usedPrefetch = (info != nil)
                    item.stage = info != nil ? "Starting download…" : "Getting video info…"
                    self.timing(item, info != nil ? "using prefetched info" : "getting video info")
                    let engine = VideoEngine(
                        binary: binary, pageURL: item.url, directory: item.directory,
                        quality: item.videoQuality, connections: Prefs.connections,
                        ffmpeg: YtDlp.shared.ffmpegPath, searchPath: YtDlp.shared.searchPath,
                        extraArgs: attempt >= 2 ? ["--extractor-args", "youtube:player_client=default,tv,web_safari,android"] : [],
                        infoJSON: info
                    ) { [weak self, weak item] event in
                        DispatchQueue.main.async {
                            guard let self = self, let item = item else { return }
                            self.handleVideo(event, for: item, token: token)
                        }
                    }
                    self.videoEngines[item.id] = engine
                    engine.start()
                }

                if attempt == 0 && !item.skipPrefetch {
                    item.stage = "Getting video info…"
                    VideoPrefetcher.shared.takeInfo(for: item.url, completion: launch)
                } else {
                    launch(nil)
                }
            }
        }
    }

    private func timing(_ item: DownloadItem, _ what: String) {
        let id = String(item.id.uuidString.prefix(6))
        TimingLog.write(String(format: "[%@] +%5.1fs  %@", id, Date().timeIntervalSince(item.videoStartedAt), what))
    }

    private func handleVideo(_ event: VideoEvent, for item: DownloadItem, token: UUID) {
        if case .stopped = event {
            item.speed = 0
            item.connections = 0
            return
        }
        guard item.runToken == token else { return }

        switch event {
        case .title(let title):
            item.fileName = FileUtil.sanitize(title)
            if item.status == .connecting {
                item.stage = "Starting download…"
                timing(item, "got video info")
            }
        case .progress(let downloaded, let total, let speed):
            if item.status == .connecting {
                item.status = .downloading
                item.stage = nil
                timing(item, "first data")
                changed()
            }
            guard item.status == .downloading else { return }
            item.totalBytes = total
            item.segments = [Segment(start: 0, end: total > 0 ? total - 1 : -1, downloaded: downloaded)]
            item.speed = speed
            item.connections = 1
        case .completed(let file):
            videoEngines[item.id] = nil
            item.fileName = file.lastPathComponent
            item.directory = file.deletingLastPathComponent().path
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
            item.totalBytes = size ?? max(item.totalBytes, 0)
            item.segments = [Segment(start: 0, end: max(0, item.totalBytes - 1), downloaded: item.totalBytes)]
            item.status = .completed
            item.dateCompleted = Date()
            item.speed = 0
            item.connections = 0
            item.stage = nil
            timing(item, "completed")
            changed()
            notifyCompleted(item)
            schedule()
        case .failed(let message):
            videoEngines[item.id] = nil
            timing(item, "failed: \(message)")
            // A download that used prefetched info failed: try once more the normal way.
            if item.usedPrefetch {
                item.usedPrefetch = false
                item.skipPrefetch = true
                item.status = .paused   // so startVideo's state checks pass
                startVideo(item)
                return
            }
            // YouTube often answers 403 when yt-dlp is out of date or a player client is blocked:
            // retry automatically before giving up.
            if message.contains("403"), item.videoAttempt < 2 {
                item.videoAttempt += 1
                item.status = .paused   // so startVideo's state checks pass
                startVideo(item)
                return
            }
            item.status = .failed
            item.stage = nil
            let lower = message.lowercased()
            if lower.contains("could not find chrome cookies") || lower.contains("cookies database") {
                item.errorMessage = "ODM couldn't read Chrome's cookies directly. Open this video in Chrome and press ODM's Download button on the video (or “Download video” in the extension) — that passes your YouTube sign-in to ODM."
            } else if lower.contains("not a bot") || lower.contains("sign in to confirm") {
                item.errorMessage = Prefs.useBrowserCookies
                    ? "YouTube asked to confirm you're not a bot. Open the video in Chrome (signed in to YouTube) and press ODM's Download button there, so the extension can pass your sign-in."
                    : "YouTube asked to confirm you're not a bot. Signing in fixes this: press “Use my browser sign-in and retry”."
            } else {
                item.errorMessage = message.contains("403")
                ? "The site refused the download (HTTP 403). Try again later, or press “Use my browser sign-in and retry”."
                : message
            }
            item.speed = 0
            item.connections = 0
            changed()
            schedule()
        case .stopped:
            break
        }
    }

    /// Stops whichever engine is running this item.
    private func stopEngines(for item: DownloadItem) {
        engines.removeValue(forKey: item.id)?.stop()
        videoEngines.removeValue(forKey: item.id)?.stop()
    }

    // MARK: File engine

    private func launchEngine(for item: DownloadItem, probe: ProbeResult, token: UUID) {
        let fm = FileManager.default

        // The file on the server changed size since we started: start over.
        if item.totalBytes > 0, probe.totalBytes > 0, item.totalBytes != probe.totalBytes, !item.segments.isEmpty {
            try? fm.removeItem(at: item.partURL)
            item.segments = []
        }

        if !item.nameResolved {
            let name = FileUtil.sanitize(probe.suggestedName ?? item.fileName)
            item.category = FileCategory.from(fileName: name)
            item.directory = directory(for: item.category)
            let dir = item.directory
            item.fileName = FileUtil.uniqueName(name, in: dir) { candidate in
                self.items.contains { $0 !== item && $0.directory == dir && $0.fileName == candidate && $0.status != .completed }
            }
            item.nameResolved = true
        }

        do {
            try fm.createDirectory(atPath: item.directory, withIntermediateDirectories: true)
        } catch {
            item.status = .failed
            item.errorMessage = "Can't create folder \(item.directory): \(error.localizedDescription)"
            changed()
            schedule()
            return
        }

        item.totalBytes = probe.totalBytes
        item.resumable = probe.resumable
        if !probe.resumable { item.segments = [] }

        let engine = DownloadEngine(
            url: probe.finalURL, headers: item.headers, partURL: item.partURL, finalURL: item.fileURL,
            totalBytes: probe.totalBytes, resumable: probe.resumable, segments: item.segments,
            maxConnections: Prefs.connections
        ) { [weak self, weak item] event in
            DispatchQueue.main.async {
                guard let self = self, let item = item else { return }
                self.handle(event, for: item, token: token)
            }
        }
        engines[item.id] = engine
        item.status = .downloading
        changed()
        engine.start()
    }

    private func handle(_ event: EngineEvent, for item: DownloadItem, token: UUID) {
        if case .stopped(let s) = event {
            // Paused: keep the final byte counts unless a new run already started.
            if engines[item.id] == nil && item.status == .paused { apply(s, to: item) }
            item.speed = 0
            item.connections = 0
            save()
            return
        }
        guard item.runToken == token else { return }

        switch event {
        case .progress(let s):
            guard item.status == .downloading else { return }
            apply(s, to: item)
            if Date().timeIntervalSince(lastSave) > 5 { save() }

        case .completed(let s, let dest):
            apply(s, to: item)
            engines[item.id] = nil
            item.fileName = dest.lastPathComponent
            item.directory = dest.deletingLastPathComponent().path
            if item.totalBytes <= 0 { item.totalBytes = s.segments.reduce(0) { $0 + $1.downloaded } }
            item.status = .completed
            item.dateCompleted = Date()
            item.speed = 0
            item.connections = 0
            changed()
            notifyCompleted(item)
            schedule()

        case .failed(let message, let s):
            apply(s, to: item)
            engines[item.id] = nil
            item.status = .failed
            item.errorMessage = message
            item.speed = 0
            item.connections = 0
            changed()
            schedule()

        case .stopped:
            break
        }
    }

    private func apply(_ s: EngineSnapshot, to item: DownloadItem) {
        item.segments = s.segments
        item.speed = s.speed
        item.connections = s.connections
        if s.totalBytes > 0 { item.totalBytes = s.totalBytes }
    }

    func pause(_ item: DownloadItem) {
        guard item.status.isActive || item.status == .queued else { return }
        item.runToken = UUID()
        item.stage = nil
        item.status = .paused
        item.speed = 0
        item.connections = 0
        stopEngines(for: item)
        changed()
        schedule()
    }

    func resume(_ item: DownloadItem) {
        guard item.status == .paused || item.status == .failed || item.status == .queued else { return }
        item.wantsWindow = true
        start(item)
    }

    func pauseAll() {
        for item in items where item.status.isActive || item.status == .queued { pause(item) }
    }

    /// Puts every unfinished download back in the queue (respects the parallel limit).
    func resumeAll() {
        for item in items where item.status == .paused || item.status == .failed {
            item.status = .queued
        }
        changed()
        schedule()
    }

    func redownload(_ item: DownloadItem) {
        item.runToken = UUID()
        stopEngines(for: item)
        if item.kind == .file { try? FileManager.default.removeItem(at: item.partURL) }
        item.segments = []
        item.totalBytes = -1
        item.errorMessage = nil
        item.dateCompleted = nil
        item.speed = 0
        item.status = .queued
        changed()
        schedule()
    }

    func remove(_ toRemove: [DownloadItem], deleteFiles: Bool) {
        for item in toRemove { ProgressWindows.shared.close(item.id) }
        for item in toRemove {
            item.runToken = UUID()
            stopEngines(for: item)
            if item.status != .completed && item.kind == .file {
                try? FileManager.default.removeItem(at: item.partURL)
            }
            if deleteFiles && item.status == .completed {
                try? FileManager.default.trashItem(at: item.fileURL, resultingItemURL: nil)
            }
        }
        let ids = Set(toRemove.map { $0.id })
        items.removeAll { ids.contains($0.id) }
        changed()
        schedule()
    }

    func clearCompleted() {
        items.removeAll { $0.status == .completed }
        changed()
    }

    // MARK: Finder

    func open(_ item: DownloadItem) {
        guard item.status == .completed else { reveal(item); return }
        NSWorkspace.shared.open(item.fileURL)
    }

    func reveal(_ item: DownloadItem) {
        let fm = FileManager.default
        if item.status == .completed, fm.fileExists(atPath: item.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        } else if fm.fileExists(atPath: item.partURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([item.partURL])
        } else {
            try? fm.createDirectory(atPath: item.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: item.directory))
        }
    }

    /// After an app update, refresh the unpacked extension folder Chrome loads from (if the user
    /// installed it), so the extension only needs a reload in chrome://extensions.
    func syncChromeExtension() {
        let fm = FileManager.default
        let dest = FileUtil.appSupportDir.appendingPathComponent("ChromeExtension")
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
              fm.fileExists(atPath: src.path), fm.fileExists(atPath: dest.path) else { return }
        func version(_ dir: URL) -> String? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json["version"] as? String
        }
        guard version(src) != version(dest) else { return }
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: src, to: dest)
    }

    /// Copies the bundled Chrome extension to Application Support and shows it in Finder.
    func revealChromeExtension() {
        let fm = FileManager.default
        let dest = FileUtil.appSupportDir.appendingPathComponent("ChromeExtension")
        if let src = Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
           fm.fileExists(atPath: src.path) {
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: src, to: dest)
        }
        if fm.fileExists(atPath: dest.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } else {
            let alert = NSAlert()
            alert.messageText = "Extension folder not found"
            alert.informativeText = "Use the ChromeExtension folder from the ODM source folder instead."
            alert.runModal()
        }
    }

    // MARK: Bookkeeping

    /// Call after any status/list change: refreshes the UI, Dock badge, sleep prevention, and saves.
    private func changed() {
        objectWillChange.send()
        let active = activeCount
        NSApplication.shared.dockTile.badgeLabel = active > 0 ? "\(active)" : nil
        if active > 0, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Downloading files")
        } else if active == 0, let a = sleepActivity {
            ProcessInfo.processInfo.endActivity(a)
            sleepActivity = nil
        }
        save()
    }

    func save() {
        lastSave = Date()
        let records = items.map { $0.record }
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("ODM: failed to save downloads: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return }
        items = records.map { r in
            var r = r
            // Downloads that were running when the app quit go back into the queue.
            if r.status == .downloading || r.status == .connecting { r.status = .queued }
            return DownloadItem(record: r)
        }
    }

    private func notifyCompleted(_ item: DownloadItem) {
        guard Prefs.notify else { return }
        NSSound(named: "Glass")?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = item.fileName
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
