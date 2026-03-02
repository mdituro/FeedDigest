import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        TabView {
            SummaryView(appState: appState)
                .tabItem {
                    Label("Digest", systemImage: "text.bubble")
                }

            AccountsView(appState: appState)
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }

            SettingsView(appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onOpenURL { url in
            // Handle Mastodon OAuth callback
            guard url.scheme == "feeddigest", url.host == "oauth" else { return }
            Task {
                do {
                    try await appState.completeMastodonOAuth(callbackURL: url)
                } catch {
                    appState.error = error.localizedDescription
                }
            }
        }
    }
}
