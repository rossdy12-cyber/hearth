import Foundation

struct JellyfinSession: Codable, Equatable, Sendable {
    var serverURL: String
    var username: String
    var userId: String
    var accessToken: String
}

/// A movie, show, season or episode. Jellyfin sends `PascalCase` keys; the decoder lower-cases the first letter.
struct JFItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let type: String?
    let overview: String?
    let productionYear: Int?
    let officialRating: String?
    let communityRating: Double?
    let runTimeTicks: Int64?
    let genres: [String]?
    let seriesId: String?
    let seriesName: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let backdropImageTags: [String]?
    let parentBackdropItemId: String?
    let imageTags: JFImageTags?
    let userData: JFUserData?

    static func == (lhs: JFItem, rhs: JFItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var title: String { name ?? "Untitled" }
    var isSeries: Bool { type == "Series" }
    var isEpisode: Bool { type == "Episode" }
    var resumeTicks: Int64 { userData?.playbackPositionTicks ?? 0 }
    var isPlayed: Bool { userData?.played ?? false }

    /// 0...1 when partly watched, otherwise nil.
    var progress: Double? {
        guard let position = userData?.playbackPositionTicks, position > 0,
              let total = runTimeTicks, total > 0 else { return nil }
        return min(1, Double(position) / Double(total))
    }

    var runtimeText: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let minutes = Int(ticks / 600_000_000)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    var episodeLabel: String? {
        guard isEpisode else { return nil }
        var parts: [String] = []
        if let season = parentIndexNumber { parts.append("S\(season)") }
        if let episode = indexNumber { parts.append("E\(episode)") }
        return parts.isEmpty ? nil : parts.joined(separator: ":")
    }
}

struct JFImageTags: Decodable, Sendable {
    let primary: String?
    let thumb: String?
    let logo: String?
}

struct JFUserData: Decodable, Sendable {
    let playbackPositionTicks: Int64?
    let playedPercentage: Double?
    let played: Bool?
}

struct JFItemsResponse: Decodable, Sendable {
    let items: [JFItem]
    let totalRecordCount: Int?
}

struct JFAuthResponse: Decodable {
    struct User: Decodable {
        let id: String
        let name: String?
    }
    let user: User
    let accessToken: String
}

struct JFMediaSource: Decodable {
    let id: String?
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let transcodingUrl: String?
}

struct JFPlaybackInfo: Decodable {
    let mediaSources: [JFMediaSource]
    let playSessionId: String?
}

/// What the video player needs: a URL AVPlayer can open plus the ids used for progress reports.
struct JFPlaybackSource: Sendable {
    let url: URL
    let mediaSourceId: String
    let playSessionId: String
    let playMethod: String
}

struct JFGenreRow: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [JFItem]
}
