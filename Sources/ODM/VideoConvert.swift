import Foundation

/// Makes downloaded videos open in editing apps (Premiere Pro, Final Cut, iMovie).
/// Some sites (Facebook, YouTube above 1080p) only offer VP9 or AV1 video and Opus audio,
/// which those apps can't import. Such files are converted to H.264 + AAC in an .mp4.
/// Files that are already H.264/HEVC with AAC/MP3 audio are left untouched.
final class VideoConverter {
    struct Info {
        var videoCodec: String?
        var audioCodec: String?
        var height = 0
        var duration: Double = 0

        static let okVideo: Set<String> = ["h264", "hevc", "prores", "mpeg4"]
        static let okAudio: Set<String> = ["aac", "mp3", "alac", "ac3"]

        var videoOK: Bool { videoCodec.map { Self.okVideo.contains($0) } ?? true }
        var audioOK: Bool { audioCodec.map { Self.okAudio.contains($0) || $0.hasPrefix("pcm_") } ?? true }
        var needsConversion: Bool { videoCodec != nil && (!videoOK || !audioOK) }
    }

    private let ffmpeg: String
    private let input: URL
    private let info: Info
    private var process: Process?
    private var cancelled = false
    private let lock = NSLock()

    init(ffmpeg: String, input: URL, info: Info) {
        self.ffmpeg = ffmpeg
        self.input = input
        self.info = info
    }

    // MARK: Inspecting a file

    /// Reads the codecs from `ffmpeg -i` (ODM ships ffmpeg, not ffprobe).
    static func inspect(ffmpeg: String, file: URL) -> Info? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-hide_banner", "-i", file.path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var info = Info()
        for line in text.components(separatedBy: "\n") {
            if line.contains("Duration:"), let r = line.range(of: "Duration: ") {
                let t = line[r.upperBound...].prefix(11)   // 00:01:02.33
                let parts = t.split(separator: ":").compactMap { Double($0) }
                if parts.count == 3 { info.duration = parts[0] * 3600 + parts[1] * 60 + parts[2] }
            }
            guard line.contains("Stream #") else { continue }
            if info.videoCodec == nil, let r = line.range(of: "Video: ") {
                if line.contains("attached pic") { continue }
                info.videoCodec = codecName(line[r.upperBound...])
                if let m = line.range(of: #"\b\d{2,5}x(\d{2,5})\b"#, options: .regularExpression) {
                    let size = line[m]
                    if let x = size.firstIndex(of: "x") { info.height = Int(size[size.index(after: x)...]) ?? 0 }
                }
            } else if info.audioCodec == nil, let r = line.range(of: "Audio: ") {
                info.audioCodec = codecName(line[r.upperBound...])
            }
        }
        return info
    }

    private static func codecName(_ s: Substring) -> String {
        String(s.prefix { $0.isLetter || $0.isNumber || $0 == "_" }).lowercased()
    }

    // MARK: Converting

    /// Converts the file and calls `completion` with the new file (or the error) on the main queue.
    /// `progress` gets 0…1 on the main queue.
    func run(progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.convert(progress: progress)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        if let p = p, p.isRunning { p.terminate() }
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    private func convert(progress: @escaping (Double) -> Void) -> Result<URL, Error> {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let temp = dir.appendingPathComponent(".\(base).odmconvert.mp4")
        try? FileManager.default.removeItem(at: temp)

        // Hardware encoder first (fast), then the software one.
        var attempts: [[String]] = []
        if info.videoOK {
            attempts.append(["-c:v", "copy"])
        } else {
            let rate: String
            switch info.height {
            case 2000...: rate = "35M"
            case 1300...: rate = "16M"
            case 1000...: rate = "10M"
            case 700...:  rate = "6M"
            default:      rate = "3M"
            }
            attempts.append(["-c:v", "h264_videotoolbox", "-b:v", rate, "-profile:v", "high", "-pix_fmt", "yuv420p"])
            attempts.append(["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p"])
        }
        let audio = info.audioOK ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "192k"]

        var lastError = "The video could not be converted."
        for video in attempts {
            if isCancelled { break }
            var args = ["-hide_banner", "-nostdin", "-y", "-i", input.path,
                        "-map", "0:v:0", "-map", "0:a:0?", "-dn", "-sn"]
            args += video + audio
            if !info.videoOK { args += ["-tag:v", "avc1"] }
            args += ["-movflags", "+faststart",
                     "-progress", "pipe:1", "-nostats", "-loglevel", "error", temp.path]

            let (ok, message) = runFFmpeg(args, progress: progress)
            if ok { lastError = ""; break }
            lastError = message
            try? FileManager.default.removeItem(at: temp)
        }

        if isCancelled {
            try? FileManager.default.removeItem(at: temp)
            return .failure(DMError.message("Stopped"))
        }
        guard lastError.isEmpty, FileManager.default.fileExists(atPath: temp.path) else {
            return .failure(DMError.message(lastError))
        }

        // Replace the original with the converted .mp4.
        do {
            try FileManager.default.removeItem(at: input)
            let final = FileUtil.freeURL(for: dir.appendingPathComponent(base + ".mp4"))
            try FileManager.default.moveItem(at: temp, to: final)
            return .success(final)
        } catch {
            return .failure(error)
        }
    }

    private func runFFmpeg(_ args: [String], progress: @escaping (Double) -> Void) -> (Bool, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let duration = info.duration
        var buffer = ""
        out.fileHandleForReading.readabilityHandler = { h in
            guard let s = String(data: h.availableData, encoding: .utf8), !s.isEmpty else { return }
            buffer += s
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl])
                buffer.removeSubrange(...nl)
                // out_time_us=12345678 (older builds call it out_time_ms, also in microseconds)
                if duration > 0, line.hasPrefix("out_time_"), let eq = line.firstIndex(of: "="),
                   let us = Double(line[line.index(after: eq)...]) {
                    let f = min(1, max(0, us / 1_000_000 / duration))
                    DispatchQueue.main.async { progress(f) }
                }
            }
        }

        lock.lock()
        if cancelled { lock.unlock(); return (false, "Stopped") }
        process = p
        lock.unlock()

        do { try p.run() } catch { return (false, error.localizedDescription) }
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil

        lock.lock(); process = nil; lock.unlock()

        if p.terminationStatus == 0 { return (true, "") }
        let msg = String(data: errData, encoding: .utf8)?
            .components(separatedBy: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (false, msg ?? "The video could not be converted.")
    }
}
