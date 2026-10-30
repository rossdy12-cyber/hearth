import SwiftUI

/// "Play on…": sends a title to another Jellyfin device (e.g. Hearth on your PC) and controls it.
@MainActor
final class RemoteController: ObservableObject {
    enum Sheet: String, Identifiable {
        case picker, remote
        var id: String { rawValue }
    }

    struct PendingPlay {
        let item: JFItem
        let startTicks: Int64
    }

    static let shared = RemoteController()

    @Published var sheet: Sheet?
    @Published private(set) var pending: PendingPlay?
    @Published private(set) var targetId: String?
    @Published private(set) var targetName: String?
    @Published var lastError: String?

    /// Starts "Play on…" for a title. Without a start time it resumes where you left off.
    func offer(_ item: JFItem, startTicks: Int64? = nil) {
        pending = PendingPlay(item: item, startTicks: startTicks ?? (item.isPlayed ? 0 : item.resumeTicks))
        sheet = .picker
    }

    /// Opens the remote for the last device, or the device list if there isn't one yet.
    func openRemote() {
        pending = nil
        sheet = targetId == nil ? .picker : .remote
    }

    func pickAnotherDevice() {
        pending = nil
        sheet = .picker
    }

    func choose(_ session: JFSession, client: JellyfinClient) async {
        if let pending {
            do {
                try await client.playOn(sessionId: session.id, itemIds: [pending.item.id], startTicks: pending.startTicks)
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        targetId = session.id
        targetName = session.displayName
        pending = nil
        sheet = .remote
    }
}

// MARK: - Device picker

struct SessionPickerView: View {
    let client: JellyfinClient
    @ObservedObject private var remote = RemoteController.shared
    @State private var sessions: [JFSession] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var busyId: String?

    var body: some View {
        NavigationStack {
            List {
                if let pending = remote.pending {
                    Section {
                        Text("Choose where to play “\(pending.item.title)”.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Section("Devices") {
                    if !loaded {
                        ProgressView()
                    } else if sessions.isEmpty {
                        Text("No other devices found. Open Hearth on your PC (or the Jellyfin web app) and sign in to the same Jellyfin server, then pull down to refresh.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(sessions) { session in
                        Button {
                            Task {
                                busyId = session.id
                                await remote.choose(session, client: client)
                                busyId = nil
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: session.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.displayName)
                                        .foregroundStyle(.white)
                                    Text(subtitle(for: session))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if busyId == session.id {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(busyId != nil)
                    }
                }
                if let message = error ?? remote.lastError {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(remote.pending == nil ? "Control a Device" : "Play on…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { remote.sheet = nil }
                }
            }
            .refreshable { await load() }
            .task {
                remote.lastError = nil
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    private func subtitle(for session: JFSession) -> String {
        var parts = [session.client ?? ""]
        if let playing = session.nowPlayingItem {
            parts.append("Playing \(playing.seriesName ?? playing.title)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func load() async {
        do {
            sessions = try await client.controllableSessions()
            error = nil
        } catch {
            if !isCancellation(error) { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

// MARK: - Remote control screen

struct RemoteControlView: View {
    let client: JellyfinClient
    @ObservedObject private var remote = RemoteController.shared
    @State private var session: JFSession?
    @State private var lost = false
    @State private var streamsItemId: String?
    @State private var audioStreams: [JFMediaStream] = []
    @State private var subtitleStreams: [JFMediaStream] = []
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var volume: Double = 100
    @State private var editingVolume = false

    private var item: JFItem? { session?.nowPlayingItem }
    private var playState: JFPlayState? { session?.playState }
    private var position: Double { Double(playState?.positionTicks ?? 0) / 10_000_000 }
    private var duration: Double { Double(item?.runTimeTicks ?? 0) / 10_000_000 }
    private var isPaused: Bool { playState?.isPaused ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if lost {
                        message("\(remote.targetName ?? "The device") isn't connected any more. Choose another device.", icon: "wifi.slash")
                    } else if let item {
                        nowPlaying(item)
                        scrubber
                        transport
                        volumeRow
                        trackPickers
                    } else if session != nil {
                        message("Nothing is playing on \(remote.targetName ?? "this device"). Use Play on… on a title page to start something.", icon: "tv")
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(remote.targetName ?? "Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Devices") { remote.pickAnotherDevice() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { remote.sheet = nil }
                }
            }
            .alert("Remote control", isPresented: Binding(
                get: { remote.lastError != nil },
                set: { if !$0 { remote.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(remote.lastError ?? "")
            }
            .task {
                while !Task.isCancelled {
                    await refresh()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 80)
    }

    private func nowPlaying(_ item: JFItem) -> some View {
        VStack(spacing: 10) {
            RemoteImage(url: client.landscapeURL(item), placeholderText: item.title)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let series = item.seriesName {
                Text(series)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text([item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · "))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { scrubbing ? scrubValue : min(position, max(duration, 1)) }, set: { scrubValue = $0 }),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = position
                        scrubbing = true
                    } else {
                        let target = Int64(scrubValue * 10_000_000)
                        perform { try await client.sendPlaystate(sessionId: $0, "Seek", seekTicks: target) }
                        scrubbing = false
                    }
                }
            )
            .tint(Theme.accent)
            HStack {
                Text(formatTime(scrubbing ? scrubValue : position))
                Spacer()
                Text("-" + formatTime(max(0, duration - (scrubbing ? scrubValue : position))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
    }

    private var transport: some View {
        VStack(spacing: 18) {
            HStack(spacing: 34) {
                transportButton("backward.end.fill", "Previous episode") {
                    try await client.sendPlaystate(sessionId: $0, "PreviousTrack")
                }
                transportButton("gobackward.10", "Back 10 seconds") { id in
                    try await client.sendPlaystate(sessionId: id, "Seek", seekTicks: Int64((position - 10) * 10_000_000))
                }
                Button {
                    perform { try await client.sendPlaystate(sessionId: $0, isPaused ? "Unpause" : "Pause") }
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.black)
                        .frame(width: 72, height: 72)
                        .background(Theme.accent, in: Circle())
                }
                .accessibilityLabel(isPaused ? "Play" : "Pause")
                transportButton("goforward.30", "Forward 30 seconds") { id in
                    try await client.sendPlaystate(sessionId: id, "Seek", seekTicks: Int64((position + 30) * 10_000_000))
                }
                transportButton("forward.end.fill", "Next episode") {
                    try await client.sendPlaystate(sessionId: $0, "NextTrack")
                }
            }
            .foregroundStyle(.white)
            Button(role: .destructive) {
                perform { try await client.sendPlaystate(sessionId: $0, "Stop") }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())
            }
        }
    }

    private func transportButton(_ icon: String, _ label: String, _ action: @escaping (String) async throws -> Void) -> some View {
        Button {
            perform(action)
        } label: {
            Image(systemName: icon).font(.title2)
        }
        .accessibilityLabel(label)
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Button {
                perform { try await client.sendCommand(sessionId: $0, "ToggleMute") }
            } label: {
                Image(systemName: (playState?.isMuted ?? false) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle((playState?.isMuted ?? false) ? Theme.accent : Color.white)
                    .frame(width: 32)
            }
            .accessibilityLabel("Mute")
            Slider(value: $volume, in: 0...100, onEditingChanged: { editing in
                editingVolume = editing
                if !editing {
                    let level = String(Int(volume))
                    perform { try await client.sendCommand(sessionId: $0, "SetVolume", arguments: ["Volume": level]) }
                }
            })
            .tint(Theme.accent)
        }
    }

    @ViewBuilder private var trackPickers: some View {
        if audioStreams.count > 1 || !subtitleStreams.isEmpty {
            HStack(spacing: 12) {
                if audioStreams.count > 1 {
                    Menu {
                        ForEach(audioStreams, id: \.index) { stream in
                            Button {
                                perform { try await client.sendCommand(sessionId: $0, "SetAudioStreamIndex", arguments: ["Index": String(stream.index)]) }
                            } label: {
                                if stream.index == playState?.audioStreamIndex {
                                    Label(stream.label, systemImage: "checkmark")
                                } else {
                                    Text(stream.label)
                                }
                            }
                        }
                    } label: {
                        PillLabel(title: "Audio", systemImage: "waveform", prominent: false)
                    }
                }
                if !subtitleStreams.isEmpty {
                    Menu {
                        Button {
                            perform { try await client.sendCommand(sessionId: $0, "SetSubtitleStreamIndex", arguments: ["Index": "-1"]) }
                        } label: {
                            if (playState?.subtitleStreamIndex ?? -1) < 0 {
                                Label("Off", systemImage: "checkmark")
                            } else {
                                Text("Off")
                            }
                        }
                        ForEach(subtitleStreams, id: \.index) { stream in
                            Button {
                                perform { try await client.sendCommand(sessionId: $0, "SetSubtitleStreamIndex", arguments: ["Index": String(stream.index)]) }
                            } label: {
                                if stream.index == playState?.subtitleStreamIndex {
                                    Label(stream.label, systemImage: "checkmark")
                                } else {
                                    Text(stream.label)
                                }
                            }
                        }
                    } label: {
                        PillLabel(title: "Subtitles", systemImage: "captions.bubble", prominent: false)
                    }
                }
            }
        }
    }

    /// Sends a command to the chosen device, then refreshes the live state shortly after.
    private func perform(_ action: @escaping (String) async throws -> Void) {
        guard let id = remote.targetId else { return }
        Task {
            do {
                try await action(id)
                try? await Task.sleep(nanoseconds: 400_000_000)
                await refresh()
            } catch {
                remote.lastError = error.localizedDescription
            }
        }
    }

    private func refresh() async {
        guard let id = remote.targetId else { return }
        do {
            let fresh = try await client.remoteSession(id: id)
            lost = fresh == nil
            session = fresh
            if !editingVolume, let level = fresh?.playState?.volumeLevel {
                volume = Double(level)
            }
            let nowId = fresh?.nowPlayingItem?.id
            if nowId != streamsItemId {
                streamsItemId = nowId
                await loadStreams(nowId)
            }
        } catch {
            // Keep the last known state; the next poll tries again.
        }
    }

    private func loadStreams(_ itemId: String?) async {
        guard let itemId, let detailed = try? await client.itemWithStreams(itemId) else {
            audioStreams = []
            subtitleStreams = []
            return
        }
        let streams = detailed.mediaStreams ?? []
        audioStreams = streams.filter { $0.type == "Audio" }
        subtitleStreams = streams.filter { $0.type == "Subtitle" }
    }
}
