import SwiftUI
import AppKit

enum SidebarFilter: Hashable {
    case all, active, completed, unfinished
    case category(FileCategory)
}

struct ContentView: View {
    @EnvironmentObject var manager: DownloadManager
    // View state lives in a shared object instead of @State: on newer macOS SDKs @State is a
    // macro whose plugin ships only with full Xcode, not with the Command Line Tools.
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                table
                if let item = singleSelection {
                    Divider()
                    DetailPanel(item: item)
                }
            }
            .navigationTitle(title)
        }
        .toolbar { toolbarContent }
        .searchable(text: $ui.search, placement: .toolbar, prompt: "Search downloads")
        .sheet(isPresented: $ui.showAdd) {
            AddDownloadView().environmentObject(manager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownload)) { _ in ui.showAdd = true }
        .confirmationDialog("Delete \(selectedItems.count) download(s)?", isPresented: $ui.confirmDelete) {
            Button("Remove from List") { manager.remove(selectedItems, deleteFiles: false); ui.selection.removeAll() }
            Button("Remove and Move Files to Trash", role: .destructive) {
                manager.remove(selectedItems, deleteFiles: true); ui.selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        }
        .dropDestination(for: URL.self) { urls, _ in
            var added = false
            for u in urls where ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
                if manager.add(urlString: u.absoluteString) != nil { added = true }
            }
            return added
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $ui.filter) {
            Section("Downloads") {
                row("All", "tray.full", .all, manager.items.count)
                row("Active", "arrow.down.circle", .active,
                    manager.items.filter { $0.status.isActive || $0.status == .queued }.count)
                row("Unfinished", "hourglass", .unfinished,
                    manager.items.filter { $0.status != .completed }.count)
                row("Completed", "checkmark.circle", .completed,
                    manager.items.filter { $0.status == .completed }.count)
            }
            Section("Categories") {
                ForEach(FileCategory.allCases) { c in
                    row(c.title, c.symbol, .category(c), manager.items.filter { $0.category == c }.count)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ title: String, _ icon: String, _ tag: SidebarFilter, _ count: Int) -> some View {
        Label(title, systemImage: icon)
            .badge(count)
            .tag(tag)
    }

    // MARK: Table

    private var visible: [DownloadItem] {
        manager.items.filter { item in
            let matches: Bool
            switch ui.filter ?? .all {
            case .all: matches = true
            case .active: matches = item.status.isActive || item.status == .queued
            case .completed: matches = item.status == .completed
            case .unfinished: matches = item.status != .completed
            case .category(let c): matches = item.category == c
            }
            guard matches else { return false }
            return ui.search.isEmpty
                || item.fileName.localizedCaseInsensitiveContains(ui.search)
                || item.url.localizedCaseInsensitiveContains(ui.search)
        }
    }

    private var table: some View {
        Table(visible, selection: $ui.selection) {
            TableColumn("File Name") { item in CellView(item: item, kind: .name) }
                .width(min: 200, ideal: 320)
            TableColumn("Size") { item in CellView(item: item, kind: .size) }
                .width(min: 60, ideal: 80)
            TableColumn("Progress") { item in CellView(item: item, kind: .progress) }
                .width(min: 120, ideal: 170)
            TableColumn("Speed") { item in CellView(item: item, kind: .speed) }
                .width(min: 70, ideal: 90)
            TableColumn("Time Left") { item in CellView(item: item, kind: .eta) }
                .width(min: 60, ideal: 75)
            TableColumn("Status") { item in CellView(item: item, kind: .status) }
                .width(min: 90, ideal: 115)
            TableColumn("Added") { item in
                Text(item.dateAdded, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            for item in manager.items where ids.contains(item.id) { manager.open(item) }
        }
        .overlay {
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(manager.items.isEmpty ? "No downloads yet" : "Nothing here")
                        .font(.title3)
                    if manager.items.isEmpty {
                        Text("Press ⌘N to add a link, drop a link onto this window,\nor install the Chrome extension from Settings.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Add Download…") { ui.showAdd = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UUID>) -> some View {
        let picked = manager.items.filter { ids.contains($0.id) }
        if picked.count == 1, let item = picked.first {
            Button(item.status == .completed ? "Open" : "Show Partial File") { manager.open(item) }
            Button("Show in Finder") { manager.reveal(item) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }
            Divider()
        }
        if !picked.isEmpty {
            Button("Resume") { for i in picked { manager.resume(i) } }
            Button("Pause") { for i in picked { manager.pause(i) } }
            Button("Redownload") { for i in picked { manager.redownload(i) } }
            Divider()
            Button("Remove from List") { manager.remove(picked, deleteFiles: false); ui.selection.removeAll() }
            Button("Move Files to Trash", role: .destructive) {
                manager.remove(picked, deleteFiles: true); ui.selection.removeAll()
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { ui.showAdd = true } label: { Label("Add URL", systemImage: "plus") }
                .help("Add a download (⌘N)")
            Button { for i in selectedItems { manager.resume(i) } } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .help("Resume selected")
            .disabled(!selectedItems.contains { [.paused, .failed, .queued].contains($0.status) })
            Button { for i in selectedItems { manager.pause(i) } } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .help("Pause selected")
            .disabled(!selectedItems.contains { $0.status.isActive || $0.status == .queued })
            Button { ui.confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                .help("Delete selected")
                .disabled(selectedItems.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { manager.resumeAll() } label: { Label("Resume All", systemImage: "forward.fill") }
                .help("Resume all unfinished downloads")
            Button { manager.pauseAll() } label: { Label("Pause All", systemImage: "stop.fill") }
                .help("Pause everything")
        }
    }

    // MARK: Helpers

    private var selectedItems: [DownloadItem] {
        manager.items.filter { ui.selection.contains($0.id) }
    }

    private var singleSelection: DownloadItem? {
        guard ui.selection.count == 1 else { return nil }
        return manager.items.first { ui.selection.contains($0.id) }
    }

    private var title: String {
        switch ui.filter ?? .all {
        case .all: return "All Downloads"
        case .active: return "Active"
        case .completed: return "Completed"
        case .unfinished: return "Unfinished"
        case .category(let c): return c.title
        }
    }
}

// MARK: - Table cells (each observes its own item so rows update live)

enum CellKind { case name, size, progress, speed, eta, status }

struct CellView: View {
    @ObservedObject var item: DownloadItem
    let kind: CellKind

    var body: some View {
        switch kind {
        case .name:
            HStack(spacing: 6) {
                Image(nsImage: FileIcon.icon(for: item.fileName))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(item.url)

        case .size:
            Text(Fmt.bytes(item.totalBytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)

        case .progress:
            HStack(spacing: 6) {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .tint(item.status.color)
                Text(progressText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }

        case .speed:
            Text(item.status == .downloading ? Fmt.speed(item.speed) : "")
                .monospacedDigit()

        case .eta:
            Text(item.status == .downloading ? Fmt.eta(item.eta) : "")
                .monospacedDigit()
                .foregroundStyle(.secondary)

        case .status:
            Label(item.status.label, systemImage: item.status.symbol)
                .foregroundStyle(item.status.color)
                .help(item.errorMessage ?? item.status.label)
        }
    }

    private var progressText: String {
        if item.totalBytes > 0 || item.status == .completed { return "\(Int(item.progress * 100))%" }
        let d = item.downloadedBytes
        return d > 0 ? Fmt.bytes(d) : ""
    }
}

extension DownloadStatus {
    var color: Color {
        switch self {
        case .downloading: return .accentColor
        case .connecting, .queued: return .secondary
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}
