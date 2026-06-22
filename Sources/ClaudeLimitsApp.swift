import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon
        store.start()
    }
}

@main
struct ClaudeLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopupView(store: delegate.store)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let store: UsageStore
    var body: some View {
        switch store.state {
        case .ok(let windows):
            // Show the binding (active) window, falling back to the first.
            if let w = windows.first(where: { $0.isActive }) ?? windows.first {
                Text("\(w.percent)%")
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
        case .loading:
            Image(systemName: "gauge.with.dots.needle.50percent")
        default:
            Image(systemName: "exclamationmark.triangle")
        }
    }
}
