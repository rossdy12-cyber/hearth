import SwiftUI

struct AlbumDetailView: View {
    let albumId: String
    @EnvironmentObject private var accounts: AccountStore
    @State private var album: SubsonicAlbumDetail?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let client = accounts.subsonicClient, let album {
                let songs = album.song ?? []
                VStack(spacing: 14) {
                    RemoteImage(url: client.coverURL(album.coverArt, size: 600), placeholderText: album.name)
                        .frame(width: 250, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
                        .padding(.top, 12)
                    Text(album.name ?? "Album")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    if let artist = album.artist {
                        if let artistId = album.artistId {
                            NavigationLink(value: MusicRoute.artist(artistId)) {
                                Text(artist).font(.headline).foregroundStyle(Theme.accent)
                            }
                        } else {
                            Text(artist).font(.headline).foregroundStyle(Theme.accent)
                        }
                    }
                    Text(meta(songs))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    PlayShuffleButtons(songs: songs)
                    TrackList(songs: songs, showArtwork: false, client: client)
                }
                .padding(.bottom, 24)
            } else if let error {
                ErrorBanner(message: error).padding(.top, 40)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: albumId) {
            await load()
        }
    }

    private func meta(_ songs: [SubsonicSong]) -> String {
        var parts: [String] = []
        if let year = album?.year { parts.append(String(year)) }
        parts.append(songs.count == 1 ? "1 song" : "\(songs.count) songs")
        let seconds = songs.reduce(0) { $0 + ($1.duration ?? 0) }
        parts.append("\(seconds / 60) min")
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let client = accounts.subsonicClient else { return }
        do {
            album = try await client.album(albumId)
        } catch {
            if !isCancellation(error) { self.error = error.localizedDescription }
        }
    }
}

struct PlaylistDetailView: View {
    let playlistId: String
    @EnvironmentObject private var accounts: AccountStore
    @State private var playlist: SubsonicPlaylistDetail?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let client = accounts.subsonicClient, let playlist {
                let songs = playlist.entry ?? []
                VStack(spacing: 14) {
                    RemoteImage(url: client.coverURL(playlist.coverArt, size: 600), placeholderText: playlist.name)
                        .frame(width: 250, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
                        .padding(.top, 12)
                    Text(playlist.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Text(songs.count == 1 ? "1 song" : "\(songs.count) songs")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    PlayShuffleButtons(songs: songs)
                    TrackList(songs: songs, showArtwork: true, client: client)
                }
                .padding(.bottom, 24)
            } else if let error {
                ErrorBanner(message: error).padding(.top, 40)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: playlistId) {
            guard let client = accounts.subsonicClient else { return }
            do {
                playlist = try await client.playlist(playlistId)
            } catch {
                if !isCancellation(error) { self.error = error.localizedDescription }
            }
        }
    }
}

struct ArtistDetailView: View {
    let artistId: String
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var audio: AudioPlayer
    @State private var artist: SubsonicArtistDetail?
    @State private var error: String?
    @State private var shuffling = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            if let client = accounts.subsonicClient, let artist {
                VStack(spacing: 16) {
                    RemoteImage(url: client.coverURL(artist.coverArt, size: 500), placeholderText: String(artist.name.prefix(1)))
                        .frame(width: 180, height: 180)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
                        .padding(.top, 12)
                    Text(artist.name)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await shuffleAll(client) }
                    } label: {
                        PillLabel(title: shuffling ? "Loading…" : "Shuffle Artist", systemImage: "shuffle")
                    }
                    .buttonStyle(.plain)
                    .disabled(shuffling)
                    .padding(.horizontal, 48)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(artist.album ?? []) { album in
                            NavigationLink(value: MusicRoute.album(album.id)) {
                                AlbumCard(album: album, client: client, size: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            } else if let error {
                ErrorBanner(message: error).padding(.top, 40)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artistId) {
            guard let client = accounts.subsonicClient else { return }
            do {
                artist = try await client.artist(artistId)
            } catch {
                if !isCancellation(error) { self.error = error.localizedDescription }
            }
        }
    }

    private func shuffleAll(_ client: SubsonicClient) async {
        guard let albums = artist?.album, !albums.isEmpty else { return }
        shuffling = true
        defer { shuffling = false }
        var songs: [SubsonicSong] = []
        for album in albums.prefix(20) {
            if let detail = try? await client.album(album.id) {
                songs += detail.song ?? []
            }
        }
        audio.play(songs.shuffled())
    }
}

struct AllArtistsView: View {
    @EnvironmentObject private var accounts: AccountStore
    @State private var artists: [SubsonicArtist] = []
    @State private var filter = ""

    private var filtered: [SubsonicArtist] {
        let term = filter.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return artists }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        List(filtered) { artist in
            NavigationLink(value: MusicRoute.artist(artist.id)) {
                HStack(spacing: 12) {
                    RemoteImage(url: accounts.subsonicClient?.coverURL(artist.coverArt, size: 120), placeholderText: String(artist.name.prefix(1)))
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    Text(artist.name)
                        .foregroundStyle(.white)
                    Spacer()
                    if let count = artist.albumCount {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .listRowBackground(Theme.background)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .searchable(text: $filter, prompt: "Filter artists")
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if artists.isEmpty {
                artists = (try? await accounts.subsonicClient?.artists()) ?? []
            }
        }
    }
}
