import Foundation

enum MastodonError: LocalizedError {
    case invalidInstance
    case registrationFailed(String)
    case tokenExchangeFailed(String)
    case timelineFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInstance: return "Invalid Mastodon instance URL."
        case .registrationFailed(let msg): return "App registration failed: \(msg)"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .timelineFetchFailed(let msg): return "Timeline fetch failed: \(msg)"
        }
    }
}

// Non-recursive reblog struct to avoid infinite-size struct
private struct MastodonReblog: Decodable {
    let id: String
    let content: String
    let account: MastodonAccount
    let createdAt: String
    let url: String?
    let mediaAttachments: [MastodonMedia]
    let favouritesCount: Int
    let reblogsCount: Int

    enum CodingKeys: String, CodingKey {
        case id, content, account, url
        case createdAt = "created_at"
        case mediaAttachments = "media_attachments"
        case favouritesCount = "favourites_count"
        case reblogsCount = "reblogs_count"
    }
}

private struct MastodonAccount: Decodable {
    let id: String
    let username: String
    let acct: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id, username, acct
        case displayName = "display_name"
    }
}

private struct MastodonMedia: Decodable {
    let id: String
    let type: String
    let url: String?
    let previewUrl: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, type, url, description
        case previewUrl = "preview_url"
    }
}

private struct MastodonStatus: Decodable {
    let id: String
    let content: String
    let account: MastodonAccount
    let createdAt: String
    let url: String?
    let mediaAttachments: [MastodonMedia]
    let reblog: MastodonReblog?
    let favouritesCount: Int
    let reblogsCount: Int

    enum CodingKeys: String, CodingKey {
        case id, content, account, url, reblog
        case createdAt = "created_at"
        case mediaAttachments = "media_attachments"
        case favouritesCount = "favourites_count"
        case reblogsCount = "reblogs_count"
    }
}

private struct MastodonAppResponse: Decodable {
    let clientId: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }
}

private struct MastodonTokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct MastodonService {
    static let shared = MastodonService()
    private init() {}

    private let redirectURI = "feeddigest://oauth/mastodon"
    private let scopes = "read"

    func registerApp(instanceURL: URL) async throws -> MastodonAppRegistration {
        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/apps"
        guard let url = components.url else { throw MastodonError.invalidInstance }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_name": "FeedDigest",
            "redirect_uris": redirectURI,
            "scopes": scopes,
            "website": "https://github.com/feeddigest"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MastodonError.registrationFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let appResponse = try JSONDecoder().decode(MastodonAppResponse.self, from: data)
        return MastodonAppRegistration(
            instanceURL: instanceURL,
            clientID: appResponse.clientId,
            clientSecret: appResponse.clientSecret,
            redirectURI: redirectURI
        )
    }

    func authorizationURL(registration: MastodonAppRegistration) -> URL {
        var components = URLComponents(url: registration.instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: registration.clientID),
            URLQueryItem(name: "redirect_uri", value: registration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes)
        ]
        return components.url!
    }

    func exchangeToken(code: String, registration: MastodonAppRegistration) async throws -> String {
        var components = URLComponents(url: registration.instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/oauth/token"
        guard let url = components.url else { throw MastodonError.invalidInstance }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": registration.clientID,
            "client_secret": registration.clientSecret,
            "redirect_uri": registration.redirectURI,
            "grant_type": "authorization_code",
            "code": code,
            "scope": scopes
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MastodonError.tokenExchangeFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let tokenResponse = try JSONDecoder().decode(MastodonTokenResponse.self, from: data)
        return tokenResponse.accessToken
    }

    func fetchHomeTimeline(account: SocialAccount, sinceID: String?) async throws -> [Post] {
        guard let instanceURL = account.instanceURL else { throw MastodonError.invalidInstance }
        guard let token = KeychainService.shared.retrieve(key: "mastodon_token_\(account.id)") else {
            throw MastodonError.timelineFetchFailed("No access token found")
        }

        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/timelines/home"
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "200")]
        if let sinceID = sinceID {
            queryItems.append(URLQueryItem(name: "since_id", value: sinceID))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw MastodonError.invalidInstance }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MastodonError.timelineFetchFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let decoder = JSONDecoder()
        let statuses = try decoder.decode([MastodonStatus].self, from: data)
        return statuses.map { status in
            let isBoost = status.reblog != nil
            let actual = status.reblog
            let authorHandle = isBoost
                ? "@\(actual!.account.acct)"
                : "@\(status.account.acct)"
            let authorDisplay = isBoost
                ? actual!.account.displayName
                : status.account.displayName
            let rawContent = isBoost ? actual!.content : status.content
            let rawMedia = isBoost ? actual!.mediaAttachments : status.mediaAttachments
            let rawURL = isBoost ? actual!.url : status.url
            let rawCreatedAt = isBoost ? actual!.createdAt : status.createdAt
            let createdAt = parseISO8601(rawCreatedAt) ?? Date()

            let media: [MediaAttachment] = rawMedia.compactMap { m in
                guard let urlStr = m.url, let url = URL(string: urlStr) else { return nil }
                return MediaAttachment(
                    id: m.id,
                    url: url,
                    previewURL: m.previewUrl.flatMap { URL(string: $0) },
                    altText: m.description,
                    type: m.type
                )
            }

            return Post(
                id: "mastodon_\(status.id)",
                platform: .mastodon,
                accountHandle: authorHandle,
                displayName: authorDisplay,
                content: stripHTML(rawContent),
                htmlContent: rawContent,
                createdAt: createdAt,
                postURL: rawURL.flatMap { URL(string: $0) },
                mediaAttachments: media,
                boostedByHandle: isBoost ? "@\(status.account.acct)" : nil,
                likeCount: isBoost ? actual!.favouritesCount : status.favouritesCount,
                shareCount: isBoost ? actual!.reblogsCount : status.reblogsCount
            )
        }
    }

    func fetchVerifyCredentials(instanceURL: URL, token: String) async throws -> (handle: String, displayName: String) {
        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/accounts/verify_credentials"
        guard let url = components.url else { throw MastodonError.invalidInstance }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let account = try JSONDecoder().decode(MastodonAccount.self, from: data)
        return (handle: "@\(account.acct)", displayName: account.displayName)
    }

    func stripHTML(_ html: String) -> String {
        var result = html
        // Replace block-level tags with newlines
        let blockTags = ["</p>", "</div>", "<br>", "<br/>", "<br />", "</li>"]
        for tag in blockTags {
            result = result.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // Remove all remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse multiple newlines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
