import SwiftUI

/// The small bar above the tab bar while music is queued. Tap it for the full player.
struct MiniPlayer: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var accounts: AccountStore

    var body: some View {
        if let song = audio.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    RemoteImage(url: accounts.subsonicClient?.coverURL(song.coverArt, size: 120))
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(song.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        audio.togglePlayPause()
                    } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
                    Button {
                        audio.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Next track")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                MiniProgress(clock: audio.clock)
            }
            .foregroundStyle(.white)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                audio.showNowPlaying = true
            }
        }
    }
}

private struct MiniProgress: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        ProgressBar(value: clock.fraction)
            .frame(height: 2)
    }
}

/// Full-screen player: artwork, scrubber, transport controls and the Up Next queue.
struct NowPlayingView: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.16, blue: 0.05), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let song = audio.current {
                VStack(spacing: 22) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close player")
                        Spacer()
                        Text("Track \(audio.index + 1) of \(audio.queue.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Button {
                            withAnimation { showQueue.toggle() }
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(showQueue ? Theme.accent : Color.white)
                        }
                        .accessibilityLabel("Up Next")
                    }

                    if showQueue {
                        queueList
                    } else {
                        Spacer(minLength: 0)
                        RemoteImage(url: accounts.subsonicClient?.coverURL(song.coverArt, size: 800), placeholderText: song.album)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.displayTitle)
                            .font(.title2.bold())
                            .lineLimit(1)
                        Text([song.artist, song.album].compactMap { $0 }.joined(separator: " — "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        if !audio.streamDescription.isEmpty {
                            Text(audio.streamDescription)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Scrubber(clock: audio.clock)

                    HStack(spacing: 48) {
                        Button {
                            audio.previous()
                        } label: {
                            Image(systemName: "backward.fill").font(.title)
                        }
                        .accessibilityLabel("Previous track")
                        Button {
                            audio.togglePlayPause()
                        } label: {
                            Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.black)
                                .frame(width: 72, height: 72)
                                .background(Theme.accent, in: Circle())
                        }
                        .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
                        Button {
                            audio.next()
                        } label: {
                            Image(systemName: "forward.fill").font(.title)
                        }
                        .accessibilityLabel("Next track")
                    }
                    .padding(.bottom, 12)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            } else {
                Text("Nothing playing")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var queueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(audio.queue.enumerated()), id: \.offset) { index, song in
                        SongRow(
                            song: song,
                            number: index + 1,
                            artworkURL: nil,
                            isCurrent: index == audio.index
                        ) {
                            audio.jump(to: index)
                        }
                        .id(index)
                    }
                }
            }
            .onAppear {
                proxy.scrollTo(audio.index, anchor: .center)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct Scrubber: View {
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject private var audio: AudioPlayer
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isDragging ? dragValue : clock.elapsed },
                    set: { dragValue = $0 }
                ),
                in: 0...max(clock.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        dragValue = clock.elapsed
                        isDragging = true
                    } else {
                        audio.seek(to: dragValue)
                        isDragging = false
                    }
                }
            )
            .tint(Theme.accent)
            HStack {
                Text(formatTime(isDragging ? dragValue : clock.elapsed))
                Spacer()
                Text("-" + formatTime(max(0, clock.duration - (isDragging ? dragValue : clock.elapsed))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
    }
}
