import SwiftUI
import AppKit

/// The main window's content: the first-run setup screen until all video tools are installed,
/// then the download list.
struct RootView: View {
    @ObservedObject private var tools = YtDlp.shared
    @AppStorage(Prefs.chromeGuideDoneKey) private var guideDone = false

    var body: some View {
        if !tools.setupComplete {
            SetupView()
        } else if !guideDone {
            ChromeGuideView { guideDone = true }
        } else {
            ContentView()
        }
    }
}

/// First-run setup: shows each part being installed, how much has downloaded, and a retry on failure.
struct SetupView: View {
    @ObservedObject private var tools = YtDlp.shared

    private var doneCount: Int {
        tools.steps.filter { $0.state == .done }.count
    }

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            VStack(spacing: 8) {
                Text("Setting up ODM")
                    .font(.largeTitle.weight(.semibold))
                Text("ODM is downloading the parts it needs for video downloads.\nThis happens only once.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                ForEach(tools.steps) { step in
                    SetupRow(step: step)
                    if step.id != tools.steps.last?.id {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
            .frame(maxWidth: 560)

            footer

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { tools.runSetup() }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = tools.setupError, !tools.setupRunning {
            VStack(spacing: 14) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Quit ODM") { NSApplication.shared.terminate(nil) }
                    Button("Try Again") { tools.runSetup() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        } else {
            Text("\(doneCount) of \(tools.steps.count) installed — please keep ODM open")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct SetupRow: View {
    let step: ToolStep

    var body: some View {
        HStack(spacing: 14) {
            icon
                .font(.system(size: 22))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.headline)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            status
                .frame(width: 220, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .downloading, .installing:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch step.state {
        case .waiting:
            Text("Waiting")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .downloading(let got, let total):
            VStack(alignment: .trailing, spacing: 5) {
                if total > 0 {
                    ProgressView(value: min(1, Double(got) / Double(total)))
                        .progressViewStyle(.linear)
                    Text("\(Fmt.bytes(got)) of \(Fmt.bytes(total)) · \(Int(min(1, Double(got) / Double(total)) * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(got > 0 ? "\(Fmt.bytes(got)) downloaded" : "Connecting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.callout)
            }
        case .done:
            Text("Installed")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
