import Foundation

struct SummarizedMedia: Identifiable {
    let id: String
    let url: URL
    let previewURL: URL?
    let altText: String?
    let sourcePostURL: URL?
    let platform: SocialPlatform
}

struct SummarySection: Identifiable {
    let id: String
    let title: String
    let content: String
    let relatedPostURLs: [URL]
    let media: [SummarizedMedia]
}

struct BulletItem: Identifiable {
    let id: String
    let text: String
    let url: URL?
    let media: [SummarizedMedia]
}

enum DigestContent {
    case thematic(sections: [SummarySection])
    case bullet(items: [BulletItem])
}

struct DigestSummary {
    let generatedAt: Date
    let postCount: Int
    let platforms: [SocialPlatform]
    let timeRange: ClosedRange<Date>?
    let content: DigestContent
    let allMedia: [SummarizedMedia]
}
