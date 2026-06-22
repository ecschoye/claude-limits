import Foundation

// Minimal assert-based self-test for the pure logic (parse + countdown).
// Run via `make test`. No XCTest, no SwiftUI, no network.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!); failures += 1 }
}

// --- formatRemaining ---
check(formatRemaining(3 * 3600 + 13 * 60) == "3h 13m", "3h13m formatting")
check(formatRemaining(45 * 60) == "45m", "45m formatting")
check(formatRemaining(0) == "now", "zero -> now")
check(formatRemaining(-500) == "now", "negative clamps to now")

// --- parse against the committed fixture ---
let fixture = "Fixtures/usage_response.json"
guard let data = FileManager.default.contents(atPath: fixture) else {
    FileHandle.standardError.write("FAIL: cannot read \(fixture) (run from repo root)\n".data(using: .utf8)!)
    exit(1)
}

guard let windows = UsageParse.parse(data) else {
    FileHandle.standardError.write("FAIL: parse returned nil on valid fixture\n".data(using: .utf8)!)
    exit(1)
}
check(windows.count == 2, "session + weekly only (weekly_scoped skipped), got \(windows.count)")

let session = windows.first { $0.id == "session" }
check(session?.percent == 45, "session percent 45")
check(session?.isActive == true, "session active")
check(session?.resetsAt != nil, "session reset parsed")
check(session?.severity == .normal, "session severity normal")

let weekly = windows.first { $0.id == "weekly" }
check(weekly?.percent == 20, "weekly percent 20")
check(weekly?.isActive == false, "weekly idle")

// --- schema drift -> nil ---
check(UsageParse.parse(Data("{\"nope\":1}".utf8)) == nil, "missing limits -> nil")
check(UsageParse.parse(Data("not json".utf8)) == nil, "garbage -> nil")

if failures == 0 { print("OK: all self-tests passed") } else { print("\(failures) failure(s)"); exit(1) }
