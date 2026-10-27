import SwiftUI
import AppKit

/// Who made ODM. Shown in Settings → About and in the "About ODM" window.
enum Author {
    static let name = "Nirob Islam"
    static let website = URL(string: "https://www.nirobislam.com/en/")!
    static let facebook = URL(string: "https://www.facebook.com/mdnurunnabiislamniroob")!
    static let instagram = URL(string: "https://www.instagram.com/niru_bhai_0/")!
    static let github = URL(string: "https://github.com/niruvai/odm")!

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    /// The standard macOS About window, with the author and links as credits.
    static func showAboutPanel() {
        let credits = NSMutableAttributedString()
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: center,
        ]
        func add(_ text: String, link: URL? = nil, bold: Bool = false) {
            var attrs = base
            if bold { attrs[.font] = NSFont.boldSystemFont(ofSize: 12) }
            if let link = link { attrs[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attrs))
        }
        add("Open Source Download Manager\n")
        add("Made by \(name)\n\n", bold: true)
        add("Website", link: website)
        add("  ·  ")
        add("Facebook", link: facebook)
        add("  ·  ")
        add("Instagram", link: instagram)
        add("  ·  ")
        add("GitHub", link: github)

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "ODM",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 \(name). MIT License.",
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// Settings → About
struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)

            VStack(spacing: 3) {
                Text("ODM")
                    .font(.title.weight(.bold))
                Text("Open Source Download Manager")
                    .foregroundStyle(.secondary)
                Text("Version \(Author.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                Text("Made by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Author.name)
                    .font(.title3.weight(.semibold))
            }

            HStack(spacing: 10) {
                linkButton("Website", "globe", Author.website)
                linkButton("Facebook", "person.2.fill", Author.facebook)
                linkButton("Instagram", "camera.fill", Author.instagram)
                linkButton("GitHub", "chevron.left.forwardslash.chevron.right", Author.github)
            }

            Text("© 2026 \(Author.name). Released under the MIT License — keep this notice and the author's name when you share or modify ODM.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linkButton(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: symbol)
        }
        .help(url.absoluteString)
    }
}
