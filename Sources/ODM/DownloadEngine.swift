import Foundation

struct EngineSnapshot {
    var segments: [Segment]
    var speed: Double
    var connections: Int
    var totalBytes: Int64
}

enum EngineEvent {
    case progress(EngineSnapshot)
    case stopped(EngineSnapshot)
    case completed(EngineSnapshot, URL)
    case failed(String, EngineSnapshot)
}

/// Downloads one file over several parallel connections, IDM style:
///  • the file is split into byte ranges, one per connection
///  • when a connection finishes early it takes over half of the biggest
///    remaining range (dynamic segmentation), so all connections stay busy
///  • progress of every range is saved, so pause / resume / app restart continue where they left off
///
/// Every connection gets its own URLSession so each one is a separate TCP connection
/// (one session would multiplex everything over a single HTTP/2 connection).
/// All state is touched only on `queue`.
final class DownloadEngine: NSObject, URLSessionDataDelegate {
    static let minSplitSize: Int64 = 1 << 20   // never create ranges smaller than 1 MB
    static let maxRetries = 8

    private let url: URL
    private let headers: [String: String]
    private let partURL: URL
    private let finalURL: URL
    private var totalBytes: Int64
    private let resumable: Bool
    private let maxConnections: Int
    private var segments: [Segment]
    private let onEvent: (EngineEvent) -> Void

    private let queue = DispatchQueue(label: "odm.engine")
    private let opQueue = OperationQueue()
    private var sessions: [URLSession] = []
    private var fileHandle: FileHandle?
    private var timer: DispatchSourceTimer?

    private struct Active { let task: URLSessionDataTask; let segment: Int; let slot: Int }
    private var active: [Int: Active] = [:]          // taskIdentifier -> info
    private var taskErrors: [Int: String] = [:]      // problems detected from the response headers
    private var retries: [Int: Int] = [:]            // segment index -> consecutive failures
    private var coolingDown = Set<Int>()             // segments waiting before a retry
    private var stopped = false

    private var bytesSinceTick: Int64 = 0
    private var lastTick = Date()
    private var speed: Double = 0

    init(url: URL, headers: [String: String], partURL: URL, finalURL: URL,
         totalBytes: Int64, resumable: Bool, segments: [Segment], maxConnections: Int,
         onEvent: @escaping (EngineEvent) -> Void) {
        self.url = url
        self.headers = headers
        self.partURL = partURL
        self.finalURL = finalURL
        self.totalBytes = totalBytes
        self.resumable = resumable
        self.segments = segments
        // Without range support only one connection is possible.
        self.maxConnections = (resumable && totalBytes > 0) ? max(1, maxConnections) : 1
        self.onEvent = onEvent
        super.init()

        opQueue.underlyingQueue = queue
        opQueue.maxConcurrentOperationCount = 1
        for _ in 0..<self.maxConnections {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 7 * 24 * 3600
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            config.httpMaximumConnectionsPerHost = 1
            sessions.append(URLSession(configuration: config, delegate: self, delegateQueue: opQueue))
        }
    }

    // MARK: Public controls

    func start() { queue.async { self.begin() } }

    func stop() {
        queue.async {
            guard !self.stopped else { return }
            self.shutDown()
            self.onEvent(.stopped(self.snapshot()))
        }
    }

    // MARK: Setup

    private func begin() {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: partURL.path)

        if !resumable || !existed || segments.isEmpty {
            // Fresh start (or the server can't resume, so earlier bytes are useless).
            if existed { try? fm.removeItem(at: partURL) }
            segments = makeInitialSegments()
        }
        if !fm.fileExists(atPath: partURL.path) {
            guard fm.createFile(atPath: partURL.path, contents: nil) else {
                fail("Can't create a file in \(partURL.deletingLastPathComponent().path). Check the download folder in Settings.")
                return
            }
        }
        do {
            let fh = try FileHandle(forWritingTo: partURL)
            if resumable && totalBytes > 0 { try fh.truncate(atOffset: UInt64(totalBytes)) }
            fileHandle = fh
        } catch {
            fail("Can't open the file for writing: \(error.localizedDescription)")
            return
        }

        if segments.allSatisfy({ $0.isComplete }) {
            finish()
            return
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 0.5)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
        lastTick = Date()

        fill()
    }

    private func makeInitialSegments() -> [Segment] {
        guard resumable, totalBytes > 0 else {
            return [Segment(start: 0, end: totalBytes > 0 ? totalBytes - 1 : -1, downloaded: 0)]
        }
        let count = max(1, min(Int64(maxConnections), totalBytes / Self.minSplitSize))
        let size = totalBytes / count
        var result: [Segment] = []
        for i in 0..<count {
            let s = i * size
            let e = (i == count - 1) ? totalBytes - 1 : s + size - 1
            result.append(Segment(start: s, end: e, downloaded: 0))
        }
        return result
    }

    // MARK: Scheduling connections

    private func fill() {
        guard !stopped else { return }
        while active.count < maxConnections {
            let busySegments = Set(active.values.map { $0.segment })
            let busySlots = Set(active.values.map { $0.slot })
            guard let slot = (0..<maxConnections).first(where: { !busySlots.contains($0) }) else { break }

            if let idx = segments.indices.first(where: {
                !segments[$0].isComplete && !busySegments.contains($0) && !coolingDown.contains($0)
            }) {
                launch(segment: idx, slot: slot)
            } else if let idx = splitLargest(busy: busySegments) {
                launch(segment: idx, slot: slot)
            } else {
                break
            }
        }
    }

    /// Dynamic segmentation: hand half of the biggest unfinished range to a free connection.
    private func splitLargest(busy: Set<Int>) -> Int? {
        guard resumable, totalBytes > 0 else { return nil }
        var best: Int?
        var bestRemaining: Int64 = 0
        for idx in busy {
            let r = segments[idx].remaining
            if r != Int64.max && r > bestRemaining { best = idx; bestRemaining = r }
        }
        guard let b = best, bestRemaining >= Self.minSplitSize * 2 else { return nil }
        let old = segments[b]
        let mid = old.nextOffset + bestRemaining / 2
        segments.append(Segment(start: mid, end: old.end, downloaded: 0))
        segments[b].end = mid - 1   // the running request is trimmed in didReceive(data:)
        return segments.count - 1
    }

    private func launch(segment idx: Int, slot: Int) {
        let seg = segments[idx]
        var req = URLRequest(url: url)
        Networking.apply(headers: headers, to: &req)
        if resumable {
            let range = seg.end >= 0 ? "bytes=\(seg.nextOffset)-\(seg.end)" : "bytes=\(seg.nextOffset)-"
            req.setValue(range, forHTTPHeaderField: "Range")
        }
        let task = sessions[slot].dataTask(with: req)
        active[task.taskIdentifier] = Active(task: task, segment: idx, slot: slot)
        task.resume()
    }

    // MARK: URLSession delegate (runs on `queue`)

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Networking.redirected(request, from: task))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let id = dataTask.taskIdentifier
        if let http = response as? HTTPURLResponse, let info = active[id] {
            if http.statusCode >= 400 {
                taskErrors[id] = DMError.http(http.statusCode).localizedDescription
                completionHandler(.cancel)
                return
            }
            if resumable && http.statusCode != 206 {
                // Server sent the whole file instead of our range. Only OK for a range starting at 0
                // that covers the whole file.
                let seg = segments[info.segment]
                let wholeFile = seg.nextOffset == 0 && (seg.end < 0 || seg.end == totalBytes - 1)
                if !wholeFile {
                    taskErrors[id] = "range"
                    completionHandler(.cancel)
                    return
                }
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !stopped, let info = active[dataTask.taskIdentifier], let fh = fileHandle else { return }
        let idx = info.segment
        var seg = segments[idx]
        var chunk = data

        if seg.end >= 0 {
            let remaining = seg.length - seg.downloaded
            if remaining <= 0 { dataTask.cancel(); return }
            if Int64(chunk.count) > remaining { chunk = chunk.prefix(Int(remaining)) }
        }

        do {
            try fh.seek(toOffset: UInt64(seg.nextOffset))
            try fh.write(contentsOf: chunk)
        } catch {
            fail("Writing to disk failed: \(error.localizedDescription)")
            return
        }

        seg.downloaded += Int64(chunk.count)
        segments[idx] = seg
        bytesSinceTick += Int64(chunk.count)
        retries[idx] = 0

        if seg.isComplete { dataTask.cancel() }   // range done (possibly shortened by a split)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        guard let info = active.removeValue(forKey: id) else { return }
        let headerProblem = taskErrors.removeValue(forKey: id)
        guard !stopped else { return }
        let idx = info.segment

        // A stream of unknown size ends when the server closes it cleanly.
        if segments[idx].end < 0 && error == nil && headerProblem == nil {
            segments[idx].end = segments[idx].start + segments[idx].downloaded - 1
            totalBytes = segments[idx].end + 1
            finish()
            return
        }

        if segments[idx].isComplete {
            if segments.allSatisfy({ $0.isComplete }) { finish() } else { fill() }
            return
        }

        if headerProblem == "range" {
            fail("The server stopped accepting multi-part requests. Try “Redownload”.")
            return
        }

        // Connection dropped or server error: retry this range after a short pause.
        let count = (retries[idx] ?? 0) + 1
        retries[idx] = count
        if count > Self.maxRetries {
            fail(headerProblem ?? error?.localizedDescription ?? "The connection closed too early.")
            return
        }
        if !resumable {
            segments[idx].downloaded = 0
            try? fileHandle?.truncate(atOffset: 0)
        }
        coolingDown.insert(idx)
        queue.asyncAfter(deadline: .now() + Double(min(count * 2, 10))) { [weak self] in
            guard let self = self, !self.stopped else { return }
            self.coolingDown.remove(idx)
            self.fill()
        }
        fill()
    }

    // MARK: Progress, completion, failure

    private func tick() {
        guard !stopped else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let instant = dt > 0 ? Double(bytesSinceTick) / dt : 0
        bytesSinceTick = 0
        speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3
        onEvent(.progress(snapshot()))
    }

    private func snapshot() -> EngineSnapshot {
        EngineSnapshot(segments: segments, speed: speed, connections: active.count, totalBytes: totalBytes)
    }

    private func shutDown() {
        stopped = true
        timer?.cancel()
        timer = nil
        for a in active.values { a.task.cancel() }
        active.removeAll()
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil
        for s in sessions { s.invalidateAndCancel() }
        speed = 0
    }

    private func finish() {
        shutDown()
        do {
            let dest = FileUtil.freeURL(for: finalURL)
            try FileManager.default.moveItem(at: partURL, to: dest)
            onEvent(.completed(snapshot(), dest))
        } catch {
            onEvent(.failed("Download finished but the file couldn't be moved: \(error.localizedDescription)", snapshot()))
        }
    }

    private func fail(_ message: String) {
        guard !stopped else { return }
        shutDown()
        onEvent(.failed(message, snapshot()))
    }
}
