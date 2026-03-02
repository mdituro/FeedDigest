import Foundation

enum SocialPlatform: String, Codable {
    case mastodon
    case bluesky
}

struct MediaAttachment: Identifiable, Codable {
    let id: String
    let url: URL
    let previewURL: URL?
    let altText: String?
    let type: String // "image", "video", "gifv", etc.
}

struct Post: Identifiable, Codable {
    let id: String
    let platform: SocialPlatform
    let accountHandle: String
    let displayName: String
    let content: String         // plain text
    let htmlContent: String     // raw HTML (mastodon) or empty
    let createdAt: Date
    let postURL: URL?
    let mediaAttachments: [MediaAttachment]
    let boostedByHandle: String?
    let likeCount: Int
    let shareCount: Int
}
