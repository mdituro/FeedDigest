import Foundation

struct MastodonAppRegistration: Codable {
    let instanceURL: URL
    let clientID: String
    let clientSecret: String
    let redirectURI: String
}

struct SocialAccount: Identifiable, Codable {
    let id: String
    let platform: SocialPlatform
    let handle: String          // e.g. "@user@mastodon.social" or "user.bsky.social"
    let displayName: String
    let instanceURL: URL?       // Mastodon only
    var lastFetchedPostID: String?   // Mastodon since_id tracking
}
