import SwiftUI

/// Loads an image from the server and fills (and crops to) whatever frame it is given.
struct RemoteImage: View {
    let url: URL?
    var placeholderText: String? = nil

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ZStack {
                            Theme.surface
                            if let placeholderText {
                                Text(placeholderText)
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Theme.secondaryText)
                                    .padding(6)
                            }
                        }
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.3))
                Rectangle().fill(Theme.accent)
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 3)
    }
}

struct RowTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
    }
}

/// The big rounded button used for Play / More Info / Shuffle.
struct PillLabel: View {
    let title: String
    let systemImage: String
    var prominent = true

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(prominent ? Theme.accent : Color.white.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
    }
}

struct SignInPrompt: View {
    let service: String
    let systemImage: String
    let message: String
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Connect \(service)")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
            Button {
                router.showSettings = true
            } label: {
                PillLabel(title: "Open Settings", systemImage: "gearshape.fill")
                    .frame(maxWidth: 240)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video cards and rows

struct PosterCard: View {
    let url: URL?
    let title: String
    var width: CGFloat? = 112
    var progress: Double? = nil

    var body: some View {
        poster
            .overlay(alignment: .bottom) {
                if let progress {
                    ProgressBar(value: progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(title)
    }

    @ViewBuilder private var poster: some View {
        if let width {
            RemoteImage(url: url, placeholderText: title)
                .frame(width: width, height: width * 1.5)
        } else {
            RemoteImage(url: url, placeholderText: title)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
        }
    }
}

/// A horizontal row of posters; tapping one opens its detail page.
struct PosterRow: View {
    let title: String
    let items: [JFItem]
    let client: JellyfinClient

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RowTitle(text: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCard(url: client.posterURL(item), title: item.title, progress: item.progress)
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

struct LandscapeCard: View {
    let item: JFItem
    let client: JellyfinClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: client.landscapeURL(item), placeholderText: item.title)
                .frame(width: 230, height: 130)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
                .overlay(alignment: .bottom) {
                    if let progress = item.progress {
                        ProgressBar(value: progress)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(item.seriesName ?? item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 230, alignment: .leading)
    }

    private var subtitle: String {
        if item.isEpisode {
            return [item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · ")
        }
        return item.runtimeText ?? ""
    }
}

/// Tapping a card resumes the video straight away.
struct ContinueWatchingRow: View {
    let items: [JFItem]
    let client: JellyfinClient

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RowTitle(text: "Continue Watching")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                VideoPlayback.shared.start(item, client: client)
                            } label: {
                                LandscapeCard(item: item, client: client)
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
