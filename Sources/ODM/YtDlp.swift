import Foundation

/// Finds, installs and updates yt-dlp (https://github.com/yt-dlp/yt-dlp), and finds ffmpeg.
/// yt-dlp is downloaded on first use into ~/Library/Application Support/ODM/bin.
final class YtDlp: ObservableObject {
    static let shared = YtDlp()

    @Published private(set) var version: String?
    @Published private(set) var isInstalling = false
    @Published private(set) var lastError: String?

    private let releaseURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    private var waiters: [(Result<URL, Error>) -> Void] = []

    private init() {
        refreshVersion()
    }

    var binDir: URL {
        let dir = FileUtil.appSupportDir.appendingPathComponent("bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var managedBinary: URL { binDir.appendingPathComponent("yt-dlp") }

    /// Our own copy first, then a Homebrew / MacPorts install.
    var binary: URL? {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: managedBinary.path) { return managedBinary }
        for p in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"]
        where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// ffmpeg is needed to merge HD video + audio. Without it yt-dlp can only fetch single-file formats.
    var ffmpegPath: String? {
        let fm = FileManager.default
        let candidates = [binDir.appendingPathComponent("ffmpeg").path,
                          "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Calls back on the main thread with a usable yt-dlp, downloading it first if needed.
    func ensureInstalled(_ completion: @escaping (Result<URL, Error>) -> Void) {
        if let b = binary {
            completion(.success(b))
            return
        }
        waiters.append(completion)
        if !isInstalling { install() }
    }

    /// Downloads the latest yt-dlp release (also used for "Update").
    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        lastError = nil
        let destination = managedBinary

        let task = URLSession.shared.downloadTask(with: releaseURL) { [weak self] tmp, response, error in
            var result: Result<URL, Error>
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let tmp = tmp, code == 200 {
                do {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                    try fm.moveItem(at: tmp, to: destination)
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
                    result = .success(destination)
                } catch {
                    result = .failure(DMError.message("Could not install yt-dlp: \(error.localizedDescription)"))
                }
            } else {
                let reason = error?.localizedDescription ?? "HTTP \(code)"
                result = .failure(DMError.message("Could not download yt-dlp (\(reason)). Check your internet connection."))
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isInstalling = false
                if case .failure(let e) = result { self.lastError = e.localizedDescription }
                let callbacks = self.waiters
                self.waiters.removeAll()
                callbacks.forEach { $0(result) }
                self.refreshVersion()
            }
        }
        task.resume()
    }

    func refreshVersion() {
        guard let b = binary else {
            version = nil
            return
        }
        DispatchQueue.global().async {
            let out = YtDlp.runQuick(b, ["--version"])
            DispatchQueue.main.async { self.version = out }
        }
    }

    /// Runs a short command and returns its trimmed stdout.
    static func runQuick(_ exe: URL, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }

    /// Sites handled by yt-dlp automatically when a link is added.
    static func isVideoPage(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let hosts = ["youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "dailymotion.com",
                     "facebook.com", "fb.watch", "instagram.com", "tiktok.com", "twitter.com", "x.com",
                     "twitch.tv", "soundcloud.com", "bilibili.com", "reddit.com"]
        guard hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        // A direct file link on those sites (e.g. an .mp4 on a CDN subdomain) is still a plain file.
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ["html", "htm", "php"].contains(ext)
    }
}

// MARK: - Running one yt-dlp download

enum VideoEvent {
    case title(String)
    case progress(downloaded: Int64, total: Int64, speed: Double)
    case completed(URL)
    case failed(String)
    case stopped
}

/// Runs yt-dlp for one video and reports progress. Pausing stops the process; starting again
/// continues from yt-dlp's .part files.
final class VideoEngine {
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let queue = DispatchQueue(label: "odm.video")
    private let onEvent: (VideoEvent) -> Void

    private var outReader = LineReader()
    private var errReader = LineReader()
    private var userStopped = false
    private var finished = false
    private var filePath: String?
    private var lastError: String?
    private var lastProgress = Date.distantPast

    init(binary: URL, pageURL: String, directory: String, quality: String, connections: Int,
         ffmpeg: String?, onEvent: @escaping (VideoEvent) -> Void) {
        self.onEvent = onEvent

        var args: [String] = [
            "--newline", "--progress", "--no-simulate",
            "--no-playlist", "--no-mtime", "--continue",
            "--concurrent-fragments", String(max(1, min(connections, 16))),
            "--progress-template",
            "download:TDM %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s",
            "--print", "before_dl:TDMTITLE %(title)s",
            "--print", "after_move:TDMFILE %(filepath)s",
            "-o", (directory as NSString).appendingPathComponent("%(title).150B [%(id)s].%(ext)s"),
        ]

        let height = Int(quality)
        if quality == "audio" {
            args += ["-f", "ba[ext=m4a]/ba/b"]
        } else if let ffmpeg = ffmpeg {
            args += ["--ffmpeg-location", ffmpeg, "--merge-output-format", "mp4"]
            if let h = height {
                // Prefer H.264 + AAC so the file plays in QuickTime / on every device.
                args += ["-f", "bv*[height<=\(h)]+ba/b[height<=\(h)]/bv*+ba/b", "-S", "vcodec:h264,res,acodec:m4a"]
            } else {
                args += ["-f", "bv*+ba/b"]
            }
        } else {
            // No ffmpeg: only formats that already contain video + audio in one file.
            args += ["-f", height.map { "b[height<=\($0)]/b" } ?? "b"]
        }
        args.append(pageURL)

        process.executableURL = binary
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        process.environment = env
        process.standardOutput = outPipe
        process.standardError = errPipe
    }

    func start() {
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            self?.queue.async { self?.consume(d, stderr: false) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            self?.queue.async { self?.consume(d, stderr: true) }
        }
        process.terminationHandler = { [weak self] p in
            // Give the pipes a moment to deliver their last lines.
            self?.queue.asyncAfter(deadline: .now() + 0.3) {
                self?.finish(status: p.terminationStatus)
            }
        }
        do {
            try process.run()
        } catch {
            queue.async {
                self.finished = true
                self.onEvent(.failed("Could not start yt-dlp: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        queue.async {
            self.userStopped = true
            if self.process.isRunning { self.process.terminate() }
        }
    }

    private func consume(_ data: Data, stderr: Bool) {
        let lines = stderr ? errReader.feed(data) : outReader.feed(data)
        for line in lines { handle(line) }
    }

    private func handle(_ line: String) {
        if line.hasPrefix("TDMTITLE ") {
            onEvent(.title(String(line.dropFirst(9))))
        } else if line.hasPrefix("TDMFILE ") {
            filePath = String(line.dropFirst(8))
        } else if line.hasPrefix("TDM ") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 5 else { return }
            let num: (String) -> Double? = { Double($0) }
            let downloaded = Int64(num(parts[1]) ?? 0)
            let total = Int64(num(parts[2]) ?? num(parts[3]) ?? -1)
            let speed = num(parts[4]) ?? 0
            let now = Date()
            guard now.timeIntervalSince(lastProgress) > 0.3 || (total > 0 && downloaded >= total) else { return }
            lastProgress = now
            onEvent(.progress(downloaded: downloaded, total: total, speed: speed))
        } else if let r = line.range(of: "ERROR: ") {
            lastError = String(line[r.upperBound...])
        }
    }

    private func finish(status: Int32) {
        guard !finished else { return }
        finished = true
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        for line in outReader.flush() + errReader.flush() { handle(line) }

        if userStopped {
            onEvent(.stopped)
        } else if status == 0, let path = filePath {
            onEvent(.completed(URL(fileURLWithPath: path)))
        } else if status == 0 {
            onEvent(.failed("yt-dlp finished but did not report a file."))
        } else {
            onEvent(.failed(lastError ?? "yt-dlp stopped with error code \(status)."))
        }
    }
}

/// Splits a byte stream into lines (handles \r progress updates too).
struct LineReader {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: lineData, encoding: .utf8), !s.isEmpty { lines.append(s) }
        }
        return lines
    }

    mutating func flush() -> [String] {
        defer { buffer.removeAll() }
        guard let s = String(data: buffer, encoding: .utf8), !s.isEmpty else { return [] }
        return [s]
    }
}
