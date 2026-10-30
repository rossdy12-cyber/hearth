import Foundation

/// Talks to the Jellyfin REST API. Every call after sign-in carries the access token
/// in the `Authorization: MediaBrowser ... Token="..."` header.
final class JellyfinClient: @unchecked Sendable {
    let session: JellyfinSession

    init(session: JellyfinSession) {
        self.session = session
    }

    // MARK: - Auth

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            let key = path[path.count - 1]
            if key.intValue != nil { return key }
            let name = key.stringValue
            return AnyKey(stringValue: name.prefix(1).lowercased() + name.dropFirst())
        }
        return decoder
    }()

    static var deviceId: String {
        let key = "hearth.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static func authorizationHeader(token: String?) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        var value = "MediaBrowser Client=\"Hearth\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"\(version)\""
        if let token {
            value += ", Token=\"\(token)\""
        }
        return value
    }

    static func signIn(server: String, username: String, password: String) async throws -> JellyfinSession {
        let base = ServerAddress.normalize(server)
        guard let url = makeURL(base: base, path: "/Users/AuthenticateByName") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader(token: nil), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let (data, response) = try await httpSession.data(for: request)
        try check(response)
        guard let auth = try? decoder.decode(JFAuthResponse.self, from: data) else {
            throw APIError.notTheRightServer("Jellyfin")
        }
        return JellyfinSession(serverURL: base, username: auth.user.name ?? username, userId: auth.user.id, accessToken: auth.accessToken)
    }

    func logout() async {
        _ = try? await send("/Sessions/Logout", method: "POST")
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        if !(200..<300).contains(http.statusCode) { throw APIError.http(http.statusCode) }
    }

    // MARK: - Requests

    private func send(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = makeURL(base: session.serverURL, path: path, query: query) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.authorizationHeader(token: session.accessToken), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await httpSession.data(for: request)
        try Self.check(response)
        return data
    }

    private func itemsResponse(_ path: String, _ query: [URLQueryItem]) async throws -> JFItemsResponse {
        let data = try await send(path, query: query)
        return try Self.decoder.decode(JFItemsResponse.self, from: data)
    }

    private func items(_ path: String, _ query: [URLQueryItem]) async throws -> [JFItem] {
        try await itemsResponse(path, query).items
    }

    private var user: URLQueryItem { queryItem("userId", session.userId) }
    private static let listFields = queryItem("Fields", "Overview,Genres,PrimaryImageAspectRatio")

    // MARK: - Browsing

    func resumeItems() async throws -> [JFItem] {
        try await items("/Items", [
            user, queryItem("Recursive", "true"), queryItem("Filters", "IsResumable"),
            queryItem("SortBy", "DatePlayed"), queryItem("SortOrder", "Descending"),
            queryItem("IncludeItemTypes", "Movie,Episode"), queryItem("Limit", "20"), Self.listFields
        ])
    }

    func nextUp(limit: Int) async throws -> [JFItem] {
        try await items("/Shows/NextUp", [user, queryItem("Limit", String(limit)), Self.listFields])
    }

    func nextUp(seriesId: String) async throws -> JFItem? {
        try await items("/Shows/NextUp", [user, queryItem("SeriesId", seriesId), queryItem("Limit", "1"), Self.listFields]).first
    }

    func firstEpisode(seriesId: String) async throws -> JFItem? {
        try await items("/Shows/\(seriesId)/Episodes", [user, queryItem("Limit", "1")]).first
    }

    func latest(includeTypes: String, limit: Int = 20) async throws -> [JFItem] {
        try await items("/Items", [
            user, queryItem("Recursive", "true"), queryItem("IncludeItemTypes", includeTypes),
            queryItem("SortBy", "DateCreated,SortName"), queryItem("SortOrder", "Descending"),
            queryItem("Limit", String(limit)), Self.listFields
        ])
    }

    /// Random titles that have a backdrop, used for the big banner at the top.
    func featured(includeTypes: String) async throws -> [JFItem] {
        try await items("/Items", [
            user, queryItem("Recursive", "true"), queryItem("IncludeItemTypes", includeTypes),
            queryItem("SortBy", "Random"), queryItem("ImageTypes", "Backdrop"),
            queryItem("Limit", "10"), Self.listFields
        ])
    }

    func browse(includeTypes: String, genreId: String? = nil, sortBy: String = "SortName",
                descending: Bool = false, start: Int = 0, limit: Int = 40) async throws -> JFItemsResponse {
        var query = [
            user, queryItem("Recursive", "true"), queryItem("IncludeItemTypes", includeTypes),
            queryItem("SortBy", sortBy), queryItem("SortOrder", descending ? "Descending" : "Ascending"),
            queryItem("StartIndex", String(start)), queryItem("Limit", String(limit)), Self.listFields
        ]
        if let genreId {
            query.append(queryItem("GenreIds", genreId))
        }
        return try await itemsResponse("/Items", query)
    }

    func genres(includeTypes: String) async throws -> [JFItem] {
        try await items("/Genres", [
            user, queryItem("IncludeItemTypes", includeTypes),
            queryItem("SortBy", "SortName"), queryItem("Recursive", "true")
        ])
    }

    /// A handful of genre rows ("Comedy", "Drama", ...) with a few random titles in each.
    func genreRows(includeTypes: String, maxRows: Int) async -> [JFGenreRow] {
        guard let all = try? await genres(includeTypes: includeTypes) else { return [] }
        let picked = Array(all.shuffled().prefix(maxRows))
        return await withTaskGroup(of: (Int, JFGenreRow?).self) { group in
            for (index, genre) in picked.enumerated() {
                group.addTask {
                    let found = (try? await self.browse(includeTypes: includeTypes, genreId: genre.id, sortBy: "Random", limit: 20).items) ?? []
                    let row = found.count >= 3 ? JFGenreRow(id: genre.id, title: genre.title, items: found) : nil
                    return (index, row)
                }
            }
            var rows: [(Int, JFGenreRow)] = []
            for await (index, row) in group {
                if let row { rows.append((index, row)) }
            }
            return rows.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    func item(_ id: String) async throws -> JFItem? {
        try await items("/Items", [user, queryItem("Ids", id), Self.listFields]).first
    }

    func seasons(seriesId: String) async throws -> [JFItem] {
        try await items("/Shows/\(seriesId)/Seasons", [user])
    }

    func episodes(seriesId: String, seasonId: String) async throws -> [JFItem] {
        try await items("/Shows/\(seriesId)/Episodes", [user, queryItem("SeasonId", seasonId), queryItem("Fields", "Overview")])
    }

    func similar(_ id: String) async throws -> [JFItem] {
        try await items("/Items/\(id)/Similar", [user, queryItem("Limit", "12")])
    }

    func search(_ term: String) async throws -> [JFItem] {
        try await items("/Items", [
            user, queryItem("SearchTerm", term), queryItem("Recursive", "true"),
            queryItem("IncludeItemTypes", "Movie,Series"), queryItem("Limit", "40"), Self.listFields
        ])
    }

    // MARK: - Remote control ("Play on…")

    private func allSessions() async throws -> [JFSession] {
        let data = try await send("/Sessions", query: [queryItem("ControllableByUserId", session.userId)])
        return try Self.decoder.decode([JFSession].self, from: data)
    }

    /// Other devices that can play video and accept remote commands.
    func controllableSessions() async throws -> [JFSession] {
        try await allSessions().filter {
            $0.deviceId != Self.deviceId
                && ($0.supportsRemoteControl ?? false)
                && ($0.playableMediaTypes ?? []).contains("Video")
        }
    }

    func remoteSession(id: String) async throws -> JFSession? {
        try await allSessions().first { $0.id == id }
    }

    func playOn(sessionId: String, itemIds: [String], startTicks: Int64) async throws {
        _ = try await send("/Sessions/\(sessionId)/Playing", query: [
            queryItem("playCommand", "PlayNow"),
            queryItem("itemIds", itemIds.joined(separator: ",")),
            queryItem("startPositionTicks", String(startTicks))
        ], method: "POST")
    }

    /// command: Pause, Unpause, PlayPause, Stop, Seek, NextTrack, PreviousTrack
    func sendPlaystate(sessionId: String, _ command: String, seekTicks: Int64? = nil) async throws {
        var query: [URLQueryItem] = []
        if let seekTicks {
            query.append(queryItem("seekPositionTicks", String(max(0, seekTicks))))
        }
        _ = try await send("/Sessions/\(sessionId)/Playing/\(command)", query: query, method: "POST")
    }

    /// name: SetVolume, Mute, Unmute, ToggleMute, SetAudioStreamIndex, SetSubtitleStreamIndex, DisplayMessage
    func sendCommand(sessionId: String, _ name: String, arguments: [String: String] = [:]) async throws {
        _ = try await send("/Sessions/\(sessionId)/Command", method: "POST", body: ["Name": name, "Arguments": arguments])
    }

    func itemWithStreams(_ id: String) async throws -> JFItem? {
        try await items("/Items", [user, queryItem("Ids", id), queryItem("Fields", "MediaStreams")]).first
    }

    // MARK: - Images

    func imageURL(_ itemId: String, _ type: String, maxWidth: Int, tag: String? = nil) -> URL? {
        var query = [queryItem("maxWidth", String(maxWidth)), queryItem("quality", "85")]
        if let tag {
            query.append(queryItem("tag", tag))
        }
        return makeURL(base: session.serverURL, path: "/Items/\(itemId)/Images/\(type)", query: query)
    }

    /// Portrait 2:3 poster. Episodes use their show's poster.
    func posterURL(_ item: JFItem) -> URL? {
        if item.isEpisode, let seriesId = item.seriesId {
            return imageURL(seriesId, "Primary", maxWidth: 300)
        }
        return imageURL(item.id, "Primary", maxWidth: 300, tag: item.imageTags?.primary)
    }

    func backdropURL(_ item: JFItem, maxWidth: Int = 1280) -> URL? {
        if let tag = item.backdropImageTags?.first {
            return imageURL(item.id, "Backdrop", maxWidth: maxWidth, tag: tag)
        }
        if let parent = item.parentBackdropItemId {
            return imageURL(parent, "Backdrop", maxWidth: maxWidth)
        }
        if let seriesId = item.seriesId {
            return imageURL(seriesId, "Backdrop", maxWidth: maxWidth)
        }
        return imageURL(item.id, "Primary", maxWidth: maxWidth, tag: item.imageTags?.primary)
    }

    /// Wide 16:9 still, used for Continue Watching and episode lists.
    func landscapeURL(_ item: JFItem) -> URL? {
        if item.isEpisode {
            return imageURL(item.id, "Primary", maxWidth: 520, tag: item.imageTags?.primary)
        }
        if let thumb = item.imageTags?.thumb {
            return imageURL(item.id, "Thumb", maxWidth: 520, tag: thumb)
        }
        return backdropURL(item, maxWidth: 520)
    }

    func logoURL(_ item: JFItem) -> URL? {
        guard let tag = item.imageTags?.logo else { return nil }
        return imageURL(item.id, "Logo", maxWidth: 600, tag: tag)
    }

    // MARK: - Playback

    /// Tells Jellyfin what the iPhone can play. Files that fit are played directly,
    /// anything else is converted by the server into an HLS stream (`master.m3u8`).
    private static let deviceProfile: [String: Any] = [
        "Name": "Hearth for iPhone",
        "MaxStreamingBitrate": 120_000_000,
        "MaxStaticBitrate": 120_000_000,
        "MusicStreamingTranscodingBitrate": 192_000,
        "DirectPlayProfiles": [
            ["Container": "mp4,m4v,mov", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,mp3,ac3,eac3,alac,flac"]
        ] as [[String: Any]],
        "TranscodingProfiles": [
            [
                "Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac,mp3,ac3,eac3",
                "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "6",
                "MinSegments": 1, "BreakOnNonKeyFrames": true
            ] as [String: Any]
        ] as [[String: Any]],
        "SubtitleProfiles": [
            ["Format": "vtt", "Method": "Hls"],
            ["Format": "srt", "Method": "Hls"],
            ["Format": "subrip", "Method": "Hls"],
            ["Format": "ass", "Method": "Hls"],
            ["Format": "ssa", "Method": "Hls"],
            ["Format": "mov_text", "Method": "Embed"]
        ] as [[String: Any]],
        "ContainerProfiles": [[String: Any]](),
        "CodecProfiles": [[String: Any]]()
    ]

    func playbackSource(itemId: String) async throws -> JFPlaybackSource {
        let body: [String: Any] = [
            "UserId": session.userId,
            "MaxStreamingBitrate": 120_000_000,
            "AutoOpenLiveStream": true,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "AllowVideoStreamCopy": true,
            "AllowAudioStreamCopy": true,
            "DeviceProfile": Self.deviceProfile
        ]
        let data = try await send("/Items/\(itemId)/PlaybackInfo", query: [user], method: "POST", body: body)
        let info = try Self.decoder.decode(JFPlaybackInfo.self, from: data)
        guard let source = info.mediaSources.first else {
            throw APIError.server("Jellyfin has no playable file for this title.")
        }
        let playSessionId = info.playSessionId ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let sourceId = source.id ?? itemId

        // 1. Direct play: the file is already something iOS understands.
        if source.supportsDirectPlay == true,
           let url = makeURL(base: session.serverURL, path: "/Videos/\(itemId)/stream.mp4", query: [
            queryItem("static", "true"), queryItem("MediaSourceId", sourceId),
            queryItem("PlaySessionId", playSessionId), queryItem("DeviceId", Self.deviceId),
            queryItem("ApiKey", session.accessToken)
           ]) {
            return JFPlaybackSource(url: url, mediaSourceId: sourceId, playSessionId: playSessionId, playMethod: "DirectPlay")
        }

        // 2. The server's own HLS transcoding URL for this device profile.
        if let path = source.transcodingUrl, let url = URL(string: session.serverURL + path) {
            let lower = path.lowercased()
            let hasKey = lower.contains("apikey=") || lower.contains("api_key=")
            let finalURL = hasKey ? url : appendingQuery(url, [queryItem("ApiKey", session.accessToken)])
            return JFPlaybackSource(url: finalURL, mediaSourceId: sourceId, playSessionId: playSessionId, playMethod: "Transcode")
        }

        // 3. Fallback: ask for an HLS transcode directly.
        guard let url = makeURL(base: session.serverURL, path: "/Videos/\(itemId)/master.m3u8", query: [
            queryItem("MediaSourceId", sourceId), queryItem("PlaySessionId", playSessionId),
            queryItem("DeviceId", Self.deviceId), queryItem("VideoCodec", "h264"),
            queryItem("AudioCodec", "aac,mp3"), queryItem("SegmentContainer", "ts"),
            queryItem("TranscodingMaxAudioChannels", "2"), queryItem("VideoBitrate", "20000000"),
            queryItem("AudioBitrate", "192000"), queryItem("BreakOnNonKeyFrames", "true"),
            queryItem("ApiKey", session.accessToken)
        ]) else { throw APIError.invalidURL }
        return JFPlaybackSource(url: url, mediaSourceId: sourceId, playSessionId: playSessionId, playMethod: "Transcode")
    }

    private func progressBody(_ source: JFPlaybackSource, itemId: String, positionTicks: Int64, isPaused: Bool) -> [String: Any] {
        [
            "ItemId": itemId,
            "MediaSourceId": source.mediaSourceId,
            "PlaySessionId": source.playSessionId,
            "PositionTicks": positionTicks,
            "PlayMethod": source.playMethod,
            "CanSeek": true,
            "IsPaused": isPaused
        ]
    }

    func reportStart(_ source: JFPlaybackSource, itemId: String, positionTicks: Int64) async {
        _ = try? await send("/Sessions/Playing", method: "POST",
                            body: progressBody(source, itemId: itemId, positionTicks: positionTicks, isPaused: false))
    }

    func reportProgress(_ source: JFPlaybackSource, itemId: String, positionTicks: Int64, isPaused: Bool) async {
        _ = try? await send("/Sessions/Playing/Progress", method: "POST",
                            body: progressBody(source, itemId: itemId, positionTicks: positionTicks, isPaused: isPaused))
    }

    func reportStopped(_ source: JFPlaybackSource, itemId: String, positionTicks: Int64) async {
        _ = try? await send("/Sessions/Playing/Stopped", method: "POST",
                            body: progressBody(source, itemId: itemId, positionTicks: positionTicks, isPaused: true))
        if source.playMethod == "Transcode" {
            _ = try? await send("/Videos/ActiveEncodings", query: [
                queryItem("DeviceId", Self.deviceId), queryItem("PlaySessionId", source.playSessionId)
            ], method: "DELETE")
        }
    }
}
