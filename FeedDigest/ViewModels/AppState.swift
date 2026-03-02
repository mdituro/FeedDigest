import Foundation
import SwiftUI

@Observable
class AppState {
    var accounts: [SocialAccount] = []
    var currentSummary: DigestSummary?
    var isLoading: Bool = false
    var error: String?
    var settings: AppSettings = AppSettings()
    var lastChecked: Date?

    // Pending Mastodon OAuth state
    private var pendingRegistration: MastodonAppRegistration?

    private let accountsKey = "saved_accounts"
    private let settingsKey = "app_settings"
    private let lastCheckedKey = "last_checked"

    init() {
        loadPersistedState()
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([SocialAccount].self, from: data) {
            accounts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
        if let interval = UserDefaults.standard.object(forKey: lastCheckedKey) as? Double {
            lastChecked = Date(timeIntervalSince1970: interval)
        }
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func persistLastChecked() {
        if let date = lastChecked {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastCheckedKey)
        }
    }

    // MARK: - Digest Generation

    func generateDigest() async {
        guard !accounts.isEmpty else {
            error = "Add at least one account to generate a digest."
            return
        }

        isLoading = true
        error = nil

        let since = lastChecked ?? Date().addingTimeInterval(-8 * 3600)
        var allPosts: [Post] = []

        await withTaskGroup(of: [Post].self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        return try await self.fetchPosts(for: account, since: since)
                    } catch {
                        await MainActor.run { self.error = error.localizedDescription }
                        return []
                    }
                }
            }
            for await posts in group {
                allPosts.append(contentsOf: posts)
            }
        }

        allPosts.sort { $0.createdAt < $1.createdAt }

        guard !allPosts.isEmpty else {
            isLoading = false
            error = "No new posts since \(formatDate(since))."
            return
        }

        do {
            if #available(iOS 26.0, *) {
                let summary = try await SummarizationService.shared.summarize(
                    posts: allPosts,
                    style: settings.summaryStyle,
                    mediaMode: settings.mediaDisplayMode
                )
                currentSummary = summary
            } else {
                isLoading = false
                error = SummarizationError.unavailable.localizedDescription
                return
            }
        } catch {
            self.error = error.localizedDescription
        }

        lastChecked = Date()
        persistLastChecked()
        isLoading = false
    }

    private func fetchPosts(for account: SocialAccount, since: Date) async throws -> [Post] {
        switch account.platform {
        case .mastodon:
            let posts = try await MastodonService.shared.fetchHomeTimeline(
                account: account,
                sinceID: account.lastFetchedPostID
            )
            // Filter by date since we might not have a sinceID
            let filtered = posts.filter { $0.createdAt > since }
            // Update lastFetchedPostID
            if let newest = filtered.max(by: { $0.createdAt < $1.createdAt }) {
                let mastodonID = newest.id.replacingOccurrences(of: "mastodon_", with: "")
                updateLastFetchedID(accountID: account.id, postID: mastodonID)
            }
            return filtered
        case .bluesky:
            return try await BlueskyService.shared.fetchTimeline(account: account, since: since)
        }
    }

    private func updateLastFetchedID(accountID: String, postID: String) {
        if let idx = accounts.firstIndex(where: { $0.id == accountID }) {
            accounts[idx] = SocialAccount(
                id: accounts[idx].id,
                platform: accounts[idx].platform,
                handle: accounts[idx].handle,
                displayName: accounts[idx].displayName,
                instanceURL: accounts[idx].instanceURL,
                lastFetchedPostID: postID
            )
            persistAccounts()
        }
    }

    func resetLastChecked() {
        lastChecked = nil
        UserDefaults.standard.removeObject(forKey: lastCheckedKey)
        for idx in accounts.indices {
            accounts[idx] = SocialAccount(
                id: accounts[idx].id,
                platform: accounts[idx].platform,
                handle: accounts[idx].handle,
                displayName: accounts[idx].displayName,
                instanceURL: accounts[idx].instanceURL,
                lastFetchedPostID: nil
            )
        }
        persistAccounts()
    }

    // MARK: - Mastodon OAuth

    func addMastodonAccount(instanceURL: URL) async throws -> URL {
        let registration = try await MastodonService.shared.registerApp(instanceURL: instanceURL)
        pendingRegistration = registration

        // Store registration in keychain for later retrieval
        if let data = try? JSONEncoder().encode(registration),
           let str = String(data: data, encoding: .utf8) {
            KeychainService.shared.save(key: "mastodon_registration_pending", value: str)
        }

        return MastodonService.shared.authorizationURL(registration: registration)
    }

    func completeMastodonOAuth(callbackURL: URL) async throws {
        guard let registration = pendingRegistration ?? loadPendingRegistration() else {
            throw MastodonError.registrationFailed("No pending OAuth registration found")
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw MastodonError.tokenExchangeFailed("No authorization code in callback URL")
        }

        let token = try await MastodonService.shared.exchangeToken(code: code, registration: registration)
        let (handle, displayName) = try await MastodonService.shared.fetchVerifyCredentials(
            instanceURL: registration.instanceURL,
            token: token
        )

        let accountID = UUID().uuidString
        KeychainService.shared.save(key: "mastodon_token_\(accountID)", value: token)
        KeychainService.shared.delete(key: "mastodon_registration_pending")
        pendingRegistration = nil

        let account = SocialAccount(
            id: accountID,
            platform: .mastodon,
            handle: handle,
            displayName: displayName,
            instanceURL: registration.instanceURL
        )
        accounts.append(account)
        persistAccounts()
    }

    private func loadPendingRegistration() -> MastodonAppRegistration? {
        guard let str = KeychainService.shared.retrieve(key: "mastodon_registration_pending"),
              let data = str.data(using: .utf8),
              let reg = try? JSONDecoder().decode(MastodonAppRegistration.self, from: data) else {
            return nil
        }
        return reg
    }

    // MARK: - Bluesky Auth

    func addBlueskyAccount(handle: String, appPassword: String) async throws {
        let session = try await BlueskyService.shared.authenticate(handle: handle, appPassword: appPassword)
        let accountID = UUID().uuidString

        KeychainService.shared.save(key: "bluesky_access_\(accountID)", value: session.accessJwt)
        KeychainService.shared.save(key: "bluesky_refresh_\(accountID)", value: session.refreshJwt)

        let account = SocialAccount(
            id: accountID,
            platform: .bluesky,
            handle: "@\(session.handle)",
            displayName: session.handle,
            instanceURL: nil
        )
        accounts.append(account)
        persistAccounts()
    }

    // MARK: - Account Removal

    func removeAccount(_ account: SocialAccount) {
        switch account.platform {
        case .mastodon:
            KeychainService.shared.delete(key: "mastodon_token_\(account.id)")
        case .bluesky:
            KeychainService.shared.delete(key: "bluesky_access_\(account.id)")
            KeychainService.shared.delete(key: "bluesky_refresh_\(account.id)")
        }
        accounts.removeAll { $0.id == account.id }
        persistAccounts()
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
