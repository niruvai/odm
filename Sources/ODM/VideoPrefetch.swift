import Foundation

/// Fetches a video's info (title, formats, stream links) in the background as soon as the user
/// opens ODM's quality menu on a video page. When they then pick a quality, the download can start
/// from that saved info instead of waiting for the slow "get video info" step again.
///
/// Everything here is optional: if a prefetch is missing, failed, too old or slow, the download
/// simply runs the normal way. Used only on the main thread.
final class VideoPrefetcher {
    static let shared = VideoPrefetcher()

    private final class Entry {
        let started = Date()
        var file: URL?
        var finished = false
        var failed = false
        var process: Process?
        var waiters: [(URL?) -> Void] = []
    }

    private var entries: [String: Entry] = [:]
    /// Stream links in the saved info expire after a few hours; stay well below that.
    private let maxAge: TimeInterval = 20 * 60
    /// How long a download may wait for a prefetch that is still running (counted from its start).
    private let maxWait: TimeInterval = 25
    private let maxRunning = 2

    private var dir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("odm-prefetch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Start fetching info for this page (no-op if already fresh or running).
    func prefetch(_ pageURL: String) {
        cleanUp()
        if let e = entries[pageURL], !e.failed { return }
        let running = entries.values.filter { !$0.finished }.count
        guard running < maxRunning else { return }

        let entry = Entry()
        entries[pageURL] = entry
        TimingLog.write("prefetch start  \(pageURL)")

        YtDlp.shared.prepare { [weak self] result in
            guard let self = self, case .success(let binary) = result else {
                self?.finish(entry, file: nil)
                return
            }
            self.run(binary, pageURL: pageURL, entry: entry)
        }
    }

    /// Hands over saved info for this page, waiting briefly if it is still being fetched.
    /// Calls back on the main thread with nil when there is nothing usable.
    func takeInfo(for pageURL: String, completion: @escaping (URL?) -> Void) {
        cleanUp()
        guard let entry = entries[pageURL], !entry.failed else {
            completion(nil)
            return
        }
        if entry.finished {
            entries[pageURL] = nil
            completion(entry.file)
            return
        }
        let remaining = maxWait - Date().timeIntervalSince(entry.started)
        guard remaining > 0 else {
            completion(nil)
            return
        }
        // Answer exactly once: either when the prefetch finishes or when the wait runs out.
        final class Once { var done = false }
        let once = Once()
        entry.waiters.append { file in
            guard !once.done else { return }
            once.done = true
            completion(file)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard !once.done else { return }
            once.done = true
            TimingLog.write("prefetch too slow, downloading normally  \(pageURL)")
            completion(nil)
        }
        // A finished prefetch is single-use.
        entry.waiters.append { [weak self] _ in self?.entries[pageURL] = nil }
    }

    // MARK: Internals

    private func run(_ binary: URL, pageURL: String, entry: Entry) {
        let fm = FileManager.default
        let out = dir.appendingPathComponent(UUID().uuidString + ".json")
        guard fm.createFile(atPath: out.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: out) else {
            finish(entry, file: nil)
            return
        }

        let p = Process()
        p.executableURL = binary
        p.arguments = ["--no-playlist", "--dump-single-json"] + YtDlp.cookieArgs(for: pageURL) + [pageURL]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = YtDlp.shared.searchPath + ":" + (env["PATH"] ?? "")
        env["PYTHONIOENCODING"] = "utf-8"
        p.environment = env
        p.standardOutput = handle
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            try? handle.close()
            let size = (try? fm.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.intValue ?? 0
            let ok = proc.terminationStatus == 0 && size > 100
            DispatchQueue.main.async {
                if !ok { try? fm.removeItem(at: out) }
                self?.finish(entry, file: ok ? out : nil)
            }
        }
        do {
            try p.run()
            entry.process = p
        } catch {
            try? handle.close()
            finish(entry, file: nil)
        }
    }

    private func finish(_ entry: Entry, file: URL?) {
        entry.finished = true
        entry.failed = (file == nil)
        entry.file = file
        entry.process = nil
        TimingLog.write(String(format: "prefetch %@ after %.1fs", file == nil ? "failed" : "ready",
                               Date().timeIntervalSince(entry.started)))
        let waiters = entry.waiters
        entry.waiters.removeAll()
        waiters.forEach { $0(file) }
    }

    private func cleanUp() {
        let now = Date()
        for (key, e) in entries where e.finished && (e.failed || now.timeIntervalSince(e.started) > maxAge) {
            if let f = e.file { try? FileManager.default.removeItem(at: f) }
            entries[key] = nil
        }
    }
}

/// A small log of how long each step of a video download takes, so slow steps can be found:
/// ~/Library/Logs/ODM/timing.log
enum TimingLog {
    private static let queue = DispatchQueue(label: "odm.timinglog")

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ODM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timing.log")
    }

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        let line = "\(stamp)  \(message)\n"
        queue.async {
            let url = fileURL
            let fm = FileManager.default
            // Keep the log small.
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > 512_000 {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            }
        }
    }
}
