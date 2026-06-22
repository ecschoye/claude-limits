import Foundation

// Assert-based self-test for pure logic: countdown + each provider's parser.
// Run via `make test`. No SwiftUI, no network.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!); failures += 1 }
}
func load(_ name: String) -> Data {
    guard let d = FileManager.default.contents(atPath: "Fixtures/\(name)") else {
        FileHandle.standardError.write("FAIL: cannot read Fixtures/\(name) (run from repo root)\n".data(using: .utf8)!)
        exit(1)
    }
    return d
}

// --- formatRemaining ---
check(formatRemaining(3 * 86400 + 21 * 3600 + 46 * 60) == "3d 21h", "days+hours")
check(formatRemaining(3 * 3600 + 13 * 60) == "3h 13m", "h+m")
check(formatRemaining(45 * 60) == "45m", "m only")
check(formatRemaining(0) == "now", "zero")
check(formatRemaining(-500) == "now", "negative clamps")

// --- Claude parser (limits[] shape) ---
if let m = ClaudeProvider.parse(load("usage_response.json")) {
    check(m.count == 2, "claude 2 windows, got \(m.count)")
    check(m.first { $0.id == "5h" }?.percentUsed == 45, "claude 5h 45%")
    check(m.first { $0.id == "7d" }?.percentUsed == 20, "claude 7d 20%")
    check(m.first { $0.id == "5h" }?.resetsAt != nil, "claude reset parsed")
} else { check(false, "claude parse returned nil") }
check(ClaudeProvider.parse(Data("{}".utf8)) == nil, "claude empty -> nil")

// --- Codex parser (rate_limit.primary/secondary) ---
if let m = CodexProvider.parse(load("codex_usage.json")) {
    check(m.count == 2, "codex 2 windows, got \(m.count)")
    check(m.first { $0.id == "5h" }?.percentUsed == 3, "codex 5h 3%")
    check(m.first { $0.id == "7d" }?.percentUsed == 16, "codex 7d 16%")
    check(m.first { $0.id == "5h" }?.resetsAt != nil, "codex reset (epoch) parsed")
} else { check(false, "codex parse returned nil") }
check(CodexProvider.parse(Data("{}".utf8)) == nil, "codex empty -> nil")

// --- OpenRouter parser (data.total_credits/usage) ---
if let m = OpenRouterProvider.parse(load("openrouter_credits.json")) {
    check(m.count == 1, "openrouter 1 metric")
    check(m[0].id == "credits", "openrouter credits metric")
    check(m[0].display == "$20.86", "openrouter remaining $20.86, got \(m[0].display)")
    check(m[0].percentUsed == 93, "openrouter 93% used, got \(m[0].percentUsed)")
    check(m[0].resetsAt == nil, "openrouter no reset")
} else { check(false, "openrouter parse returned nil") }
check(OpenRouterProvider.parse(Data("{}".utf8)) == nil, "openrouter empty -> nil")


// --- OpenRouter activity (daily/weekly/monthly spend) ---
if let m = OpenRouterProvider.parseActivity(load("openrouter_key.json")) {
    check(m.count == 3, "activity 3 rows")
    check(m.first { $0.id == "monthly" }?.display == "$6.92", "monthly $6.92")
} else { check(false, "activity parse nil") }

if failures == 0 { print("OK: all self-tests passed") } else { print("\(failures) failure(s)"); exit(1) }
