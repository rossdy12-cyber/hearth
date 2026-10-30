import SwiftUI

/// One search box for both servers: movies and shows from Jellyfin, artists, albums and songs from Navidrome.
struct SearchView: View {
    @EnvironmentObject private var accounts: AccountStore
    @State private var query = ""
    @State private var videos: [JFItem] = []
    @State private var music: SubsonicSearchResult?
    @State private var searching = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !videos.isEmpty || !(music?.artist ?? []).isEmpty || !(music?.album ?? []).isEmpty || !(music?.song ?? []).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if trimmed.count < 2 {
                        hint(icon: "magnifyingglass", text: "Search your movies, shows and music.")
                    } else if searching && !hasResults {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    } else if !hasResults {
                        hint(icon: "questionmark.circle", text: "Nothing found for “\(trimmed)”.")
                    } else {
                        results
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Movies, shows, artists, songs")
            .autocorrectionDisabled()
            .task(id: query) {
                await search()
            }
            .navigationTitle("Search")
            .hearthChrome()
            .jellyfinDestinations()
            .musicDestinations()
        }
        .miniPlayerInset()
    }

    @ViewBuilder private var results: some View {
        if let client = accounts.jellyfinClient, !videos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RowTitle(text: "Movies & TV")
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(videos) { item in
                        NavigationLink(value: item) {
                            PosterCard(url: client.posterURL(item), title: item.title, width: nil, progress: item.progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        if let client = accounts.subsonicClient, let music {
            ArtistRow(title: "Artists", artists: music.artist ?? [], client: client, showSeeAll: false)
            AlbumRow(title: "Albums", albums: music.album ?? [], client: client)
            if let songs = music.song, !songs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    RowTitle(text: "Songs")
                    TrackList(songs: songs, showArtwork: true, client: client)
                }
            }
        }
    }

    private func hint(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text(text)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
        .padding(.horizontal, 32)
    }

    private func search() async {
        let term = trimmed
        guard term.count >= 2 else {
            videos = []
            music = nil
            return
        }
        // Wait for a pause in typing before asking the servers.
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let jellyfin = accounts.jellyfinClient
        let navidrome = accounts.subsonicClient
        async let videoResults: [JFItem] = (try? await jellyfin?.search(term)) ?? []
        async let musicResults: SubsonicSearchResult? = try? await navidrome?.search(term)
        let (foundVideos, foundMusic) = await (videoResults, musicResults)
        guard !Task.isCancelled else { return }
        videos = foundVideos
        music = foundMusic
    }
}
