import SwiftUI
import AppKit

enum Keys {
    static let mode = "menubar.mode"
}

// Menu bar display mode.
enum MenuBarMode: String, CaseIterable {
    case fiveHour    // one 5h icon, popup shows 5h
    case sevenDay    // one 7d icon, popup shows 7d
    case separate    // two icons, each popup its own window
    case unified     // one 5h icon, popup shows BOTH 5h and 7d
}

@main
struct ClaudeLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }   // menu bar items + settings window managed in AppKit
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(store: store)
        store.start()
    }
}

@MainActor
final class MenuBarController {
    // statusID = the menu bar item; barWindow = which window's % shows on the icon;
    // popupWindows = which window rows the popover shows.
    private struct ItemDef { let statusID: String; let caption: String; let barWindow: String; let popupWindows: [String] }

    private let store: UsageStore
    private var items: [String: NSStatusItem] = [:]
    private var popovers: [String: NSPopover] = [:]
    private var defs: [String: ItemDef] = [:]
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

    private var mode: MenuBarMode {
        MenuBarMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .fiveHour
    }

    private func wantedDefs() -> [ItemDef] {
        switch mode {
        case .fiveHour:
            return [ItemDef(statusID: "session", caption: "5h", barWindow: "session", popupWindows: ["session"])]
        case .sevenDay:
            return [ItemDef(statusID: "weekly", caption: "7d", barWindow: "weekly", popupWindows: ["weekly"])]
        case .separate:
            return [
                ItemDef(statusID: "session", caption: "5h", barWindow: "session", popupWindows: ["session"]),
                ItemDef(statusID: "weekly",  caption: "7d", barWindow: "weekly",  popupWindows: ["weekly"]),
            ]
        case .unified:
            return [ItemDef(statusID: "session", caption: "5h", barWindow: "session", popupWindows: ["session", "weekly"])]
        }
    }

    private func syncItems() {
        let wanted = wantedDefs()
        let wantedIDs = Set(wanted.map { $0.statusID })

        for id in Array(items.keys) where !wantedIDs.contains(id) {
            if let item = items[id] { NSStatusBar.system.removeStatusItem(item) }
            items[id] = nil; popovers[id] = nil; defs[id] = nil
        }

        for d in wanted {
            defs[d.statusID] = d
            if items[d.statusID] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(togglePopover(_:))
                item.button?.identifier = NSUserInterfaceItemIdentifier(d.statusID)
                items[d.statusID] = item
            }
            // Rebuild the popover so its window set matches the current mode (cheap).
            let pop = NSPopover()
            pop.behavior = .transient
            pop.contentViewController = NSHostingController(rootView:
                PopupView(store: store, windowIDs: d.popupWindows,
                          onOpenSettings: { [weak self] in self?.openSettings() }))
            popovers[d.statusID] = pop
        }
        updateImages()
    }

    private func updateImages() {
        for (id, item) in items {
            guard let button = item.button, let d = defs[id] else { continue }
            let v = value(for: d.barWindow)
            button.image = Self.render(caption: d.caption, value: v)
            button.imagePosition = .imageOnly
            button.toolTip = "Claude \(d.caption): \(v)"
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
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            win.contentViewController = host
            win.title = "Claude Limits Settings"
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        guard let win = settingsWindow else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            guard let screen = NSScreen.main else { return }
            let f = win.frame, vis = screen.visibleFrame
            win.setFrameOrigin(NSPoint(x: vis.midX - f.width / 2, y: vis.midY - f.height / 2))
        }
    }

    @MainActor
    static func render(caption: String, value: String) -> NSImage {
        let content = VStack(spacing: -1) {
            Text(caption).font(.system(size: 8))
            Text(value).font(.system(size: 11, weight: .bold)).monospacedDigit()
        }
        .fixedSize()
        .foregroundStyle(.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 22, height: 18))
        image.isTemplate = true
        return image
    }
}
