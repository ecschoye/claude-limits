import SwiftUI
import AppKit

@MainActor
@Observable
final class UsageStore {
    private(set) var state: FetchState = .loading
    private(set) var lastUpdated: Date?

    private var token: ClaudeToken?
    private var loop: Task<Void, Never>?
    private var failureStreak: UInt64 = 0

    private let basePollSeconds: UInt64 = 300   // 5 min; data moves slowly

    func start() {
        observeWakeAndClock()
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() { loop?.cancel() }

    private func run() async {
        while !Task.isCancelled {
            await refresh()
            let wait = failureStreak > 0
                ? min(basePollSeconds << failureStreak, 1800)   // back off, cap 30 min
                : basePollSeconds
            try? await Task.sleep(for: .seconds(Double(wait)))
        }
    }

    /// Force an immediate refresh (popup open, wake, manual button).
    func refresh() async {
        if needsTokenReload {
            switch Keychain.readToken() {
            case .success(let t): token = t
            case .failure(let e): apply(map(e)); return
            }
        }
        guard let t = token else { apply(.noToken); return }

        let result = await UsageClient.fetch(token: t)
        if result == .unauthorized {
            // CLI may have just rotated the token in the keychain; re-read once and retry.
            if case .success(let fresh) = Keychain.readToken() {
                token = fresh
                apply(await UsageClient.fetch(token: fresh))
                return
            }
        }
        apply(result)
    }

    private var needsTokenReload: Bool {
        guard let token else { return true }
        return Date() >= token.expiresAt
    }

    private func apply(_ s: FetchState) {
        state = s
        switch s {
        case .ok: lastUpdated = Date(); failureStreak = 0
        case .expired, .noToken, .keychainDenied, .unauthorized, .schemaMismatch:
            failureStreak = 0                       // not transient, don't back off
        case .rateLimited, .serverError, .networkError:
            failureStreak = min(failureStreak + 1, 3)
        case .loading: break
        }
    }

    private func map(_ e: KeychainError) -> FetchState {
        switch e {
        case .notFound: return .noToken
        case .accessDenied: return .keychainDenied
        case .malformed, .other: return .schemaMismatch
        }
    }

    private func observeWakeAndClock() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } }

        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }
}
