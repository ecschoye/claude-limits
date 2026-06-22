import SwiftUI
import ServiceManagement

struct SettingsView: View {
    // Observe icon-set + threshold changes so toggles reflect live.
    @AppStorage(MenuConfig.key) private var iconsCSV = MenuConfig.defaultIcons
    @AppStorage(ColorPrefs.warnAtKey) private var warnAt = 60
    @AppStorage(ColorPrefs.critAtKey) private var critAt = 85
    @AppStorage("or.threshold") private var threshold = 5.0
    @AppStorage("or.keySource") private var keySource = "zshenv"
    @State private var orKey = KeychainStore.read("openrouter") ?? ""

    private let providers: [(id: String, name: String, metrics: [(id: String, label: String)])] = [
        ("claude", "Claude", [("5h", "5-hour"), ("7d", "Weekly")]),
        ("codex", "Codex", [("5h", "5-hour"), ("7d", "Weekly")]),
        ("openrouter", "OpenRouter", [("credits", "Credits")]),
    ]

    var body: some View {
        Form {
            ForEach(providers, id: \.id) { p in
                Section(p.name) {
                    ForEach(p.metrics, id: \.id) { m in
                        Toggle("Show \(m.label)", isOn: iconBinding("\(p.id):\(m.id)"))
                    }
                    if p.id == "openrouter" {
                        Picker("API key", selection: $keySource) {
                            Text("~/.zshenv").tag("zshenv")
                            Text("Paste key").tag("custom")
                        }
                        if keySource == "custom" {
                            HStack {
                                SecureField("Paste key", text: $orKey)
                                Button("Save") {
                                    KeychainStore.write("openrouter", orKey.trimmingCharacters(in: .whitespaces))
                                }
                            }
                        }
                        Stepper(threshold == 0 ? "Alert: off" : "Alert me when below $\(Int(threshold))",
                                value: $threshold, in: 0...100, step: 1)
                    }
                }
            }

            Section("Colors") {
                Stepper("Yellow at \(warnAt)%", value: $warnAt, in: 1...max(2, critAt - 1))
                Stepper("Red at \(critAt)%", value: $critAt, in: min(99, warnAt + 1)...100)
                ColorPicker("Normal", selection: hexBinding(ColorPrefs.normalKey, ColorPrefs.defaultNormal))
                ColorPicker("Warning", selection: hexBinding(ColorPrefs.warnKey, ColorPrefs.defaultWarn))
                ColorPicker("Critical", selection: hexBinding(ColorPrefs.critKey, ColorPrefs.defaultCrit))
            }

            Section("Startup") { LaunchAtLogin() }
            Section { Button("Quit Claude Limits") { NSApplication.shared.terminate(nil) } }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 520)
    }

    // Toggle an icon on/off, refusing to disable the last remaining one.
    private func iconBinding(_ icon: String) -> Binding<Bool> {
        Binding(
            get: { MenuConfig.isOn(icon) },
            set: { on in
                if !on && MenuConfig.icons() == [icon] { return }
                MenuConfig.toggle(icon, on)
            })
    }

    private func hexBinding(_ key: String, _ fallback: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: UserDefaults.standard.string(forKey: key) ?? fallback) ?? .gray },
            set: { UserDefaults.standard.set($0.hexString, forKey: key) })
    }
}

struct LaunchAtLogin: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorText: String?

    private var inApplications: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled },
                set: { setEnabled($0) }))
                .disabled(!inApplications && status != .enabled)

            if !inApplications {
                note("Install to /Applications to enable launch at login.")
            } else if status == .requiresApproval {
                note("Approve in System Settings > General > Login Items.")
            }
            if let errorText { note(errorText, color: .orange) }
        }
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.caption2).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
