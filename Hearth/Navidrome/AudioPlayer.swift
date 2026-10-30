import AVFoundation
import MediaPlayer
import UIKit

/// Elapsed time lives in its own object so only the progress bars redraw twice a second.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }
}

/// Plays Navidrome music in the background, with lock-screen and Control Center controls.
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var queue: [SubsonicSong] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published var showNowPlaying = false
    let clock = PlaybackClock()

    var client: SubsonicClient?

    private let player = AVPlayer()
    private var artwork: MPMediaItemArtwork?
    private var artworkSongId: String?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rateObservation: NSKeyValueObservation?

    var current: SubsonicSong? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    private init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            let seconds = time.seconds
            Task { @MainActor in
                AudioPlayer.shared.tick(seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { note in
            let finishedId = (note.object as? AVPlayerItem).map { ObjectIdentifier($0) }
            Task { @MainActor in
                AudioPlayer.shared.itemFinished(finishedId)
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { observed, _ in
            let playing = observed.timeControlStatus != .paused
            Task { @MainActor in
                AudioPlayer.shared.playingChanged(playing)
            }
        }
        setUpRemoteCommands()
    }

    // MARK: - Controls

    func play(_ songs: [SubsonicSong], startAt start: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs
        index = max(0, min(start, songs.count - 1))
        loadCurrent()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard current != nil, !VideoPlayback.shared.isActive else { return }
        guard player.currentItem != nil else {
            loadCurrent()
            return
        }
        activateSession()
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        guard index + 1 < queue.count else {
            player.pause()
            player.seek(to: .zero)
            clock.elapsed = 0
            isPlaying = false
            updateNowPlaying()
            return
        }
        index += 1
        loadCurrent()
    }

    func previous() {
        if clock.elapsed > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            loadCurrent()
        }
    }

    func jump(to newIndex: Int) {
        guard queue.indices.contains(newIndex) else { return }
        index = newIndex
        loadCurrent()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        clock.elapsed = seconds
        updateNowPlaying()
    }

    func stop() {
        player.replaceCurrentItem(with: nil)
        queue = []
        index = 0
        isPlaying = false
        showNowPlaying = false
        clock.elapsed = 0
        clock.duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Internals

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func loadCurrent() {
        guard let song = current, let client, let url = client.streamURL(for: song) else { return }
        activateSession()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        clock.elapsed = 0
        clock.duration = Double(song.duration ?? 0)
        player.play()
        isPlaying = true
        updateNowPlaying()
        loadArtwork(for: song, client: client)
        Task {
            await client.scrobble(song.id, submission: false)
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, current != nil else { return }
        clock.elapsed = seconds
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0,
           abs(itemDuration - clock.duration) > 1 {
            clock.duration = itemDuration
            updateNowPlaying()
        }
    }

    private func itemFinished(_ itemId: ObjectIdentifier?) {
        guard let itemId, let currentItem = player.currentItem, ObjectIdentifier(currentItem) == itemId else { return }
        if let song = current, let client {
            Task {
                await client.scrobble(song.id, submission: true)
            }
        }
        next()
    }

    private func playingChanged(_ playing: Bool) {
        guard current != nil, playing != isPlaying else { return }
        isPlaying = playing
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayTitle,
            MPMediaItemPropertyArtist: song.artist ?? "",
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPMediaItemPropertyPlaybackDuration: clock.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork, artworkSongId == song.id {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for song: SubsonicSong, client: SubsonicClient) {
        artwork = nil
        artworkSongId = nil
        guard let url = client.coverURL(song.coverArt, size: 600) else { return }
        let songId = song.id
        Task {
            guard let result = try? await httpSession.data(from: url),
                  let image = UIImage(data: result.0),
                  current?.id == songId else { return }
            artwork = Self.makeArtwork(image)
            artworkSongId = songId
            updateNowPlaying()
        }
    }

    /// Built outside the main actor: iOS asks for the artwork image on a background thread.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            Task { @MainActor in AudioPlayer.shared.resume() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in AudioPlayer.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in AudioPlayer.shared.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in AudioPlayer.shared.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in AudioPlayer.shared.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in AudioPlayer.shared.seek(to: position) }
            return .success
        }
    }
}
