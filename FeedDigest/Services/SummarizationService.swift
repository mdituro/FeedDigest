import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - @Generable output types (iOS 26 structured generation)

@available(iOS 26.0, *)
@Generable
struct ThematicOutput {
    @Guide(description: "3 to 6 sections, each covering a distinct topic or event discussed across the posts")
    var sections: [ThematicSection]

    @Generable
    struct ThematicSection {
        @Guide(description: "Specific title naming the actual topic, event, or subject — not a vague category like 'Technology'")
        var title: String
        @Guide(description: "2 to 4 paragraph summary that names the specific people, products, events, and opinions expressed. Aggregate what multiple posts said about the same subject into a coherent narrative.")
        var content: String
        @Guide(description: "URLs of the posts this section draws from")
        var relatedPostURLs: [String]
    }
}

@available(iOS 26.0, *)
@Generable
struct BulletOutput {
    @Guide(description: "One bullet per distinct topic or event, grouping posts that cover the same subject")
    var bullets: [BulletEntry]

    @Generable
    struct BulletEntry {
        @Guide(description: "Specific, informative bullet naming the actual subject, what happened or was said, and key details — not a vague description")
        var text: String
        @Guide(description: "URL of the most relevant source post")
        var url: String?
    }
}

#endif

// MARK: - Errors

enum SummarizationError: LocalizedError {
    case unavailable
    case assetsUnavailable
    case guardrailTriggered(String)
    case modelError(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Summarization requires iOS 26 or later with Apple Intelligence enabled."
        case .assetsUnavailable:
            return "Apple Intelligence model assets are not yet downloaded. Open Settings → Apple Intelligence & Siri and wait for the model to finish downloading."
        case .guardrailTriggered(let detail):
            return "Apple Intelligence declined to summarize this content (\(detail)). Try resetting Last Checked in Settings to use a shorter time window."
        case .modelError(let msg):
            return "Model error: \(msg)"
        }
    }
}

// MARK: - Service

struct SummarizationService {
    static let shared = SummarizationService()
    private init() {}

    @available(iOS 26.0, *)
    func summarize(
        posts: [Post],
        style: SummaryStyle,
        mediaMode: MediaDisplayMode
    ) async throws -> DigestSummary {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard model.isAvailable else { throw SummarizationError.assetsUnavailable }

        // On-device model context window is small — 40 posts keeps us well within limits
        let cappedPosts = Array(posts.prefix(40))

        let systemInstructions = """
        You are a helpful assistant creating a personal digest of someone's social media timeline.
        Your summaries must be specific and information-dense:
        - Mention the actual topics, names, products, events, and opinions from the posts — not vague categories.
        - Aggregate posts that discuss the same subject into one cohesive summary, showing what different people said about it.
        - Avoid filler phrases like "several users discussed" or "people talked about technology". Instead write what was actually said.
        - If a post links to something or quotes someone, include that detail.
        - Write as if briefing a busy person who wants to know exactly what happened, not just that something happened.
        """

        let promptText = buildPrompt(posts: cappedPosts, style: style)
        let session = LanguageModelSession(model: model, instructions: systemInstructions)

        do {
            switch style {
            case .thematic:
                let response = try await session.respond(
                    to: promptText,
                    generating: ThematicOutput.self
                )
                return makeThematicDigest(from: response.content, posts: cappedPosts)

            case .bullet:
                let response = try await session.respond(
                    to: promptText,
                    generating: BulletOutput.self
                )
                return makeBulletDigest(from: response.content, posts: cappedPosts)
            }
        } catch let genError as LanguageModelSession.GenerationError {
            switch genError {
            case .assetsUnavailable:
                throw SummarizationError.assetsUnavailable
            case .guardrailViolation(let ctx), .refusal(_, let ctx):
                // Retry with a shorter, blander prompt containing only metadata
                return try await retryWithMetadata(
                    posts: cappedPosts, style: style,
                    session: session, detail: ctx.debugDescription
                )
            case .exceededContextWindowSize:
                // Retry with a strict subset of posts
                let fewer = Array(cappedPosts.prefix(15))
                let shorterPrompt = buildPrompt(posts: fewer, style: style)
                let session2 = LanguageModelSession(model: model, instructions: systemInstructions)
                switch style {
                case .thematic:
                    let r = try await session2.respond(to: shorterPrompt, generating: ThematicOutput.self)
                    return makeThematicDigest(from: r.content, posts: fewer)
                case .bullet:
                    let r = try await session2.respond(to: shorterPrompt, generating: BulletOutput.self)
                    return makeBulletDigest(from: r.content, posts: fewer)
                }
            default:
                throw SummarizationError.modelError("\(genError)")
            }
        }
        #else
        throw SummarizationError.unavailable
        #endif
    }

    // MARK: - Retry with metadata-only

    @available(iOS 26.0, *)
    private func retryWithMetadata(
        posts: [Post],
        style: SummaryStyle,
        session: LanguageModelSession,
        detail: String
    ) async throws -> DigestSummary {
        #if canImport(FoundationModels)
        let metaPrompt = buildMetadataPrompt(posts: posts, style: style)
        do {
            switch style {
            case .thematic:
                let r = try await session.respond(to: metaPrompt, generating: ThematicOutput.self)
                return makeThematicDigest(from: r.content, posts: posts)
            case .bullet:
                let r = try await session.respond(to: metaPrompt, generating: BulletOutput.self)
                return makeBulletDigest(from: r.content, posts: posts)
            }
        } catch let genError as LanguageModelSession.GenerationError {
            switch genError {
            case .assetsUnavailable: throw SummarizationError.assetsUnavailable
            default: throw SummarizationError.guardrailTriggered(detail)
            }
        }
        #else
        throw SummarizationError.unavailable
        #endif
    }

    // MARK: - Prompt builders

    private func buildPrompt(posts: [Post], style: SummaryStyle) -> String {
        let lines = posts.map { post in
            let time = ISO8601DateFormatter().string(from: post.createdAt)
            let url = post.postURL?.absoluteString ?? ""
            // 280 chars gives the model enough content to identify specific topics
            let text = String(post.content.prefix(280))
            return "[\(post.platform.rawValue)] \(post.displayName) (@\(post.accountHandle)) at \(time):\n\(text)\n\(url)"
        }.joined(separator: "\n\n")

        switch style {
        case .thematic:
            return """
            Here are \(posts.count) posts from my social media timeline. \
            Group them into 3–6 sections by shared topic or event. \
            For each section, write a specific summary that explains what was actually discussed — \
            include names, products, events, and concrete details. \
            Combine posts about the same subject into one narrative rather than listing them separately.

            Posts:
            \(lines)
            """
        case .bullet:
            return """
            Here are \(posts.count) posts from my social media timeline. \
            Write one bullet per distinct topic or event. \
            Each bullet must be specific: name the actual subject, what was said or happened, \
            and who said it if relevant. Group posts about the same subject into one bullet.

            Posts:
            \(lines)
            """
        }
    }

    private func buildMetadataPrompt(posts: [Post], style: SummaryStyle) -> String {
        let lines = posts.map { post in
            let time = ISO8601DateFormatter().string(from: post.createdAt)
            let url = post.postURL?.absoluteString ?? ""
            return "\(post.accountHandle) [\(post.platform.rawValue)] \(time) \(url)"
        }.joined(separator: "\n")

        switch style {
        case .thematic:
            return "Group these social media post records into thematic sections by account and timing:\n\n\(lines)"
        case .bullet:
            return "List these social media post records as brief bullet points:\n\n\(lines)"
        }
    }

    // MARK: - Digest builders

    @available(iOS 26.0, *)
    private func makeThematicDigest(from output: ThematicOutput, posts: [Post]) -> DigestSummary {
        let postsByURL = postURLLookup(posts)
        let sections = output.sections.map { sec -> SummarySection in
            let urls = sec.relatedPostURLs.compactMap { URL(string: $0) }
            let media = urls.flatMap { url -> [SummarizedMedia] in
                guard let post = postsByURL[url.absoluteString] else { return [] }
                return post.mediaAttachments.map { att in
                    SummarizedMedia(id: att.id, url: att.url, previewURL: att.previewURL,
                                    altText: att.altText, sourcePostURL: post.postURL, platform: post.platform)
                }
            }
            return SummarySection(id: UUID().uuidString, title: sec.title,
                                  content: sec.content, relatedPostURLs: urls, media: media)
        }
        return DigestSummary(
            generatedAt: Date(), postCount: posts.count,
            platforms: Array(Set(posts.map(\.platform))),
            timeRange: timeRange(posts),
            content: .thematic(sections: sections),
            allMedia: collectAllMedia(posts)
        )
    }

    @available(iOS 26.0, *)
    private func makeBulletDigest(from output: BulletOutput, posts: [Post]) -> DigestSummary {
        let postsByURL = postURLLookup(posts)
        let items = output.bullets.map { entry -> BulletItem in
            let url = entry.url.flatMap { URL(string: $0) }
            let media: [SummarizedMedia] = url.flatMap { u in
                postsByURL[u.absoluteString].map { post in
                    post.mediaAttachments.map { att in
                        SummarizedMedia(id: att.id, url: att.url, previewURL: att.previewURL,
                                        altText: att.altText, sourcePostURL: post.postURL, platform: post.platform)
                    }
                }
            } ?? []
            return BulletItem(id: UUID().uuidString, text: entry.text, url: url, media: media)
        }
        return DigestSummary(
            generatedAt: Date(), postCount: posts.count,
            platforms: Array(Set(posts.map(\.platform))),
            timeRange: timeRange(posts),
            content: .bullet(items: items),
            allMedia: collectAllMedia(posts)
        )
    }

    // MARK: - Helpers

    private func postURLLookup(_ posts: [Post]) -> [String: Post] {
        Dictionary(uniqueKeysWithValues: posts.compactMap { post in
            guard let url = post.postURL?.absoluteString else { return nil }
            return (url, post)
        })
    }

    private func timeRange(_ posts: [Post]) -> ClosedRange<Date>? {
        let dates = posts.map(\.createdAt).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        return first...last
    }

    private func collectAllMedia(_ posts: [Post]) -> [SummarizedMedia] {
        posts.flatMap { post in
            post.mediaAttachments.map { att in
                SummarizedMedia(id: att.id, url: att.url, previewURL: att.previewURL,
                                altText: att.altText, sourcePostURL: post.postURL, platform: post.platform)
            }
        }
    }
}
