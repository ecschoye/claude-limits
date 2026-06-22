import SwiftUI
import AppKit

// One popup per provider: shows all of that provider's metrics + a gear to open Settings.
struct PopupView: View {
    let store: UsageStore
    let providerID: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.provider(providerID)?.displayName ?? providerID)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            switch store.state(providerID) {
            case .ok(let metrics):
                let primary = metrics.filter { $0.resetsAt != nil || $0.id == "credits" }
                let spend = metrics.filter { $0.resetsAt == nil && $0.id != "credits" }
                ForEach(primary) { MetricRow(metric: $0) }
                if !spend.isEmpty {
                    Divider()
                    Text("Activity").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(spend) { SpendRow(metric: $0) }
                }
            case .loading:
                Label("Loading…", systemImage: "hourglass").foregroundStyle(.secondary)
            default:
                ProblemRow(state: store.state(providerID))
            }

            Divider()
            HStack {
                Button { Task { await store.refreshNow() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh")
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

private struct MetricRow: View {
    let metric: Metric
    private var tint: Color {
        metric.id == "credits" ? creditColor(metric.amount) : color(metric.percentUsed)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(metric.display).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            }
            if let reset = metric.resetsAt {
                // Usage window: bar + reset countdown. (Credits show just the amount above.)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(color(metric.percentUsed))
                            .frame(width: geo.size.width * Double(min(metric.percentUsed, 100)) / 100)
                    }
                }
                .frame(height: 6)
                Countdown(date: reset)
            }
        }
    }
}

private struct SpendRow: View {
    let metric: Metric
    var body: some View {
        HStack {
            Text(metric.label).font(.system(size: 12))
            Spacer()
            Text(metric.display).font(.system(size: 12, weight: .medium))
                .monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

private struct Countdown: View {
    let date: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text("resets in \(formatRemaining(Int(date.timeIntervalSince(ctx.date))))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ProblemRow: View {
    let state: ProviderState
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var message: String {
        switch state {
        case .noAuth:        return "No credentials found. Sign in to the CLI / set the key."
        case .expired:       return "Token expired — run the CLI to refresh."
        case .unauthorized:  return "Unauthorized (401). Re-auth in the CLI."
        case .rateLimited:   return "Rate limited (429). Backing off."
        case .schemaMismatch: return "API shape changed — needs an app update."
        case .serverError(let c): return "Server error (\(c)). Retrying."
        case .networkError(let m): return "Network error: \(m)"
        default: return "Unavailable."
        }
    }
}
