import SwiftUI
import AppKit

// Shared UserDefaults keys (menu bar items + settings).
enum Keys {
    static let show5h = "menubar.show5h"
    static let show7d = "menubar.show7d"
}

@main
struct ClaudeLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        // Agent app; menu bar items + settings window are managed by AppDelegate (AppKit).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon
        menuBar = MenuBarController(store: store)
        store.start()
    }
}

// One NSStatusItem per enabled window. Each icon has its OWN popover showing only that
// window's detail; the gear in any popover opens the shared settings window.
@MainActor
final class MenuBarController {
    private struct Window { let id: String; let caption: String; let key: String; let defaultOn: Bool }
    private let windows = [
        Window(id: "session", caption: "5h", key: Keys.show5h, defaultOn: true),
        Window(id: "weekly",  caption: "7d", key: Keys.show7d, defaultOn: false),
    ]

    private let store: UsageStore
    private var items: [String: NSStatusItem] = [:]
    private var popovers: [String: NSPopover] = [:]
    private var settingsWindow: NSWindow?
    private var defaultsObserver: NSObjectProtocol?

    init(store: UsageStore) {
        self.store = store
        store.onUpdate = { [weak self] in self?.updateImages() }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.syncItems() } }
        syncItems()
    }

    private func isOn(_ w: Window) -> Bool {
        UserDefaults.standard.object(forKey: w.key) == nil
            ? w.defaultOn
            : UserDefaults.standard.bool(forKey: w.key)
    }

    private func syncItems() {
        for w in windows {
            if isOn(w), items[w.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(togglePopover(_:))
                item.button?.identifier = NSUserInterfaceItemIdentifier(w.id)
                items[w.id] = item

                let pop = NSPopover()
                pop.behavior = .transient
                pop.contentViewController = NSHostingController(rootView:
                    PopupView(store: store, windowID: w.id,
                              onOpenSettings: { [weak self] in self?.openSettings() }))
                popovers[w.id] = pop
            } else if !isOn(w), let item = items[w.id] {
                NSStatusBar.system.removeStatusItem(item)
                items[w.id] = nil
                popovers[w.id] = nil
            }
        }
        updateImages()
    }

    private func updateImages() {
        for w in windows {
            guard let button = items[w.id]?.button else { continue }
            button.image = Self.render(caption: w.caption, value: value(for: w.id))
            button.imagePosition = .imageOnly
            button.toolTip = "Claude \(w.caption): \(value(for: w.id))"
        }
    }

    private func value(for id: String) -> String {
        switch store.state {
        case .ok(let ws): return ws.first { $0.id == id }.map { "\($0.percent)%" } ?? "--"
        case .loading:    return "··"
        default:          return "!"
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let pop = popovers[id] else { return }
        if pop.isShown {
            pop.performClose(sender)
        } else {
            pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openSettings() {
        popovers.values.forEach { if $0.isShown { $0.performClose(nil) } }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: host)
            win.title = "Claude Limits Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.center()   // after ordering front, so it's sized and centers on screen
        NSApp.activate(ignoringOtherApps: true)
    }

    // Render the stacked cell to a template image for the status button.
    @MainActor
    static func render(caption: String, value: String) -> NSImage {
        let content = VStack(spacing: -1) {
            Text(caption).font(.system(size: 8))
            Text(value).font(.system(size: 11, weight: .bold)).monospacedDigit()
        }
        .fixedSize()
        .foregroundStyle(.black)   // template image keys on alpha; color is irrelevant

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 22, height: 18))
        image.isTemplate = true
        return image
    }
}
