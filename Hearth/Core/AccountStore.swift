import Foundation

/// Holds the signed-in Jellyfin and Navidrome accounts and keeps them in the Keychain.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var jellyfin: JellyfinSession?
    @Published private(set) var navidrome: NavidromeSession?
    private(set) var jellyfinClient: JellyfinClient?
    private(set) var subsonicClient: SubsonicClient?

    private static let jellyfinKey = "jellyfin"
    private static let navidromeKey = "navidrome"

    init() {
        setJellyfin(Keychain.load(JellyfinSession.self, for: Self.jellyfinKey), persist: false)
        setNavidrome(Keychain.load(NavidromeSession.self, for: Self.navidromeKey), persist: false)
    }

    var hasAnyAccount: Bool { jellyfin != nil || navidrome != nil }

    func signInJellyfin(server: String, username: String, password: String) async throws {
        let session = try await JellyfinClient.signIn(server: server, username: username, password: password)
        UserDefaults.standard.set(session.serverURL, forKey: "lastJellyfinURL")
        setJellyfin(session)
    }

    func signOutJellyfin() {
        if let client = jellyfinClient {
            Task { await client.logout() }
        }
        setJellyfin(nil)
    }

    func signInNavidrome(server: String, username: String, password: String) async throws {
        let session = try await SubsonicClient.signIn(server: server, username: username, password: password)
        UserDefaults.standard.set(session.serverURL, forKey: "lastNavidromeURL")
        setNavidrome(session)
    }

    func signOutNavidrome() {
        AudioPlayer.shared.stop()
        setNavidrome(nil)
    }

    private func setJellyfin(_ session: JellyfinSession?, persist: Bool = true) {
        jellyfinClient = session.map { JellyfinClient(session: $0) }
        jellyfin = session
        guard persist else { return }
        if let session {
            Keychain.save(session, for: Self.jellyfinKey)
        } else {
            Keychain.delete(Self.jellyfinKey)
        }
    }

    private func setNavidrome(_ session: NavidromeSession?, persist: Bool = true) {
        subsonicClient = session.map { SubsonicClient(session: $0) }
        AudioPlayer.shared.client = subsonicClient
        navidrome = session
        guard persist else { return }
        if let session {
            Keychain.save(session, for: Self.navidromeKey)
        } else {
            Keychain.delete(Self.navidromeKey)
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var showSettings = false
}
