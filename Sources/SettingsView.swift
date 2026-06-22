import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(Keys.show5h) private var show5h = true
    @AppStorage(Keys.show7d) private var show7d = false
    @AppStorage(ColorPrefs.warnAtKey) private var warnAt = 60
    @AppStorage(ColorPrefs.critAtKey) private var critAt = 85

    var body: some View {
        Form {
            Section("Menu bar icons") {
                // The last enabled icon can't be turned off (else no way back to settings).
                Toggle("Show 5h", isOn: $show5h).disabled(show5h && !show7d)
                Toggle("Show 7d", isOn: $show7d).disabled(show7d && !show5h)
            }

            Section("Colors") {
                Stepper("Yellow at \(warnAt)%", value: $warnAt, in: 1...max(2, critAt - 1))
                Stepper("Red at \(critAt)%", value: $critAt, in: min(99, warnAt + 1)...100)
                ColorPicker("Normal", selection: hexBinding(ColorPrefs.normalKey, ColorPrefs.defaultNormal))
                ColorPicker("Warning", selection: hexBinding(ColorPrefs.warnKey, ColorPrefs.defaultWarn))
                ColorPicker("Critical", selection: hexBinding(ColorPrefs.critKey, ColorPrefs.defaultCrit))
            }

            Section("Startup") {
                LaunchAtLogin()
            }

            Section {
                Button("Quit Claude Limits") { NSApplication.shared.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 460)
    }

    // ColorPicker <-> @AppStorage hex string.
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
        return p.hasPrefix("/Applications/")
            || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled },
                set: { setEnabled($0) }))
                // Block enabling from outside /Applications, but always allow turning OFF
                // an existing registration (e.g. one made before this gate existed).
                .disabled(!inApplications && status != .enabled)

            if !inApplications {
                note("Install to /Applications to enable launch at login.")
            } else if status == .requiresApproval {
                note("Approve in System Settings > General > Login Items.")
            }
            if let errorText {
                note(errorText, color: .orange)
            }
        }
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.caption2).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
