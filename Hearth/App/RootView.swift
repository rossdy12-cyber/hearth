import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case home, movies, shows, music, search
    }

    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var audio: AudioPlayer
    @ObservedObject private var playback = VideoPlayback.shared
    @ObservedObject private var remote = RemoteController.shared
    @State private var tab: Tab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            LibraryView(kind: .movies)
                .tabItem { Label("Movies", systemImage: "film") }
                .tag(Tab.movies)
            LibraryView(kind: .shows)
                .tabItem { Label("TV Shows", systemImage: "tv") }
                .tag(Tab.shows)
            MusicView()
                .tabItem { Label("Music", systemImage: "music.note") }
                .tag(Tab.music)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
                .environmentObject(accounts)
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $audio.showNowPlaying) {
            NowPlayingView()
                .environmentObject(accounts)
                .environmentObject(audio)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $remote.sheet) { sheet in
            Group {
                if let client = accounts.jellyfinClient {
                    switch sheet {
                    case .picker:
                        SessionPickerView(client: client)
                    case .remote:
                        RemoteControlView(client: client)
                    }
                } else {
                    SignInPrompt(service: "Jellyfin", systemImage: "tv",
                                 message: "Sign in to Jellyfin to control other devices.")
                }
            }
            .environmentObject(router)
            .preferredColorScheme(.dark)
        }
        .overlay {
            if playback.isPreparing {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ProgressView("Starting playback…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("Can't play this", isPresented: Binding(
            get: { playback.lastError != nil },
            set: { if !$0 { playback.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playback.lastError ?? "")
        }
        .onAppear {
            if !accounts.hasAnyAccount {
                router.showSettings = true
            }
        }
    }
}
