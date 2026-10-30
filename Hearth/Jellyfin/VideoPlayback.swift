import AVKit
import UIKit

extension Notification.Name {
    /// Posted after a video closes, so Continue Watching and episode progress refresh.
    static let hearthPlaybackDidStop = Notification.Name("HearthPlaybackDidStop")
}

/// The system video player, with a hook for when the person closes it.
final class HearthPlayerViewController: AVPlayerViewController {
    var onClose: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onClose?()
            onClose = nil
        }
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Opens Jellyfin videos full screen in AVPlayer and reports progress back to the server.
@MainActor
final class VideoPlayback: ObservableObject {
    static let shared = VideoPlayback()

    @Published private(set) var isPreparing = false
    @Published var lastError: String?
    private(set) var isActive = false

    private var player: AVPlayer?
    private weak var controller: HearthPlayerViewController?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var didStart = false

    func start(_ item: JFItem, client: JellyfinClient) {
        guard !isPreparing, !isActive else { return }
        isPreparing = true
        Task {
            do {
                try await play(item, client: client)
            } catch {
                if !isCancellation(error) {
                    lastError = error.localizedDescription
                }
            }
            isPreparing = false
        }
    }

    private func play(_ item: JFItem, client: JellyfinClient) async throws {
        // For a show, play the next episode to watch (or the very first one).
        var target = item
        if item.isSeries {
            if let next = try await client.nextUp(seriesId: item.id) {
                target = next
            } else if let first = try await client.firstEpisode(seriesId: item.id) {
                target = first
            } else {
                throw APIError.server("No episodes were found for this show.")
            }
        }

        let source = try await client.playbackSource(itemId: target.id)
        let startTicks: Int64 = target.isPlayed ? 0 : target.resumeTicks
        let itemId = target.id

        AudioPlayer.shared.pause()
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)

        let playerItem = AVPlayerItem(url: source.url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        didStart = false

        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { observed, _ in
            let status = observed.status
            let message = observed.error?.localizedDescription
            Task { @MainActor in
                VideoPlayback.shared.itemStatusChanged(status, startTicks: startTicks, errorMessage: message)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak player] time in
            guard let player, time.seconds.isFinite else { return }
            let ticks = Int64(time.seconds * 10_000_000)
            let paused = player.timeControlStatus == .paused
            Task {
                await client.reportProgress(source, itemId: itemId, positionTicks: ticks, isPaused: paused)
            }
        }

        let controller = HearthPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        controller.modalPresentationStyle = .fullScreen
        controller.onClose = { [weak self] in
            self?.finish(client: client, source: source, itemId: itemId)
        }

        guard let presenter = UIApplication.shared.topViewController else {
            throw APIError.server("Couldn't open the video player.")
        }
        self.controller = controller
        isActive = true
        presenter.present(controller, animated: true)
        Task {
            await client.reportStart(source, itemId: itemId, positionTicks: startTicks)
        }
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, startTicks: Int64, errorMessage: String?) {
        guard let player else { return }
        switch status {
        case .readyToPlay:
            guard !didStart else { return }
            didStart = true
            if startTicks > 0 {
                player.seek(to: CMTime(seconds: Double(startTicks) / 10_000_000, preferredTimescale: 600))
            }
            player.play()
        case .failed:
            let message = "This video couldn't be played." + (errorMessage.map { " (\($0))" } ?? "")
            if let controller {
                controller.dismiss(animated: true) {
                    VideoPlayback.shared.lastError = message
                }
            } else {
                lastError = message
            }
        default:
            break
        }
    }

    private func finish(client: JellyfinClient, source: JFPlaybackSource, itemId: String) {
        guard let player else { return }
        let seconds = player.currentTime().seconds
        let ticks = seconds.isFinite ? Int64(seconds * 10_000_000) : 0
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
        self.player = nil
        isActive = false
        Task {
            await client.reportStopped(source, itemId: itemId, positionTicks: ticks)
            NotificationCenter.default.post(name: .hearthPlaybackDidStop, object: nil)
        }
    }
}
