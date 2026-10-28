import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Preferences

enum Prefs {
    static let connectionsKey = "connectionsPerDownload"
    static let concurrentKey = "maxConcurrentDownloads"
    static let folderKey = "downloadFolder"
    static let categorizeKey = "sortIntoCategoryFolders"
    static let notifyKey = "notifyOnComplete"
    static let showProgressWindowKey = "showProgressWindow"
    static let chromeGuideDoneKey = "chromeGuideDone"
    static let videoQualityKey = "defaultVideoQuality"
    static let browserCookiesKey = "videoUseChromeCookies"

    static var defaultFolder: String {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("ODM").path
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            connectionsKey: 8,
            concurrentKey: 3,
            folderKey: defaultFolder,
            categorizeKey: true,
            notifyKey: true,
            showProgressWindowKey: true,
            videoQualityKey: "1080",
        ])
    }

    static var connections: Int { min(32, max(1, UserDefaults.standard.integer(forKey: connectionsKey))) }
    static var maxConcurrent: Int { min(10, max(1, UserDefaults.standard.integer(forKey: concurrentKey))) }
    static var categorize: Bool { UserDefaults.standard.bool(forKey: categorizeKey) }
    static var notify: Bool { UserDefaults.standard.bool(forKey: notifyKey) }
    static var showProgressWindow: Bool { UserDefaults.standard.bool(forKey: showProgressWindowKey) }
    static var videoQuality: String { UserDefaults.standard.string(forKey: videoQualityKey) ?? "1080" }
    static var useBrowserCookies: Bool { UserDefaults.standard.bool(forKey: browserCookiesKey) }
    static var downloadFolder: String {
        let s = UserDefaults.standard.string(forKey: folderKey) ?? ""
        return s.isEmpty ? defaultFolder : (s as NSString).expandingTildeInPath
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        b < 0 ? "—" : ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func speed(_ s: Double) -> String {
        s < 1 ? "" : bytes(Int64(s)) + "/s"
    }

    static func eta(_ t: TimeInterval?) -> String {
        guard let t = t, t.isFinite, t >= 0 else { return "" }
        let s = Int(t)
        if s >= 86_400 { return "\(s / 86_400)d \(s % 86_400 / 3600)h" }
        if s >= 3600 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }
}

// MARK: - File helpers

enum FileUtil {
    static func sanitize(_ name: String) -> String {
        var n = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        n = n.components(separatedBy: .controlCharacters).joined()
        n = n.trimmingCharacters(in: .whitespacesAndNewlines)
        while n.hasPrefix(".") { n.removeFirst() }
        if n.count > 200 {
            let ext = (n as NSString).pathExtension
            let base = String((n as NSString).deletingPathExtension.prefix(180))
            n = ext.isEmpty ? base : base + "." + ext
        }
        return n.isEmpty ? "download" : n
    }

    /// Picks "name (1).ext", "name (2).ext"… if the name (or its partial file) is taken.
    static func uniqueName(_ name: String, in dir: String, alsoTaken: (String) -> Bool = { _ in false }) -> String {
        let fm = FileManager.default
        func taken(_ n: String) -> Bool {
            let p = (dir as NSString).appendingPathComponent(n)
            return fm.fileExists(atPath: p) || fm.fileExists(atPath: p + ".odmpart") || alsoTaken(n)
        }
        guard taken(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var i = 1
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            if !taken(candidate) { return candidate }
            i += 1
        }
    }

    /// Final destination that never overwrites an existing file.
    static func freeURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ODM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - File icons (cached per extension)

enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    static func icon(for fileName: String) -> NSImage {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if let cached = cache[ext] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let img = NSWorkspace.shared.icon(for: type)
        cache[ext] = img
        return img
    }
}

// MARK: - HTTP helpers

enum Networking {
    static let defaultUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func apply(headers: [String: String], to req: inout URLRequest) {
        req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        // Compressed responses break byte ranges, so always ask for the raw bytes.
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (key, value) in headers {
            let clean = value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            if !clean.isEmpty { req.setValue(clean, forHTTPHeaderField: key) }
        }
        if headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }) {
            req.httpShouldHandleCookies = false
        }
    }

    /// Keeps our headers on redirects, but never sends cookies to a different host.
    static func redirected(_ request: URLRequest, from task: URLSessionTask) -> URLRequest {
        var r = request
        guard let original = task.originalRequest else { return r }
        let sameHost = original.url?.host == request.url?.host
        for (k, v) in original.allHTTPHeaderFields ?? [:] {
            if !sameHost && k.caseInsensitiveCompare("Cookie") == .orderedSame { continue }
            if r.value(forHTTPHeaderField: k) == nil { r.setValue(v, forHTTPHeaderField: k) }
        }
        return r
    }
}

enum DMError: LocalizedError {
    case http(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Server returned HTTP \(code) (\(HTTPURLResponse.localizedString(forStatusCode: code)))"
        case .message(let m):
            return m
        }
    }
}

extension Notification.Name {
    static let showAddDownload = Notification.Name("ODMShowAddDownload")
}
