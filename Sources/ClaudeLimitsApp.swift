import SwiftUI
import AppKit

@main
struct ClaudeLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }   // agent app; menu bar + settings window managed in AppKit
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

// One NSStatusItem per enabled "provider:metric" icon. Each provider has one shared popover
// (showing all its metrics). Icons follow MenuConfig; the cog opens the Settings window.
@MainActor
final class MenuBarController {
    private let store: UsageStore
    private var items: [String: NSStatusItem] = [:]   // "provider:metric" -> item
    private var popovers: [String: NSPopover] = [:]   // providerID -> popover
    private var settingsWindow: NSWindow?
    private var defaultsObserver: NSObjectProtocol?
    private var lastIcons: [String] = []
    private var clickMonitor: Any?

    init(store: UsageStore) {
        self.store = store
        store.onUpdate = { [weak self] in self?.updateImages() }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.syncItems() } }
        syncItems()
    }
    // No deinit: app-lifetime singleton.

    private func syncItems() {
        let icons = MenuConfig.icons()
        // Only rebuild structure when the icon set changed (color/threshold writes also fire
        // didChangeNotification — those just need a re-render, not a teardown).
        guard icons != lastIcons else { updateImages(); return }
        lastIcons = icons
        let wantedIcons = Set(icons)
        let activeProviders = Set(icons.compactMap { $0.split(separator: ":").first.map(String.init) })

        for id in Array(items.keys) where !wantedIcons.contains(id) {
            if let it = items[id] { NSStatusBar.system.removeStatusItem(it) }
            items[id] = nil
        }
        for pid in Array(popovers.keys) where !activeProviders.contains(pid) {
            if popovers[pid]?.isShown == true { popovers[pid]?.performClose(nil) }
            popovers[pid] = nil
        }
        for pid in activeProviders where popovers[pid] == nil {
            let pop = NSPopover()
            pop.behavior = .transient
            pop.contentViewController = NSHostingController(rootView:
                PopupView(store: store, providerID: pid,
                          onOpenSettings: { [weak self] in self?.openSettings() }))
            popovers[pid] = pop
        }
        for icon in icons where items[icon] == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            it.button?.target = self
            it.button?.action = #selector(togglePopover(_:))
            it.button?.identifier = NSUserInterfaceItemIdentifier(icon)
            items[icon] = it
        }
        updateImages()
    }

    private func updateImages() {
        for (icon, it) in items {
            guard let button = it.button else { continue }
            let parts = icon.split(separator: ":").map(String.init)
            guard parts.count == 2 else { continue }
            let (pid, mid) = (parts[0], parts[1])
            let prov = store.provider(pid)
            let v = value(pid, mid)
            let caption = mid == "credits" ? nil : mid
            button.image = Self.render(logo: prov.flatMap { Self.logo($0.logoAsset) },
                                       tag: tag(pid), caption: caption, value: v)
            button.imagePosition = .imageOnly
            button.toolTip = "\(prov?.displayName ?? pid) \(mid): \(v)"
        }
    }

    private func value(_ pid: String, _ mid: String) -> String {
        switch store.state(pid) {
        case .ok: return store.metric(pid, mid)?.display ?? "--"
        case .loading: return "··"
        default: return "!"
        }
    }

    private func tag(_ pid: String) -> String {
        switch pid { case "claude": return "CC"; case "codex": return "CX"; default: return "OR" }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let icon = button.identifier?.rawValue,
              let pid = icon.split(separator: ":").first.map(String.init),
              let pop = popovers[pid] else { return }
        if pop.isShown {
            closePopovers()
        } else {
            closePopovers()
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            installClickMonitor()   // close on any click outside our app
        }
    }

    private func closePopovers() {
        popovers.values.forEach { if $0.isShown { $0.performClose(nil) } }
        removeClickMonitor()
    }

    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopovers() }
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func openSettings() {
        closePopovers()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            win.contentViewController = host
            win.title = "Claude Limits Settings"
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        guard let win = settingsWindow else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Center on the next tick so the hosting controller has finalized the window size
        // (a freshly created window otherwise centers against its pre-layout frame).
        Task { @MainActor in
            guard let screen = NSScreen.main else { return }
            let f = win.frame, vis = screen.visibleFrame
            win.setFrameOrigin(NSPoint(x: vis.midX - f.width / 2, y: vis.midY - f.height / 2))
        }
    }

    // Monochrome (template) logo from Resources, sized for the menu bar.
    static func logo(_ name: String) -> NSImage? {
        for ext in ["pdf", "png"] {
            if let p = Bundle.main.path(forResource: name, ofType: ext),
               let img = NSImage(contentsOfFile: p) {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }

    static func render(logo: NSImage?, tag: String, caption: String?, value: String) -> NSImage {
        // Top half: name (logo/tag) + window inline. Bottom half: the value (stats style, not bold).
        let content = VStack(spacing: -1) {
            HStack(spacing: 2) {
                if let logo {
                    Image(nsImage: logo).resizable().frame(width: 9, height: 9)
                } else {
                    Text(tag).font(.system(size: 8, weight: .semibold))
                }
                if let caption { Text(caption).font(.system(size: 8)) }
            }
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
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
