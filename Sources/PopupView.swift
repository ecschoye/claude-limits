import SwiftUI
import AppKit

// Per-icon popup: shows ONLY this window's detail, plus a gear that opens the settings window.
struct PopupView: View {
    let store: UsageStore
    let windowID: String          // "session" | "weekly"
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.state {
            case .ok(let windows):
                if let w = windows.first(where: { $0.id == windowID }) {
                    WindowRow(window: w)
                } else {
                    Text("No data for this window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .loading:
                Label("Loading…", systemImage: "hourglass").foregroundStyle(.secondary)
            default:
                ProblemRow(state: store.state)
            }

            Divider()
            HStack {
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
            // Custom bar with explicit fills — ProgressView greys out when the popover
            // window isn't key, which made the color appear only on focus.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color(window))
                        .frame(width: geo.size.width * CGFloat(min(window.percent, 100)) / 100)
                }
            }
            .frame(height: 6)
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

// MARK: - Color tiers (user-customizable thresholds + colors)

enum ColorPrefs {
    static let warnAtKey = "color.warnAt"
    static let critAtKey = "color.critAt"
    static let normalKey = "color.normalHex"
    static let warnKey = "color.warnHex"
    static let critKey = "color.critHex"

    static let defaultNormal = "#34C759"
    static let defaultWarn = "#FFCC00"
    static let defaultCrit = "#FF3B30"

    private static var ud: UserDefaults { .standard }
    static var warnAt: Int { ud.object(forKey: warnAtKey) == nil ? 60 : ud.integer(forKey: warnAtKey) }
    static var critAt: Int { ud.object(forKey: critAtKey) == nil ? 85 : ud.integer(forKey: critAtKey) }
    static var normal: Color { Color(hex: ud.string(forKey: normalKey) ?? defaultNormal) ?? .green }
    static var warn: Color { Color(hex: ud.string(forKey: warnKey) ?? defaultWarn) ?? .yellow }
    static var crit: Color { Color(hex: ud.string(forKey: critKey) ?? defaultCrit) ?? .red }
}

// Color by user-configured percent thresholds.
func color(_ w: UsageWindow) -> Color {
    switch w.percent {
    case ..<ColorPrefs.warnAt: return ColorPrefs.normal
    case ..<ColorPrefs.critAt: return ColorPrefs.warn
    default: return ColorPrefs.crit
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}
