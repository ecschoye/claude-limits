import SwiftUI
import ServiceManagement

struct PopupView: View {
    let store: UsageStore
    @AppStorage("show.session") private var showSession = true
    @AppStorage("show.weekly") private var showWeekly = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .ok(let windows):
                ForEach(visible(windows)) { w in WindowRow(window: w) }
                if visible(windows).isEmpty {
                    Text("All windows hidden — enable one below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .loading:
                Label("Loading…", systemImage: "hourglass").foregroundStyle(.secondary)
            default:
                ProblemRow(state: store.state)
            }

            Divider()
            Toggle("5-hour session", isOn: $showSession).toggleStyle(.checkbox)
            Toggle("Weekly", isOn: $showWeekly).toggleStyle(.checkbox)

            Divider()
            FooterView(store: store)
        }
        .padding(14)
        .frame(width: 260)
        .task { await store.refresh() }   // refresh whenever the popup opens
    }

    private func visible(_ windows: [UsageWindow]) -> [UsageWindow] {
        windows.filter {
            ($0.id == "session" && showSession) || ($0.id == "weekly" && showWeekly)
        }
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

private struct FooterView: View {
    let store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isInstalled {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
            } else {
                Text("Move to /Applications to enable launch at login.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh") { Task { await store.refresh() } }
                Spacer()
                if let updated = store.lastUpdated {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text("updated \(formatRemaining(Int(ctx.date.timeIntervalSince(updated)))) ago")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var isInstalled: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            // revert the toggle to the real system state on failure
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
