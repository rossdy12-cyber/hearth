import Foundation

struct NavidromeSession: Codable, Equatable, Sendable {
    var serverURL: String
    var username: String
    /// Kept in the Keychain: Subsonic token auth needs it to make a fresh md5(password + salt).
    var password: String
}

struct SubsonicEnvelope: Decodable {
    let response: SubsonicPayload

    enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }
}

/// Every Subsonic call answers with the same wrapper; only the field for that call is filled.
struct SubsonicPayload: Decodable {
    let status: String
    let error: SubsonicErrorBody?
    let albumList2: SubsonicAlbumList?
    let artists: SubsonicArtistIndexes?
    let artist: SubsonicArtistDetail?
    let album: SubsonicAlbumDetail?
    let playlists: SubsonicPlaylists?
    let playlist: SubsonicPlaylistDetail?
    let searchResult3: SubsonicSearchResult?
}

struct SubsonicErrorBody: Decodable {
    let code: Int?
    let message: String?
}

struct SubsonicAlbumList: Decodable {
    let album: [SubsonicAlbum]?
}

struct SubsonicAlbum: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let year: Int?
    let songCount: Int?

    var title: String { name ?? "Unknown album" }
}

struct SubsonicArtistIndexes: Decodable {
    let index: [SubsonicArtistIndex]?
}

struct SubsonicArtistIndex: Decodable {
    let name: String?
    let artist: [SubsonicArtist]?
}

struct SubsonicArtist: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
}

struct SubsonicArtistDetail: Decodable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
    let album: [SubsonicAlbum]?
}

struct SubsonicAlbumDetail: Decodable, Sendable {
    let id: String
    let name: String?
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let year: Int?
    let song: [SubsonicSong]?
}

struct SubsonicSong: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let artist: String?
    let album: String?
    let albumId: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let suffix: String?

    var displayTitle: String { title ?? "Unknown track" }
}

struct SubsonicPlaylists: Decodable {
    let playlist: [SubsonicPlaylist]?
}

struct SubsonicPlaylist: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let songCount: Int?
    let coverArt: String?
}

struct SubsonicPlaylistDetail: Decodable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
    let entry: [SubsonicSong]?
}

struct SubsonicSearchResult: Decodable, Sendable {
    let artist: [SubsonicArtist]?
    let album: [SubsonicAlbum]?
    let song: [SubsonicSong]?
}
