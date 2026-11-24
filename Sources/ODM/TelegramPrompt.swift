import SwiftUI
import AppKit

/// The official ODM Telegram channel: updates, announcements and help.
/// Every user sees a one-time invitation the first time the main window opens
/// (after setup), and the link stays in the menus and Settings → About.
enum Telegram {
    static let channel = URL(string: "https://t.me/+LsTZONGm-082MmI1")!
    static let promptShownKey = "telegramPromptShown"

    static func open() {
        NSWorkspace.shared.open(channel)
    }

    /// Shows the invitation once per user. Called when the main window appears.
    static func showPromptIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: promptShownKey) else { return }
        // A short delay so the window finishes opening before the sheet slides down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard !UserDefaults.standard.bool(forKey: promptShownKey) else { return }
            // Don't stack on top of the Add Download dialog; try again next launch.
            guard !UIState.shared.showAdd else { return }
            UserDefaults.standard.set(true, forKey: promptShownKey)
            UIState.shared.showTelegram = true
        }
    }
}

/// The one-time "Join our Telegram channel" popup.
struct TelegramPromptView: View {
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.16, green: 0.63, blue: 0.89))
                    .frame(width: 76, height: 76)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: -2, y: 1)
            }

            VStack(spacing: 8) {
                Text("Join the ODM Telegram Channel")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Get new updates, features and announcements first.\nFacing a problem? Let us know there and we'll help.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                bullet("arrow.down.circle", "Latest releases & update news")
                bullet("sparkles", "New features & bug fixes")
                bullet("questionmark.circle", "Help when something goes wrong")
            }
            .font(.callout)

            HStack(spacing: 12) {
                Button("Maybe Later") { ui.showTelegram = false }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Telegram.open()
                    ui.showTelegram = false
                } label: {
                    Label("Join Channel", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 420)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.primary)
    }
}
