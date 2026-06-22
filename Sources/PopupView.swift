import SwiftUI
import ServiceManagement

struct PopupView: View {
    let store: UsageStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSettings {
                SettingsPanel()
            } else {
                content
            }

            Divider()

            HStack {
                IconButton(symbol: "gearshape", help: "Settings", active: showSettings) {
                    showSettings.toggle()
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 260)
        // No refresh on open — the background poll keeps data fresh and the usage endpoint
        // rate-limits aggressively. Use the Refresh button for an explicit (throttled) update.
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .ok(let windows):
            ForEach(windows) { WindowRow(window: $0) }
        case .loading:
            Label("Loading…", systemImage: "hourglass").foregroundStyle(.secondary)
        default:
            ProblemRow(state: store.state)
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
                .foregroundStyle(active ? Color.accentColor : .primary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct SettingsPanel: View {
    @AppStorage(Keys.show5h) private var show5h = true
    @AppStorage(Keys.show7d) private var show7d = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu bar").font(.caption).foregroundStyle(.secondary)
            // Disable turning off the last remaining item (else no menu bar icon is left).
            Toggle("Show 5h", isOn: $show5h).toggleStyle(.checkbox)
                .disabled(show5h && !show7d)
            Toggle("Show 7d", isOn: $show7d).toggleStyle(.checkbox)
                .disabled(show7d && !show5h)
            Divider()
            LaunchAtLogin()
            Divider()
            Button("Quit Claude Limits") { NSApplication.shared.terminate(nil) }
        }
    }
}

private struct LaunchAtLogin: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorText: String?

    private var inApplications: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/")
            || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled },
                set: { setEnabled($0) }))
                .toggleStyle(.checkbox)

            if !inApplications {
                note("Install to /Applications to enable launch at login.")
            } else if status == .requiresApproval {
                note("Approve in System Settings > General > Login Items.")
            }
            if let errorText {
                note(errorText, color: .orange)
            }
        }
        .onAppear { status = SMAppService.mainApp.status }  // re-read each time the panel opens
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)   // wrap, stays readable
    }

    private func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        status = SMAppService.mainApp.status   // authoritative truth, not the requested value
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(window.percent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color(window))
            }
            ProgressView(value: Double(min(window.percent, 100)), total: 100)
                .tint(color(window))
            HStack {
                Text(window.isActive ? "active" : "idle")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let reset = window.resetsAt {
                    Countdown(date: reset)
                } else {
                    Text("reset —").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct Countdown: View {
    let date: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let secs = Int(date.timeIntervalSince(ctx.date))
            Text("resets in \(formatRemaining(secs))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ProblemRow: View {
    let state: FetchState
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var message: String {
        switch state {
        case .expired:        return "Token expired — run any claude command to refresh."
        case .noToken:        return "No Claude Code login found. Run claude first."
        case .keychainDenied: return "Keychain access denied. Grant access in Keychain Access."
        case .unauthorized:   return "Unauthorized (401). Open Claude Code to re-auth."
        case .rateLimited:    return "Rate limited (429). Backing off."
        case .schemaMismatch: return "API shape changed — needs an app update."
        case .serverError(let c): return "Server error (\(c)). Retrying."
        case .networkError(let m): return "Network error: \(m)"
        default: return "Unavailable."
        }
    }
}

// Color from the server's own severity when known, else fall back to a percent threshold.
func color(_ w: UsageWindow) -> Color {
    switch w.severity {
    case .normal: return .green
    case .warning: return .yellow
    case .critical: return .red
    case .unknown:
        switch w.percent {
        case ..<60: return .green
        case 60..<85: return .yellow
        default: return .red
        }
    }
}
