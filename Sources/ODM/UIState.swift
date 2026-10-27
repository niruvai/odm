import Foundation

/// Window and dialog state. Kept in one long-lived object (instead of SwiftUI's @State)
/// because on newer macOS SDKs @State is a macro that only builds with full Xcode.
final class UIState: ObservableObject {
    static let shared = UIState()

    // Main window
    @Published var filter: SidebarFilter? = .all
    @Published var selection = Set<UUID>()
    @Published var showAdd = false
    @Published var search = ""
    @Published var confirmDelete = false

    // Add Download dialog
    @Published var addLinks = ""
    @Published var addFileName = ""
    @Published var addStartNow = true
    @Published var addError: String?
    @Published var addKind = "auto"          // auto / file / video
    @Published var addQuality = Prefs.videoQuality
}
