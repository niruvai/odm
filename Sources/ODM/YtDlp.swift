import Foundation

/// Manages the helper tools ODM uses for web video:
///  • yt-dlp  – the video downloader (https://github.com/yt-dlp/yt-dlp)
///  • Deno    – JavaScript runtime yt-dlp needs to solve YouTube's player challenges
///  • ffmpeg  – merges separate HD video and audio streams into one MP4
/// Missing tools are downloaded on first use into ~/Library/Application Support/ODM/bin,
/// and yt-dlp is refreshed every few days because YouTube changes often.
final class YtDlp: ObservableObject {
    static let shared = YtDlp()

    @Published private(set) var version: String?
    @Published private(set) var status: String?        // e.g. "Downloading ffmpeg…"
    @Published private(set) var lastError: String?
    @Published private(set) var toolsChanged = 0       // bumps after installs so Settings refreshes

    var isInstalling: Bool { status != nil }

    private let workQueue = DispatchQueue(label: "odm.tools")
    private let ytdlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    private static let maxAge: TimeInterval = 3 * 24 * 3600

    #if arch(arm64)
    private let denoURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")!
    private let ffmpegURLs = [
        URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")!,
        URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-arm64.gz")!,
    ]
    #else
    private let denoURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-apple-darwin.zip")!
    private let ffmpegURLs = [
        URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip")!,
        URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-x64.gz")!,
    ]
    #endif

    private init() {
        refreshVersion()
    }

    // MARK: Locations

    var binDir: URL {
        let dir = FileUtil.appSupportDir.appendingPathComponent("bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var managedBinary: URL { binDir.appendingPathComponent("yt-dlp") }

    private func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Our own copy first, then Homebrew / MacPorts.
    var binary: URL? {
        firstExecutable([managedBinary.path, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"])
            .map { URL(fileURLWithPath: $0) }
    }

    var denoPath: String? {
        firstExecutable([binDir.appendingPathComponent("deno").path, "/opt/homebrew/bin/deno",
                         "/usr/local/bin/deno", NSHomeDirectory() + "/.deno/bin/deno"])
    }

    var ffmpegPath: String? {
        firstExecutable([binDir.appendingPathComponent("ffmpeg").path, "/opt/homebrew/bin/ffmpeg",
                         "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"])
    }

    /// PATH for yt-dlp: our tools first, so it finds Deno and ffmpeg.
    var searchPath: String {
        [binDir.path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
    }

    // MARK: Install / update

    /// Makes sure yt-dlp (required), Deno and ffmpeg (best effort) are present, then calls back on the
    /// main thread with yt-dlp's location. `forceUpdate` re-downloads yt-dlp even if it is recent.
    func prepare(forceUpdate: Bool = false, _ completion: @escaping (Result<URL, Error>) -> Void) {
        workQueue.async {
            let result = self.prepareSync(forceUpdate: forceUpdate)
            DispatchQueue.main.async {
                self.setStatus(nil)
                if case .failure(let e) = result { self.lastError = e.localizedDescription }
                self.toolsChanged += 1
                self.refreshVersion()
                completion(result)
            }
        }
    }

    /// Settings → "Update": fetch the newest yt-dlp now.
    func install() {
        prepare(forceUpdate: true) { _ in }
    }

    private func prepareSync(forceUpdate: Bool) -> Result<URL, Error> {
        let fm = FileManager.default
        DispatchQueue.main.async { self.lastError = nil }

        // 1. yt-dlp (required)
        var ytdlp = binary
        let managedExists = fm.isExecutableFile(atPath: managedBinary.path)
        let age = (try? fm.attributesOfItem(atPath: managedBinary.path)[.modificationDate] as? Date)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        if ytdlp == nil || forceUpdate || (managedExists && age > Self.maxAge) {
            setStatus("Downloading yt-dlp…")
            do {
                let tmp = try fetch(ytdlpURL)
                try installExecutable(from: tmp, to: managedBinary)
                ytdlp = managedBinary
            } catch {
                if ytdlp == nil {
                    return .failure(DMError.message("Could not download yt-dlp (\(error.localizedDescription)). Check your internet connection."))
                }
                // Keep using the older copy if the update failed.
            }
        }
        guard let ytdlpBinary = ytdlp else {
            return .failure(DMError.message("yt-dlp is not available."))
        }

        // 2. Deno (YouTube needs a JavaScript runtime)
        if denoPath == nil {
            setStatus("Downloading Deno (JavaScript runtime for YouTube)…")
            if let zip = try? fetch(denoURL), let file = try? unzipFind(zip, named: "deno") {
                try? installExecutable(from: file, to: binDir.appendingPathComponent("deno"))
            }
        }

        // 3. ffmpeg (needed for HD)
        if ffmpegPath == nil {
            setStatus("Downloading ffmpeg (for HD video)…")
            let target = binDir.appendingPathComponent("ffmpeg")
            for url in ffmpegURLs {
                guard let archive = try? fetch(url) else { continue }
                let file: URL?
                if url.pathExtension == "gz" {
                    file = try? gunzip(archive)
                } else {
                    file = try? unzipFind(archive, named: "ffmpeg")
                }
                guard let f = file else { continue }
                try? installExecutable(from: f, to: target)
                if YtDlp.runQuick(target, ["-version"]) != nil { break }
                try? fm.removeItem(at: target)   // didn't run on this Mac; try the next source
            }
        }
        return .success(ytdlpBinary)
    }

    private func setStatus(_ s: String?) {
        if Thread.isMainThread { status = s } else { DispatchQueue.main.async { self.status = s } }
    }

    /// Blocking download (only called on workQueue). Returns a temp file we own.
    private func fetch(_ url: URL) throws -> URL {
        final class Box { var result: Result<URL, Error> = .failure(DMError.message("Download did not start")) }
        let sem = DispatchSemaphore(value: 0)
        let box = Box()
        let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let tmp = tmp, code == 200 {
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent("odm-" + UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: tmp, to: dst)
                    box.result = .success(dst)
                } catch {
                    box.result = .failure(error)
                }
            } else if let error = error {
                box.result = .failure(error)
            } else {
                box.result = .failure(DMError.message("HTTP \(code)"))
            }
            sem.signal()
        }
        task.resume()
        sem.wait()
        return try box.result.get()
    }

    private func installExecutable(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.moveItem(at: src, to: dst)
        try fm.setAttributes([.posixPermissions: 0o755, .modificationDate: Date()], ofItemAtPath: dst.path)
        // Downloaded by us, but clear the quarantine flag just in case.
        _ = YtDlp.runQuick(URL(fileURLWithPath: "/usr/bin/xattr"), ["-d", "com.apple.quarantine", dst.path])
    }

    /// Unzips with ditto and returns the first file with the given name.
    private func unzipFind(_ zip: URL, named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odm-unzip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DMError.message("Could not unzip \(name)") }
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let u = e?.nextObject() as? URL {
            if u.lastPathComponent == name { return u }
        }
        throw DMError.message("\(name) not found in archive")
    }

    private func gunzip(_ gz: URL) throws -> URL {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("odm-gunzip-" + UUID().uuidString)
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        p.arguments = ["-c", gz.path]
        p.standardOutput = handle
        try p.run()
        p.waitUntilExit()
        try handle.close()
        guard p.terminationStatus == 0 else { throw DMError.message("Could not unpack ffmpeg") }
        return out
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

    /// Runs a short command and returns its trimmed stdout (nil if it fails).
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
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s ?? ""
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
         ffmpeg: String?, searchPath: String, extraArgs: [String] = [],
         onEvent: @escaping (VideoEvent) -> Void) {
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
        if Prefs.useBrowserCookies {
            args += ["--cookies-from-browser", "chrome"]
        }
        args += extraArgs
        args.append(pageURL)

        process.executableURL = binary
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath + ":" + (env["PATH"] ?? "")
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
