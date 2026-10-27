import Foundation

// MARK: - Status

enum DownloadStatus: String, Codable {
    case queued, connecting, downloading, paused, completed, failed

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .connecting: return "Connecting…"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .queued: return "clock"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var isActive: Bool { self == .connecting || self == .downloading }
}

// MARK: - Kind: plain file (own engine) or web video (yt-dlp)

enum DownloadKind: String, Codable {
    case file, video
}

struct QualityOption: Identifiable {
    let id: String      // stored in settings / sent by the extension
    let label: String   // shown in menus
}

enum VideoQuality {
    static let options: [QualityOption] = [
        QualityOption(id: "best", label: "Best available"),
        QualityOption(id: "2160", label: "4K (2160p)"),
        QualityOption(id: "1080", label: "1080p"),
        QualityOption(id: "720", label: "720p"),
        QualityOption(id: "480", label: "480p"),
        QualityOption(id: "360", label: "360p"),
        QualityOption(id: "audio", label: "Audio only (m4a)"),
    ]

    static func label(for id: String) -> String {
        options.first { $0.id == id }?.label ?? id
    }
}

// MARK: - Category (IDM-style folders)

enum FileCategory: String, Codable, CaseIterable, Identifiable {
    case video, music, compressed, programs, documents, images, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "Video"
        case .music: return "Music"
        case .compressed: return "Compressed"
        case .programs: return "Programs"
        case .documents: return "Documents"
        case .images: return "Images"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .music: return "music.note"
        case .compressed: return "doc.zipper"
        case .programs: return "shippingbox"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .other: return "doc"
        }
    }

    static func from(fileName: String) -> FileCategory {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "3gp", "mpg", "mpeg", "ts":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "wma", "opus", "aiff":
            return .music
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "iso":
            return .compressed
        case "dmg", "pkg", "app", "exe", "msi", "deb", "rpm", "apk", "appimage", "ipa":
            return .programs
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "epub", "rtf", "csv",
             "odt", "pages", "key", "numbers", "md":
            return .documents
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff", "psd":
            return .images
        default:
            return .other
        }
    }
}

// MARK: - Segment (one byte range downloaded by one connection)

struct Segment: Codable, Equatable {
    var start: Int64
    /// Inclusive end offset. -1 means "unknown, read until the server closes".
    var end: Int64
    var downloaded: Int64

    var length: Int64 { end < 0 ? -1 : end - start + 1 }
    var isComplete: Bool { end >= 0 && downloaded >= length }
    var nextOffset: Int64 { start + downloaded }
    var remaining: Int64 { end < 0 ? Int64.max : max(0, length - downloaded) }
}

// MARK: - Persisted record

struct DownloadRecord: Codable {
    var id: UUID
    var url: String
    var fileName: String
    var directory: String
    var nameResolved: Bool
    var totalBytes: Int64
    var segments: [Segment]
    var resumable: Bool
    var status: DownloadStatus
    var category: FileCategory
    var headers: [String: String]
    var dateAdded: Date
    var dateCompleted: Date?
    var errorMessage: String?
    // Added in 1.1 (optional so older saved lists still load)
    var kind: DownloadKind?
    var videoQuality: String?
}

// MARK: - Observable item shown in the UI (only touched on the main thread)

final class DownloadItem: ObservableObject, Identifiable {
    let id: UUID
    let dateAdded: Date

    @Published var url: String
    @Published var fileName: String
    @Published var directory: String
    @Published var totalBytes: Int64
    @Published var segments: [Segment]
    @Published var resumable: Bool
    @Published var status: DownloadStatus
    @Published var category: FileCategory
    @Published var dateCompleted: Date?
    @Published var errorMessage: String?

    // Live values, not persisted
    @Published var speed: Double = 0
    @Published var connections: Int = 0

    var nameResolved: Bool
    var headers: [String: String]
    let kind: DownloadKind
    var videoQuality: String
    /// How many automatic retries a failing video has used (not saved).
    var videoAttempt = 0
    /// Changes on every start/pause so stale engine events can be ignored.
    var runToken = UUID()

    init(record r: DownloadRecord) {
        id = r.id
        dateAdded = r.dateAdded
        url = r.url
        fileName = r.fileName
        directory = r.directory
        nameResolved = r.nameResolved
        totalBytes = r.totalBytes
        segments = r.segments
        resumable = r.resumable
        status = r.status
        category = r.category
        headers = r.headers
        dateCompleted = r.dateCompleted
        errorMessage = r.errorMessage
        kind = r.kind ?? .file
        videoQuality = r.videoQuality ?? "1080"
    }

    var record: DownloadRecord {
        DownloadRecord(id: id, url: url, fileName: fileName, directory: directory,
                       nameResolved: nameResolved, totalBytes: totalBytes, segments: segments,
                       resumable: resumable, status: status, category: category, headers: headers,
                       dateAdded: dateAdded, dateCompleted: dateCompleted, errorMessage: errorMessage,
                       kind: kind, videoQuality: videoQuality)
    }

    var downloadedBytes: Int64 {
        if status == .completed && totalBytes > 0 { return totalBytes }
        return segments.reduce(0) { $0 + $1.downloaded }
    }

    var progress: Double {
        if status == .completed { return 1 }
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    var eta: TimeInterval? {
        guard speed > 1, totalBytes > 0 else { return nil }
        return Double(max(0, totalBytes - downloadedBytes)) / speed
    }

    var fileURL: URL { URL(fileURLWithPath: directory).appendingPathComponent(fileName) }
    var partURL: URL { URL(fileURLWithPath: directory).appendingPathComponent(fileName + ".odmpart") }
}
