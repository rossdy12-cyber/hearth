import SwiftUI

enum MusicRoute: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
    case allArtists
}

struct AlbumCard: View {
    let album: SubsonicAlbum
    let client: SubsonicClient
    var size: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RemoteImage(url: client.coverURL(album.coverArt, size: 300), placeholderText: album.title)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(album.artist ?? "")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
    }
}

struct AlbumRow: View {
    let title: String
    let albums: [SubsonicAlbum]
    let client: SubsonicClient

    var body: some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RowTitle(text: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            NavigationLink(value: MusicRoute.album(album.id)) {
                                AlbumCard(album: album, client: client)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct ArtistRow: View {
    let title: String
    let artists: [SubsonicArtist]
    let client: SubsonicClient
    var showSeeAll = true

    var body: some View {
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if showSeeAll {
                        NavigationLink("See All", value: MusicRoute.allArtists)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(artists) { artist in
                            NavigationLink(value: MusicRoute.artist(artist.id)) {
                                VStack(spacing: 6) {
                                    RemoteImage(url: client.coverURL(artist.coverArt, size: 240), placeholderText: String(artist.name.prefix(1)))
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                    Text(artist.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                .frame(width: 100)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct PlaylistRow: View {
    let playlists: [SubsonicPlaylist]
    let client: SubsonicClient

    var body: some View {
        if !playlists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RowTitle(text: "Playlists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(playlists) { playlist in
                            NavigationLink(value: MusicRoute.playlist(playlist.id)) {
                                VStack(alignment: .leading, spacing: 5) {
                                    RemoteImage(url: client.coverURL(playlist.coverArt, size: 300), placeholderText: playlist.name)
                                        .frame(width: 140, height: 140)
                                        .overlay(alignment: .bottomLeading) {
                                            Image(systemName: "music.note.list")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.black)
                                                .padding(6)
                                                .background(Theme.accent, in: Circle())
                                                .padding(6)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Text(playlist.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("\(playlist.songCount ?? 0) songs")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct SongRow: View {
    let song: SubsonicSong
    let number: Int?
    let artworkURL: URL?
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let artworkURL {
                    RemoteImage(url: artworkURL)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Text(number.map { String($0) } ?? "")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .foregroundStyle(isCurrent ? Theme.accent : Color.white)
                        .lineLimit(1)
                    if let artist = song.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                Text(formatTime(Double(song.duration ?? 0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A list of songs; tapping one plays the whole list starting from that song.
struct TrackList: View {
    let songs: [SubsonicSong]
    let showArtwork: Bool
    let client: SubsonicClient
    @EnvironmentObject private var audio: AudioPlayer

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                SongRow(
                    song: song,
                    number: song.track ?? index + 1,
                    artworkURL: showArtwork ? client.coverURL(song.coverArt, size: 120) : nil,
                    isCurrent: audio.current?.id == song.id
                ) {
                    audio.play(songs, startAt: index)
                }
            }
        }
    }
}

struct PlayShuffleButtons: View {
    let songs: [SubsonicSong]
    @EnvironmentObject private var audio: AudioPlayer

    var body: some View {
        HStack(spacing: 12) {
            Button {
                audio.play(songs)
            } label: {
                PillLabel(title: "Play", systemImage: "play.fill")
            }
            Button {
                audio.play(songs.shuffled())
            } label: {
                PillLabel(title: "Shuffle", systemImage: "shuffle", prominent: false)
            }
        }
        .buttonStyle(.plain)
        .disabled(songs.isEmpty)
        .padding(.horizontal, 16)
    }
}
