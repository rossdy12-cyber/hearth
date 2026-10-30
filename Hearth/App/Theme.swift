import SwiftUI
import UIKit

enum Theme {
    /// Hearth amber.
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.18)
    static let background = Color.black
    static let surface = Color(white: 0.12)
    static let secondaryText = Color(white: 0.62)

    @MainActor
    static func applyUIKitAppearance() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(white: 0.04, alpha: 1)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = .black
        navBar.shadowColor = .clear
        navBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }
}

struct HearthLogo: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "house.fill")
                .foregroundStyle(Theme.accent)
            Text("HEARTH")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hearth")
    }
}

/// Black navigation bar with the logo on the left and a settings gear on the right.
struct HearthChrome: ViewModifier {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var accounts: AccountStore

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HearthLogo()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 18) {
                        if accounts.jellyfin != nil {
                            Button {
                                RemoteController.shared.openRemote()
                            } label: {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(.white)
                            }
                            .accessibilityLabel("Remote control")
                        }
                        Button {
                            router.showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
    }
}

extension View {
    func hearthChrome() -> some View {
        modifier(HearthChrome())
    }

    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer()
        }
    }

    func jellyfinDestinations() -> some View {
        navigationDestination(for: JFItem.self) { item in
            DetailView(item: item)
        }
        .navigationDestination(for: LibraryKind.self) { kind in
            AllItemsGrid(kind: kind)
        }
    }

    func musicDestinations() -> some View {
        navigationDestination(for: MusicRoute.self) { route in
            switch route {
            case .album(let id):
                AlbumDetailView(albumId: id)
            case .artist(let id):
                ArtistDetailView(artistId: id)
            case .playlist(let id):
                PlaylistDetailView(playlistId: id)
            case .allArtists:
                AllArtistsView()
            }
        }
    }
}
