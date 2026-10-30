import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    @Published var hero: JFItem?
    @Published var continueWatching: [JFItem] = []
    @Published var latestMovies: [JFItem] = []
    @Published var latestShows: [JFItem] = []
    @Published var genreRows: [JFGenreRow] = []
    @Published var error: String?
    @Published var loaded = false

    func load(_ client: JellyfinClient) async {
        do {
            async let resume = client.resumeItems()
            async let next = client.nextUp(limit: 20)
            async let movies = client.latest(includeTypes: "Movie")
            async let shows = client.latest(includeTypes: "Series")
            async let featured = client.featured(includeTypes: "Movie,Series")
            let (resumeItems, nextItems, movieItems, showItems, featuredItems) = try await (resume, next, movies, shows, featured)
            continueWatching = Self.merge(resume: resumeItems, nextUp: nextItems)
            latestMovies = movieItems
            latestShows = showItems
            if hero == nil {
                hero = featuredItems.first
            }
            error = nil
        } catch {
            if isCancellation(error) { return }
            self.error = error.localizedDescription
        }
        loaded = true
        let rows = await client.genreRows(includeTypes: "Movie,Series", maxRows: 6)
        if !rows.isEmpty {
            genreRows = rows
        }
    }

    func refreshContinueWatching(_ client: JellyfinClient) async {
        async let resume = client.resumeItems()
        async let next = client.nextUp(limit: 20)
        if let lists = try? await (resume, next) {
            continueWatching = Self.merge(resume: lists.0, nextUp: lists.1)
        }
    }

    /// Half-watched titles first, then the next episode of shows you're following.
    static func merge(resume: [JFItem], nextUp: [JFItem]) -> [JFItem] {
        var seen = Set(resume.map { $0.seriesId ?? $0.id })
        var result = resume
        for episode in nextUp {
            let key = episode.seriesId ?? episode.id
            if !seen.contains(key) {
                result.append(episode)
                seen.insert(key)
            }
        }
        return result
    }
}

struct HomeView: View {
    @EnvironmentObject private var accounts: AccountStore
    @StateObject private var model = HomeModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let client = accounts.jellyfinClient {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            if let hero = model.hero {
                                HeroBanner(item: hero, client: client)
                            }
                            if let error = model.error {
                                ErrorBanner(message: error)
                            }
                            ContinueWatchingRow(items: model.continueWatching, client: client)
                            PosterRow(title: "Recently Added Movies", items: model.latestMovies, client: client)
                            PosterRow(title: "Recently Added Shows", items: model.latestShows, client: client)
                            ForEach(model.genreRows) { row in
                                PosterRow(title: row.title, items: row.items, client: client)
                            }
                            if !model.loaded {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 120)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        model.hero = nil
                        await model.load(client)
                    }
                    .task(id: client.session.accessToken) {
                        await model.load(client)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .hearthPlaybackDidStop)) { _ in
                        Task { await model.refreshContinueWatching(client) }
                    }
                } else {
                    SignInPrompt(service: "Jellyfin", systemImage: "film.stack",
                                 message: "Sign in to your Jellyfin server to see your movies and shows here.")
                }
            }
            .hearthChrome()
            .jellyfinDestinations()
        }
        .miniPlayerInset()
    }
}
