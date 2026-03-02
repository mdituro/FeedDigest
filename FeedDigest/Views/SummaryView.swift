import SwiftUI

struct SummaryView: View {
    var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoading {
                    LoadingView()
                } else if let summary = appState.currentSummary {
                    DigestContentView(summary: summary, settings: appState.settings)
                } else {
                    EmptyStateView(appState: appState)
                }
            }
            .navigationTitle("FeedDigest")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    generateButton
                }
            }
            .alert("Error", isPresented: .constant(appState.error != nil), actions: {
                Button("OK") { appState.error = nil }
            }, message: {
                Text(appState.error ?? "")
            })
        }
    }

    @ViewBuilder
    private var generateButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                Task { await appState.generateDigest() }
            } label: {
                Label("Generate", systemImage: "sparkles")
            }
            .disabled(appState.isLoading || appState.accounts.isEmpty)
        } else {
            Button {} label: {
                Label("Generate", systemImage: "sparkles")
            }
            .disabled(true)
        }
    }
}

// MARK: - Loading

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Fetching posts and generating digest…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.bubble")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Digest Yet")
                .font(.title2.bold())
            if appState.accounts.isEmpty {
                Text("Add a Mastodon or Bluesky account in the Accounts tab, then tap Generate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else if #available(iOS 26.0, *) {
                Text("Tap Generate to fetch your timeline and create a digest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("Summarization requires iOS 26.0 or later with Apple Intelligence enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding()
    }
}

// MARK: - Digest Content

private struct DigestContentView: View {
    let summary: DigestSummary
    let settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DigestHeaderView(summary: summary)
                Divider()
                switch summary.content {
                case .thematic(let sections):
                    ForEach(sections) { section in
                        SummarySectionView(section: section, settings: settings)
                        if section.id != sections.last?.id {
                            Divider()
                        }
                    }
                case .bullet(let items):
                    BulletListView(items: items, settings: settings)
                }
            }
            .padding()
        }
    }
}

// MARK: - Header

private struct DigestHeaderView: View {
    let summary: DigestSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ForEach(summary.platforms, id: \.self) { platform in
                    Label(platform.rawValue.capitalized,
                          systemImage: platform == .mastodon ? "elephant" : "cloud")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
            }
            Text("\(summary.postCount) posts")
                .font(.headline)
            if let range = summary.timeRange {
                Text("\(formatDate(range.lowerBound)) – \(formatDate(range.upperBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Generated \(formatDate(summary.generatedAt))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Section View

struct SummarySectionView: View {
    let section: SummarySection
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3.bold())
            Text(section.content)
                .font(.body)
                .lineSpacing(4)
            if !section.media.isEmpty {
                MediaGalleryView(media: section.media, mode: settings.mediaDisplayMode)
            }
            if !section.relatedPostURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Referenced posts:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(section.relatedPostURLs, id: \.absoluteString) { url in
                        Link(url.absoluteString, destination: url)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Bullet List

private struct BulletListView: View {
    let items: [BulletItem]
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                BulletItemView(item: item, settings: settings)
            }
        }
    }
}

private struct BulletItemView: View {
    let item: BulletItem
    let settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.body)
                if let url = item.url {
                    Link(destination: url) {
                        Label("View post", systemImage: "arrow.up.right")
                            .font(.caption)
                    }
                }
                if !item.media.isEmpty {
                    MediaGalleryView(media: item.media, mode: settings.mediaDisplayMode)
                }
            }
        }
    }
}

// MARK: - Media Gallery

struct MediaGalleryView: View {
    let media: [SummarizedMedia]
    let mode: MediaDisplayMode
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch mode {
        case .inline:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160))], spacing: 8) {
                ForEach(media) { item in
                    MediaThumbnailView(item: item)
                        .onTapGesture {
                            openURL(item.url)
                        }
                }
            }
        case .linksOnly:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(media) { item in
                    Link(destination: item.url) {
                        Label(item.altText ?? "View media", systemImage: "photo")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct MediaThumbnailView: View {
    let item: SummarizedMedia

    var body: some View {
        AsyncImage(url: item.previewURL ?? item.url) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay { ProgressView() }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: 120, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(item.altText ?? "Media attachment")
    }
}
