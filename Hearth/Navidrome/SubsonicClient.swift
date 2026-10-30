import CryptoKit
import Foundation

/// Talks to Navidrome through the Subsonic API using token + salt auth:
/// every request carries `u`, `s` (salt) and `t` = md5(password + salt), never the password itself.
final class SubsonicClient: @unchecked Sendable {
    let session: NavidromeSession
    private let salt: String
    private let token: String

    init(session: NavidromeSession) {
        self.session = session
        // One salt per sign-in keeps cover-art URLs stable, so images cache properly.
        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        self.salt = salt
        self.token = Insecure.MD5.hash(data: Data((session.password + salt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func signIn(server: String, username: String, password: String) async throws -> NavidromeSession {
        let session = NavidromeSession(serverURL: ServerAddress.normalize(server), username: username, password: password)
        _ = try await SubsonicClient(session: session).call("ping")
        return session
    }

    func url(_ endpoint: String, _ params: [URLQueryItem] = []) -> URL? {
        let auth = [
            queryItem("u", session.username), queryItem("t", token), queryItem("s", salt),
            queryItem("v", "1.16.1"), queryItem("c", "Hearth"), queryItem("f", "json")
        ]
        return makeURL(base: session.serverURL, path: "/rest/\(endpoint)", query: auth + params)
    }

    private func call(_ endpoint: String, _ params: [URLQueryItem] = []) async throws -> SubsonicPayload {
        guard let url = url(endpoint, params) else { throw APIError.invalidURL }
        let (data, response) = try await httpSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 404 { throw APIError.notTheRightServer("Navidrome") }
            throw APIError.http(http.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(SubsonicEnvelope.self, from: data).response else {
            throw APIError.notTheRightServer("Navidrome")
        }
        guard payload.status == "ok" else {
            if payload.error?.code == 40 || payload.error?.code == 41 { throw APIError.unauthorized }
            throw APIError.server(payload.error?.message ?? "Navidrome returned an error.")
        }
        return payload
    }

    // MARK: - Browsing

    /// type: newest, recent, frequent, random, alphabeticalByName, starred
    func albumList(_ type: String, size: Int = 20) async throws -> [SubsonicAlbum] {
        try await call("getAlbumList2", [queryItem("type", type), queryItem("size", String(size))]).albumList2?.album ?? []
    }

    func artists() async throws -> [SubsonicArtist] {
        let indexes = try await call("getArtists").artists?.index ?? []
        return indexes.flatMap { $0.artist ?? [] }
    }

    func artist(_ id: String) async throws -> SubsonicArtistDetail? {
        try await call("getArtist", [queryItem("id", id)]).artist
    }

    func album(_ id: String) async throws -> SubsonicAlbumDetail? {
        try await call("getAlbum", [queryItem("id", id)]).album
    }

    func playlists() async throws -> [SubsonicPlaylist] {
        try await call("getPlaylists").playlists?.playlist ?? []
    }

    func playlist(_ id: String) async throws -> SubsonicPlaylistDetail? {
        try await call("getPlaylist", [queryItem("id", id)]).playlist
    }

    func search(_ query: String) async throws -> SubsonicSearchResult? {
        try await call("search3", [
            queryItem("query", query), queryItem("artistCount", "10"),
            queryItem("albumCount", "20"), queryItem("songCount", "30")
        ]).searchResult3
    }

    func scrobble(_ songId: String, submission: Bool) async {
        _ = try? await call("scrobble", [queryItem("id", songId), queryItem("submission", submission ? "true" : "false")])
    }

    // MARK: - Media URLs

    func coverURL(_ coverArtId: String?, size: Int) -> URL? {
        guard let coverArtId else { return nil }
        return url("getCoverArt", [queryItem("id", coverArtId), queryItem("size", String(size))])
    }

    private static let nativeFormats: Set<String> = ["mp3", "m4a", "aac", "alac", "flac", "wav", "aif", "aiff", "caf", "mp4", "m4b"]

    /// Formats iOS can't decode (ogg, opus, wma...) are converted to mp3 by Navidrome.
    func streamURL(for song: SubsonicSong) -> URL? {
        var params = [queryItem("id", song.id)]
        if let suffix = song.suffix?.lowercased(), !Self.nativeFormats.contains(suffix) {
            params += [queryItem("format", "mp3"), queryItem("maxBitRate", "320")]
        }
        return url("stream", params)
    }
}
