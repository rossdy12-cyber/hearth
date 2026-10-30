import SwiftUI

/// The large featured title at the top of Home, Movies and TV Shows.
struct HeroBanner: View {
    let item: JFItem
    let client: JellyfinClient

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: client.backdropURL(item))
                .frame(height: 480)
                .frame(maxWidth: .infinity)
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.25), .clear, .black.opacity(0.6), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(spacing: 14) {
                if let logo = client.logoURL(item) {
                    AsyncImage(url: logo) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        titleText
                    }
                    .frame(maxWidth: 260, maxHeight: 110)
                } else {
                    titleText
                }

                if let genres = item.genres, !genres.isEmpty {
                    Text(genres.prefix(3).joined(separator: "  •  "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }

                HStack(spacing: 12) {
                    Button {
                        VideoPlayback.shared.start(item, client: client)
                    } label: {
                        PillLabel(title: item.progress == nil ? "Play" : "Resume", systemImage: "play.fill")
                    }
                    NavigationLink(value: item) {
                        PillLabel(title: "More Info", systemImage: "info.circle", prominent: false)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 18)
        }
    }

    private var titleText: some View {
        Text(item.title)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .shadow(radius: 8)
            .padding(.horizontal, 24)
    }
}
