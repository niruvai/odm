import SwiftUI
import AppKit
import Combine

// MARK: - One small window per download (like IDM's download progress dialog)

/// Opens, tracks and closes the per-download progress windows.
/// Closing a window only hides it; the download keeps running in the main list.
final class ProgressWindows: NSObject, NSWindowDelegate {
    static let shared = ProgressWindows()

    private var windows: [UUID: NSWindow] = [:]
    private var subscriptions: [UUID: AnyCancellable] = [:]
    private var lastOrigin: NSPoint?

    /// Shows the window for this download (or brings it to the front if already open).
    /// `force` ignores the "show progress windows" setting (used by "Show Progress Window").
    func show(_ item: DownloadItem, force: Bool = false) {
        guard force || Prefs.showProgressWindow else { return }
        if let w = windows[item.id] {
            w.orderFrontRegardless()
            return
        }

        let state = ProgressWindowState()
        let view = DownloadProgressView(item: item, state: state) { [weak self] in
            self?.close(item.id)
        }
        .environmentObject(DownloadManager.shared)

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        window.title = Self.title(for: item)
        window.setContentSize(NSSize(width: 520, height: 300))
        position(window)

        // Keep the title like IDM: "24% file name"
        subscriptions[item.id] = item.objectWillChange
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak window, weak item] _ in
                DispatchQueue.main.async {
                    guard let window = window, let item = item else { return }
                    window.title = Self.title(for: item)
                }
            }

        windows[item.id] = window
        // Appear on top of the browser without stealing focus from it.
        window.orderFrontRegardless()
    }

    func close(_ id: UUID) {
        windows[id]?.close()
    }

    func isOpen(_ id: UUID) -> Bool { windows[id] != nil }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let raw = window.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        windows[id] = nil
        subscriptions[id] = nil
    }

    private static func title(for item: DownloadItem) -> String {
        switch item.status {
        case .completed: return "Download complete — \(item.fileName)"
        case .failed: return "Download failed — \(item.fileName)"
        case .paused: return "Paused — \(item.fileName)"
        default:
            let pct = item.totalBytes > 0 ? "\(Int(item.progress * 100))% " : ""
            return pct + item.fileName
        }
    }

    /// Cascade new windows so several downloads don't sit exactly on top of each other.
    private func position(_ window: NSWindow) {
        if let last = lastOrigin, !windows.isEmpty {
            let next = window.cascadeTopLeft(from: NSPoint(x: last.x, y: last.y))
            lastOrigin = next
        } else {
            window.center()
            let f = window.frame
            lastOrigin = window.cascadeTopLeft(from: NSPoint(x: f.minX, y: f.maxY))
        }
    }
}

/// Per-window UI state (an object instead of @State, so ODM builds without Xcode).
final class ProgressWindowState: ObservableObject {
    @Published var showDetails = UserDefaults.standard.object(forKey: "progressShowDetails") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDetails, forKey: "progressShowDetails") }
    }
}

// MARK: - The window's content

struct DownloadProgressView: View {
    @ObservedObject var item: DownloadItem
    @ObservedObject var state: ProgressWindowState
    @EnvironmentObject var manager: DownloadManager
    let close: () -> Void

    private var done: Bool { item.status == .completed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            infoGrid

            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(done ? .green : (item.status == .failed ? .red : .accentColor))
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
                .padding(.vertical, 2)

            buttons

            if state.showDetails {
                details
            }

            HStack {
                Toggle("Show this window for new downloads", isOn: Binding(
                    get: { Prefs.showProgressWindow },
                    set: { UserDefaults.standard.set($0, forKey: Prefs.showProgressWindowKey) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: FileIcon.icon(for: item.fileName))
                .resizable()
                .frame(width: 36, height: 36)
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
        }
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
            row("Status", statusText, color: statusColor)
            row("File size", Fmt.bytes(item.totalBytes))
            row("Downloaded", downloadedText)
            row("Transfer rate", item.status == .downloading ? orDash(Fmt.speed(item.speed)) : "—")
            row("Time left", item.status == .downloading ? orDash(Fmt.eta(item.eta)) : "—")
            row("Resume capability", resumeText)
            if done {
                row("Saved to", (item.directory as NSString).abbreviatingWithTildeInPath)
            }
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            Button(state.showDetails ? "<< Hide details" : "Show details >>") {
                state.showDetails.toggle()
            }
            Spacer()
            if done {
                Button {
                    manager.open(item)
                } label: {
                    Label("Open", systemImage: "play.rectangle")
                }
                .keyboardShortcut(.defaultAction)
                Button {
                    manager.reveal(item)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                Button("Close") { close() }
            } else {
                switch item.status {
                case .paused, .failed:
                    Button("Resume") { manager.resume(item) }
                        .keyboardShortcut(.defaultAction)
                default:
                    Button("Pause") { manager.pause(item) }
                }
                Button("Cancel") {
                    manager.pause(item)
                    close()
                }
                .help("Stop this download. It stays in the ODM list, where you can resume or delete it.")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start positions and download progress by connections")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            SegmentBar(segments: item.segments, total: item.totalBytes, completed: done)
                .frame(height: 14)

            ConnectionTable(rows: connectionRows)
                .frame(height: 132)
        }
    }

    // MARK: Text

    private var statusText: String {
        switch item.status {
        case .queued: return "Waiting in queue…"
        case .connecting: return item.stage ?? "Connecting…"
        case .downloading: return "Receiving data…"
        case .paused: return "Paused"
        case .completed: return "Download complete"
        case .failed: return item.errorMessage ?? "Failed"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .downloading, .connecting: return .accentColor
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        case .queued: return .secondary
        }
    }

    private var downloadedText: String {
        let d = Fmt.bytes(item.downloadedBytes)
        guard item.totalBytes > 0 else { return d }
        return String(format: "%@  (%.2f %%)", d, item.progress * 100)
    }

    private var resumeText: String {
        if item.kind == .video { return "Yes" }
        if item.totalBytes < 0 && !done { return "—" }
        return item.resumable ? "Yes" : "No"
    }

    private func orDash(_ s: String) -> String { s.isEmpty ? "—" : s }

    /// One row per connection range: how much it has downloaded and what it is doing.
    private var connectionRows: [ConnectionRow] {
        if item.kind == .video {
            let info: String
            switch item.status {
            case .downloading: return [ConnectionRow(n: 1, downloaded: item.downloadedBytes, info: "Receiving video and audio…")]
            case .completed: info = "Complete"
            case .connecting: info = item.stage ?? "Preparing…"
            default: info = item.status.label
            }
            return [ConnectionRow(n: 1, downloaded: item.downloadedBytes, info: info)]
        }
        var activeLeft = item.status == .downloading ? max(item.connections, 0) : 0
        return item.segments.sorted { $0.start < $1.start }.enumerated().map { idx, seg in
            let info: String
            if seg.isComplete {
                info = "Complete"
            } else if activeLeft > 0 {
                info = "Receiving data…"
                activeLeft -= 1
            } else if item.status == .downloading || item.status == .connecting {
                info = "Waiting…"
            } else {
                info = item.status == .paused ? "Paused" : item.status.label
            }
            return ConnectionRow(n: idx + 1, downloaded: seg.downloaded, info: info)
        }
    }
}

struct ConnectionRow: Identifiable {
    let n: Int
    let downloaded: Int64
    let info: String
    var id: Int { n }
}

/// The "N. / Downloaded / Info" list under the segment bar.
struct ConnectionTable: View {
    let rows: [ConnectionRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("N.").frame(width: 34, alignment: .leading)
                Text("Downloaded").frame(width: 120, alignment: .leading)
                Text("Info")
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { r in
                        HStack {
                            Text("\(r.n)").frame(width: 34, alignment: .leading)
                            Text(Fmt.bytes(r.downloaded)).frame(width: 120, alignment: .leading)
                            Text(r.info).foregroundStyle(r.info == "Complete" ? .green : .primary)
                            Spacer()
                        }
                        .font(.caption)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(r.n % 2 == 0 ? Color.secondary.opacity(0.06) : Color.clear)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
