import Foundation

enum BlueskyError: LocalizedError {
    case authFailed(String)
    case timelineFetchFailed(String)
    case noCredentials
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "Bluesky authentication failed: \(msg)"
        case .timelineFetchFailed(let msg): return "Timeline fetch failed: \(msg)"
        case .noCredentials: return "No Bluesky credentials found."
        case .refreshFailed: return "Failed to refresh Bluesky session."
        }
    }
}

struct BlueskySession {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
}

private let blueskyBaseURL = "https://bsky.social/xrpc"

private struct SessionResponse: Decodable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String

    enum CodingKeys: String, CodingKey {
        case did, handle, accessJwt, refreshJwt
    }
}

private struct TimelineResponse: Decodable {
    let feed: [FeedViewPost]
    let cursor: String?
}

private struct FeedViewPost: Decodable {
    let post: PostView
    let reason: ReasonRepost?
}

private struct ReasonRepost: Decodable {
    // $type is "app.bsky.feed.defs#reasonRepost"
    let by: ProfileViewBasic
}

private struct ProfileViewBasic: Decodable {
    let did: String
    let handle: String
    let displayName: String?
}

private struct PostView: Decodable {
    let uri: String
    let cid: String
    let author: ProfileViewBasic
    let record: PostRecord
    let likeCount: Int?
    let repostCount: Int?
    let embed: EmbedView?

    enum CodingKeys: String, CodingKey {
        case uri, cid, author, record, embed
        case likeCount, repostCount
    }
}

private struct PostRecord: Decodable {
    let text: String
    let createdAt: String
    let type: String?

    enum CodingKeys: String, CodingKey {
        case text, createdAt
        case type = "$type"
    }
}

private struct EmbedView: Decodable {
    let type: String?
    let images: [EmbedImage]?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images
    }
}

private struct EmbedImage: Decodable {
    let thumb: String?
    let fullsize: String?
    let alt: String?
}

struct BlueskyService {
    static let shared = BlueskyService()
    private init() {}

    func authenticate(handle: String, appPassword: String) async throws -> BlueskySession {
        guard let url = URL(string: "\(blueskyBaseURL)/com.atproto.server.createSession") else {
            throw BlueskyError.authFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["identifier": handle, "password": appPassword]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
                ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw BlueskyError.authFailed(message)
        }

        let sessionResponse = try JSONDecoder().decode(SessionResponse.self, from: data)
        return BlueskySession(
            did: sessionResponse.did,
            handle: sessionResponse.handle,
            accessJwt: sessionResponse.accessJwt,
            refreshJwt: sessionResponse.refreshJwt
        )
    }

    private func refreshSession(account: SocialAccount) async throws -> String {
        guard let refreshJwt = KeychainService.shared.retrieve(key: "bluesky_refresh_\(account.id)") else {
            throw BlueskyError.refreshFailed
        }
        guard let url = URL(string: "\(blueskyBaseURL)/com.atproto.server.refreshSession") else {
            throw BlueskyError.refreshFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(refreshJwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BlueskyError.refreshFailed
        }

        let sessionResponse = try JSONDecoder().decode(SessionResponse.self, from: data)
        KeychainService.shared.save(key: "bluesky_access_\(account.id)", value: sessionResponse.accessJwt)
        KeychainService.shared.save(key: "bluesky_refresh_\(account.id)", value: sessionResponse.refreshJwt)
        return sessionResponse.accessJwt
    }

    func fetchTimeline(account: SocialAccount, since: Date) async throws -> [Post] {
        guard var token = KeychainService.shared.retrieve(key: "bluesky_access_\(account.id)") else {
            throw BlueskyError.noCredentials
        }

        func doFetch(jwt: String) async throws -> (Data, HTTPURLResponse) {
            guard let url = URL(string: "\(blueskyBaseURL)/app.bsky.feed.getTimeline?limit=100") else {
                throw BlueskyError.timelineFetchFailed("Invalid URL")
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BlueskyError.timelineFetchFailed("Invalid response")
            }
            return (data, httpResponse)
        }

        var (data, httpResponse) = try await doFetch(jwt: token)

        if httpResponse.statusCode == 401 {
            token = try await refreshSession(account: account)
            (data, httpResponse) = try await doFetch(jwt: token)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw BlueskyError.timelineFetchFailed("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let timelineResponse = try decoder.decode(TimelineResponse.self, from: data)

        return timelineResponse.feed.compactMap { feedItem -> Post? in
            let post = feedItem.post
            let record = post.record

            guard let createdAt = parseISO8601(record.createdAt), createdAt > since else { return nil }

            let isRepost = feedItem.reason != nil
            let repostedByHandle = feedItem.reason.map { "@\($0.by.handle)" }

            // Build URL from AT URI: at://did/app.bsky.feed.post/rkey
            let postURL: URL? = {
                let parts = post.uri.components(separatedBy: "/")
                if parts.count >= 5 {
                    let handle = post.author.handle
                    let rkey = parts.last ?? ""
                    return URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)")
                }
                return nil
            }()

            let media: [MediaAttachment] = post.embed?.images?.enumerated().compactMap { idx, img in
                guard let urlStr = img.fullsize ?? img.thumb, let url = URL(string: urlStr) else { return nil }
                return MediaAttachment(
                    id: "\(post.cid)_\(idx)",
                    url: url,
                    previewURL: img.thumb.flatMap { URL(string: $0) },
                    altText: img.alt,
                    type: "image"
                )
            } ?? []

            return Post(
                id: "bluesky_\(post.cid)",
                platform: .bluesky,
                accountHandle: "@\(post.author.handle)",
                displayName: post.author.displayName ?? post.author.handle,
                content: record.text,
                htmlContent: "",
                createdAt: createdAt,
                postURL: postURL,
                mediaAttachments: media,
                boostedByHandle: repostedByHandle,
                likeCount: post.likeCount ?? 0,
                shareCount: post.repostCount ?? 0
            )
        }
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
