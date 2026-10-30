import SwiftUI

/// Title page: backdrop, synopsis, Play button, seasons and episodes, and similar titles.
struct DetailView: View {
    let item: JFItem
    @EnvironmentObject private var accounts: AccountStore
    @ObservedObject private var playback = VideoPlayback.shared
    @State private var detail: JFItem?
    @State private var seasons: [JFItem] = []
    @State private var seasonId: String?
    @State private var episodes: [JFItem] = []
    @State private var nextUp: JFItem?
    @State private var similar: [JFItem] = []

    private var shown: JFItem { detail ?? item }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let client = accounts.jellyfinClient {
                content(client)
                    .task(id: item.id) {
                        await load(client)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .hearthPlaybackDidStop)) { _ in
                        Task { await load(client) }
                    }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func content(_ client: JellyfinClient) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RemoteImage(url: client.backdropURL(shown))
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.4), .clear, .black], startPoint: .top, endPoint: .bottom)
                    }

                VStack(alignment: .leading, spacing: 12) {
                    if shown.isEpisode, let seriesName = shown.seriesName {
                        Text(seriesName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(shown.title)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    metaLine
                    playSection(client)
                    if let overview = shown.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let genres = shown.genres, !genres.isEmpty {
                        Text("Genres: " + genres.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)

                if shown.isSeries {
                    episodesSection(client)
                }

                PosterRow(title: "More Like This", items: similar, client: client)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var metaLine: some View {
        HStack(spacing: 10) {
            if let year = shown.productionYear {
                Text(String(year))
            }
            if let rating = shown.officialRating {
                Text(rating)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.secondaryText, lineWidth: 1))
            }
            if shown.isSeries, !seasons.isEmpty {
                Text(seasons.count == 1 ? "1 Season" : "\(seasons.count) Seasons")
            } else if let runtime = shown.runtimeText {
                Text(runtime)
            }
            if let score = shown.communityRating {
                Label(String(format: "%.1f", score), systemImage: "star.fill")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryText)
    }

    private var playTarget: JFItem? {
        shown.isSeries ? nextUp : shown
    }

    private var playTitle: String {
        guard let target = playTarget else { return "Play" }
        let resuming = target.resumeTicks > 0 && !target.isPlayed
        let verb = resuming ? "Resume" : "Play"
        if shown.isSeries, let label = target.episodeLabel {
            return "\(verb) \(label)"
        }
        return verb
    }

    private func playSection(_ client: JellyfinClient) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    playback.start(playTarget ?? shown, client: client)
                } label: {
                    PillLabel(title: playTitle, systemImage: "play.fill")
                }
                .disabled(playback.isPreparing)
                Button {
                    RemoteController.shared.offer(playTarget ?? shown)
                } label: {
                    PillLabel(title: "Play on…", systemImage: "tv", prominent: false)
                }
                .frame(maxWidth: 150)
            }
            .buttonStyle(.plain)

            if let progress = playTarget?.progress, !(playTarget?.isPlayed ?? false) {
                ProgressBar(value: progress)
                    .clipShape(Capsule())
            }
        }
    }

    private var currentSeasonName: String {
        seasons.first { $0.id == seasonId }?.title ?? "Season"
    }

    private func episodesSection(_ client: JellyfinClient) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if seasons.count > 1 {
                Menu {
                    ForEach(seasons) { season in
                        Button(season.title) {
                            seasonId = season.id
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(currentSeasonName).font(.headline)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                }
            } else if let only = seasons.first {
                Text(only.title).font(.headline).foregroundStyle(.white)
            }

            ForEach(episodes) { episode in
                EpisodeRow(episode: episode, client: client) {
                    playback.start(episode, client: client)
                }
            }
        }
        .padding(.horizontal, 16)
        .task(id: seasonId) {
            await loadEpisodes(client)
        }
    }

    private func load(_ client: JellyfinClient) async {
        if let fresh = try? await client.item(item.id) {
            detail = fresh
        }
        if shown.isSeries {
            async let seasonList = client.seasons(seriesId: item.id)
            async let next = client.nextUp(seriesId: item.id)
            seasons = (try? await seasonList) ?? []
            nextUp = try? await next
            if seasonId == nil {
                seasonId = nextUp?.seasonId ?? seasons.first?.id
            } else {
                await loadEpisodes(client)
            }
        }
        if similar.isEmpty {
            similar = (try? await client.similar(item.id)) ?? []
        }
    }

    private func loadEpisodes(_ client: JellyfinClient) async {
        guard let seasonId else { return }
        episodes = (try? await client.episodes(seriesId: item.id, seasonId: seasonId)) ?? []
    }
}

struct EpisodeRow: View {
    let episode: JFItem
    let client: JellyfinClient
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    RemoteImage(url: client.landscapeURL(episode))
                        .frame(width: 136, height: 77)
                        .overlay {
                            Image(systemName: "play.circle")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .overlay(alignment: .bottom) {
                            if let progress = episode.progress, !episode.isPlayed {
                                ProgressBar(value: progress)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let runtime = episode.runtimeText {
                            Text(runtime)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    if episode.isPlayed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleLine: String {
        if let number = episode.indexNumber {
            return "\(number). \(episode.title)"
        }
        return episode.title
    }
}
