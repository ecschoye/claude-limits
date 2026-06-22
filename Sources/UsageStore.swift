import SwiftUI
import AppKit
import UserNotifications
import Network

@MainActor
@Observable
final class UsageStore {
    private(set) var states: [String: ProviderState] = [:]   // providerID -> state
    var onUpdate: (@MainActor () -> Void)?

    let providers: [UsageProvider] = [ClaudeProvider(), CodexProvider(), OpenRouterProvider()]

    private var loop: Task<Void, Never>?
    private var lastFetch: [String: Date] = [:]
    private var failures: [String: Int] = [:]
    private var wakeObs: NSObjectProtocol?
    private var clockObs: NSObjectProtocol?
    private var lowCreditNotified = false
    private let pathMonitor = NWPathMonitor()

    private let basePoll: UInt64 = 300
    private let minInterval: TimeInterval = 15

    func provider(_ id: String) -> UsageProvider? { providers.first { $0.id == id } }
    func state(_ id: String) -> ProviderState { states[id] ?? .loading }
    func metric(_ providerID: String, _ metricID: String) -> Metric? {
        if case .ok(let ms) = state(providerID) { return ms.first { $0.id == metricID } }
        return nil
    }

    func start() {
        observeWakeAndClock()
        observeConnectivity()
        loop?.cancel()
        loop = Task { [weak self] in await self?.run() }
    }

    // Refetch as soon as connectivity returns (the 15s throttle bounds it).
    private func observeConnectivity() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.refreshAll() }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// Manual refresh of every enabled provider (popup Refresh button).
    func refreshNow() async { await refreshAll() }

    private func run() async {
        while !Task.isCancelled {
            await refreshAll()
            let streak = failures.values.max() ?? 0
            let wait = streak > 0 ? min(basePoll << UInt64(min(streak, 3)), 1800) : basePoll
            try? await Task.sleep(for: .seconds(Double(wait)))
        }
    }

    func refreshAll() async {
        let active = MenuConfig.providers()
        for p in providers where active.contains(p.id) { await refresh(p) }
    }

    func refresh(_ p: UsageProvider) async {
        if let last = lastFetch[p.id] {
            let dt = Date().timeIntervalSince(last)
            if dt >= 0 && dt < minInterval { return }   // throttle; dt<0 (clock back) not throttled
        }
        lastFetch[p.id] = Date()
        var result = await p.fetch()
        if result == .unauthorized { result = await p.fetch() }   // creds re-read inside fetch; one retry
        apply(p.id, result)
    }

    private func apply(_ id: String, _ s: ProviderState) {
        states[id] = s
        switch s {
        case .rateLimited: failures[id, default: 0] += 1   // only 429 backs off
        default: failures[id] = 0                          // network/server errors retry at normal cadence
        }
        checkLowCredit()
        onUpdate?()
    }

    // OpenRouter low-credit local notification, debounced to once per downward crossing.
    private func checkLowCredit() {
        let threshold = NotifyPrefs.threshold
        guard threshold > 0, let m = metric("openrouter", "credits"), let remaining = m.amount else { return }
        if remaining < threshold {
            if !lowCreditNotified { postLowCredit(m.display); lowCreditNotified = true }
        } else {
            lowCreditNotified = false
        }
    }

    private func postLowCredit(_ display: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "OpenRouter credits low"
        content.body = "\(display) remaining"
        center.add(UNNotificationRequest(identifier: "or-low-credit", content: content, trigger: nil))
    }

    private func observeWakeAndClock() {
        wakeObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refreshAll() } }

        clockObs = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refreshAll() } }
    }
    // No deinit: the store is an app-lifetime singleton; observers live as long as the app.
}
