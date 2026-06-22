# Claude Limits

macOS menu bar app showing your Claude Code **5-hour session** and **weekly** limit
usage + time to reset. Each window is toggleable. Visual nod to exelban/stats.

## How it works

Reads your Claude Code OAuth token from the macOS Keychain (`Claude Code-credentials`,
read-only, never written back) and calls `GET https://api.anthropic.com/api/oauth/usage`
for the real utilization + reset times shown by `claude /usage`.

> **Caveat:** that endpoint and its `anthropic-beta: oauth-2025-04-20` header are
> undocumented / reverse-engineered. They can change on any Claude Code update. The app
> degrades to a labelled error state (expired token, schema changed, etc.) rather than
> showing wrong numbers, but if Anthropic changes the shape it needs an app update.

Token refresh is deliberately not implemented: the access token lives ~8h and your CLI
keeps it fresh. Self-refreshing would risk rotating the shared refresh token and
desyncing the CLI's auth. If the CLI hasn't run in ~8h the app shows "token expired,
run any claude command".

## Build / run

Requires the Xcode Command Line Tools (no full Xcode needed).

```sh
make test     # pure-logic self-test (parse + countdown)
make run      # build the .app and launch it
make install  # copy to /Applications (needed for launch-at-login)
```

The app is a menu-bar agent (no Dock icon). Click the menu bar item for the popup with
per-window bars, reset countdowns, toggles, and a manual refresh.

## Layout

- `Sources/Keychain.swift` — read token from Keychain, typed errors.
- `Sources/Usage.swift` — parse the `/api/oauth/usage` `limits` array, countdown format.
- `Sources/UsageClient.swift` — fetch + classify every outcome into a `FetchState`.
- `Sources/UsageStore.swift` — `@MainActor @Observable` poll loop (5 min), backoff, wake/clock refresh.
- `Sources/PopupView.swift` / `ClaudeLimitsApp.swift` — SwiftUI `MenuBarExtra` UI.
- `Fixtures/usage_response.json` — sanitized response shape for the self-test.
