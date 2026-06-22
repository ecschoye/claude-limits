import SwiftUI
import AppKit

// User-customizable tier thresholds + colors. Credits color by % used, so a near-empty
// balance (high % used) goes red automatically.
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

func color(_ percent: Int) -> Color {
    let warn = min(ColorPrefs.warnAt, ColorPrefs.critAt - 1)   // guard against inverted thresholds
    switch percent {
    case ..<warn: return ColorPrefs.normal
    case ..<ColorPrefs.critAt: return ColorPrefs.warn
    default: return ColorPrefs.crit
    }
}

// Credit balance colored by remaining $ (low = red). ponytail: fixed thresholds for now,
// make them user-configurable if asked.
func creditColor(_ amount: Double?) -> Color {
    guard let a = amount else { return ColorPrefs.normal }
    if a < 5 { return ColorPrefs.crit }
    if a < 20 { return ColorPrefs.warn }
    return ColorPrefs.normal
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
