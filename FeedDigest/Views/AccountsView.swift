import SwiftUI

struct AccountsView: View {
    var appState: AppState
    @State private var showAddMastodon = false
    @State private var showAddBluesky = false

    var body: some View {
        NavigationStack {
            List {
                if appState.accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add a Mastodon or Bluesky account to get started.")
                    )
                } else {
                    ForEach(appState.accounts) { account in
                        AccountRowView(account: account)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appState.removeAccount(appState.accounts[index])
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAddMastodon = true
                        } label: {
                            Label("Mastodon", systemImage: "link")
                        }
                        Button {
                            showAddBluesky = true
                        } label: {
                            Label("Bluesky", systemImage: "cloud")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddMastodon) {
                AddMastodonAccountView(appState: appState)
            }
            .sheet(isPresented: $showAddBluesky) {
                AddBlueskyAccountView(appState: appState)
            }
        }
    }
}

private struct AccountRowView: View {
    let account: SocialAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.platform == .mastodon ? "link" : "cloud")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.headline)
                Text(account.handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let instanceURL = account.instanceURL {
                    Text(instanceURL.host() ?? "")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
            Text(account.platform.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}
