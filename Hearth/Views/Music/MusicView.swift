import SwiftUI

@MainActor
final class MusicModel: ObservableObject {
    @Published var featured: SubsonicAlbum?
    @Published var newest: [SubsonicAlbum] = []
    @Published var recent: [SubsonicAlbum] = []
    @Published var frequent: [SubsonicAlbum] = []
    @Published var random: [SubsonicAlbum] = []
    @Published var playlists: [SubsonicPlaylist] = []
    @Published var artists: [SubsonicArtist] = []
    @Published var error: String?
    @Published var loaded = false

    func load(_ client: SubsonicClient) async {
        do {
            async let newestAlbums = client.albumList("newest")
            async let recentAlbums = client.albumList("recent")
            async let frequentAlbums = client.albumList("frequent")
            async let randomAlbums = client.albumList("random")
            async let playlistList = client.playlists()
            async let artistList = client.artists()
            let (n, r, f, rnd, p, a) = try await (newestAlbums, recentAlbums, frequentAlbums, randomAlbums, playlistList, artistList)
            newest = n
            recent = r
            frequent = f
            random = rnd
            playlists = p
            artists = Array(a.sorted { ($0.albumCount ?? 0) > ($1.albumCount ?? 0) }.prefix(20))
            if featured == nil {
                featured = rnd.first ?? n.first
            }
            error = nil
        } catch {
            if isCancellation(error) { return }
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

/// The Music tab: a featured album, then rows of albums, playlists and artists.
struct MusicView: View {
    @EnvironmentObject private var accounts: AccountStore
    @StateObject private var model = MusicModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let client = accounts.subsonicClient {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            if let featured = model.featured {
                                MusicHero(album: featured, client: client)
                            }
                            if let error = model.error {
                                ErrorBanner(message: error)
                            }
                            AlbumRow(title: "Recently Added", albums: model.newest, client: client)
                            AlbumRow(title: "Recently Played", albums: model.recent, client: client)
                            PlaylistRow(playlists: model.playlists, client: client)
                            ArtistRow(title: "Artists", artists: model.artists, client: client)
                            AlbumRow(title: "Most Played", albums: model.frequent, client: client)
                            AlbumRow(title: "Random Picks", albums: model.random, client: client)
                            if !model.loaded {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 120)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        model.featured = nil
                        await model.load(client)
                    }
                    .task(id: client.session.serverURL + client.session.username) {
                        await model.load(client)
                    }
                } else {
                    SignInPrompt(service: "Navidrome", systemImage: "music.note.house",
                                 message: "Sign in to your Navidrome server to play your music here.")
                }
            }
            .navigationTitle("Music")
            .hearthChrome()
            .musicDestinations()
        }
        .miniPlayerInset()
    }
}

struct MusicHero: View {
    let album: SubsonicAlbum
    let client: SubsonicClient
    @EnvironmentObject private var audio: AudioPlayer

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: client.coverURL(album.coverArt, size: 600))
                .frame(height: 400)
                .frame(maxWidth: .infinity)
                .blur(radius: 40)
                .opacity(0.55)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                }

            VStack(spacing: 12) {
                NavigationLink(value: MusicRoute.album(album.id)) {
                    RemoteImage(url: client.coverURL(album.coverArt, size: 600), placeholderText: album.title)
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
                }
                .buttonStyle(.plain)
                Text(album.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(album.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Button {
                        play(shuffled: false)
                    } label: {
                        PillLabel(title: "Play", systemImage: "play.fill")
                    }
                    Button {
                        play(shuffled: true)
                    } label: {
                        PillLabel(title: "Shuffle", systemImage: "shuffle", prominent: false)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 18)
        }
    }

    private func play(shuffled: Bool) {
        Task {
            guard let detail = try? await client.album(album.id), let songs = detail.song, !songs.isEmpty else { return }
            if shuffled {
                audio.play(songs.shuffled())
            } else {
                audio.play(songs)
            }
        }
    }
}
