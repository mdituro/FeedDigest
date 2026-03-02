import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    Picker("Style", selection: $appState.settings.summaryStyle) {
                        ForEach(SummaryStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .onChange(of: appState.settings.summaryStyle) { _, _ in
                        appState.persistSettings()
                    }
                }

                Section("Media") {
                    Picker("Display", selection: $appState.settings.mediaDisplayMode) {
                        ForEach(MediaDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .onChange(of: appState.settings.mediaDisplayMode) { _, _ in
                        appState.persistSettings()
                    }
                }

                Section("Timeline") {
                    HStack {
                        Text("Last Checked")
                        Spacer()
                        Text(appState.lastChecked.map { formatDate($0) } ?? "Never")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    Button("Reset Last Checked", role: .destructive) {
                        appState.resetLastChecked()
                    }
                }

                if #unavailable(iOS 26.0) {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple Intelligence Required")
                                    .font(.headline)
                                Text("Digest generation requires iOS 26.0 or later with Apple Intelligence enabled on a supported device.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
