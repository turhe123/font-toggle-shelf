import ServiceManagement
import SwiftUI

/// Settings window: default preview text and size, family activation, launch at login and support link.
struct SettingsView: View {
    @AppStorage("defaultSampleText") private var defaultSampleText = "Handgloves & Quartz 0123"
    @AppStorage("defaultSize") private var defaultSize = 28.0
    @AppStorage("activateWholeFamily") private var activateWholeFamily = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Preview") {
                TextField("Default sample text", text: $defaultSampleText)
                HStack {
                    Slider(value: $defaultSize, in: 8...120) { Text("Default size") }
                    Text("\(Int(defaultSize)) pt").monospacedDigit().frame(width: 50)
                }
            }
            Section("Activation") {
                Toggle("Activate the whole family when one style is activated", isOn: $activateWholeFamily)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    Text("FontToggleShelf is free and open source.")
                    Spacer()
                    Button("Support / Donate ❤️") { DonateLink.open() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription). "
                + "You can manage it in System Settings › General › Login Items."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
