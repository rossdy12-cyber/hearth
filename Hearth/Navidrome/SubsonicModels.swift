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
    let contentType: String?
    /// kbps
    let bitRate: Int?
    /// OpenSubsonic extras (Navidrome sends these).
    let bitDepth: Int?
    let samplingRate: Int?

    var displayTitle: String { title ?? "Unknown track" }

    private static let losslessSuffixes: Set<String> = ["flac", "alac", "wav", "aif", "aiff", "ape", "wv", "dsf", "dff"]

    /// FLAC/WAV/..., or an .m4a whose bitrate shows it is ALAC rather than AAC.
    var isLossless: Bool {
        let ext = suffix?.lowercased() ?? ""
        if Self.losslessSuffixes.contains(ext) { return true }
        return ext == "m4a" && (bitRate ?? 0) > 500
    }

    /// e.g. "FLAC · 24-bit/44.1 kHz" or "MP3 · 320 kbps".
    var sourceFormatDescription: String {
        let ext = (suffix ?? "audio").lowercased()
        let name = ext == "m4a" ? (isLossless ? "ALAC" : "AAC") : ext.uppercased()
        if isLossless {
            var detail: [String] = []
            if let depth = bitDepth, depth > 0 { detail.append("\(depth)-bit") }
            if let rate = samplingRate, rate > 0 { detail.append(Self.kilohertz(rate)) }
            return detail.isEmpty ? name : "\(name) · \(detail.joined(separator: "/"))"
        }
        if let kbps = bitRate, kbps > 0 { return "\(name) · \(kbps) kbps" }
        return name
    }

    private static func kilohertz(_ hertz: Int) -> String {
        let value = Double(hertz) / 1000
        return value == value.rounded() ? "\(Int(value)) kHz" : String(format: "%.1f kHz", value)
    }
}

/// Music streaming quality. "Original" sends the file as it is (FLAC stays FLAC);
/// the others ask Navidrome to convert to MP3 at that bitrate.
enum MusicQuality: String, CaseIterable, Identifiable, Sendable {
    case original
    case kbps320
    case kbps256
    case kbps192
    case kbps128

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original (lossless)"
        case .kbps320: return "320 kbps"
        case .kbps256: return "256 kbps"
        case .kbps192: return "192 kbps"
        case .kbps128: return "128 kbps"
        }
    }

    var maxBitRate: Int? {
        switch self {
        case .original: return nil
        case .kbps320: return 320
        case .kbps256: return 256
        case .kbps192: return 192
        case .kbps128: return 128
        }
    }

    static let wifiKey = "musicQuality.wifi"
    static let cellularKey = "musicQuality.cellular"
    static let defaultWifi = MusicQuality.original
    static let defaultCellular = MusicQuality.kbps256

    static func stored(_ key: String, default fallback: MusicQuality) -> MusicQuality {
        UserDefaults.standard.string(forKey: key).flatMap(MusicQuality.init(rawValue:)) ?? fallback
    }
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
