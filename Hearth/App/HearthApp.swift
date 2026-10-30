import AVFoundation
import SwiftUI

@main
struct HearthApp: App {
    @StateObject private var accounts = AccountStore()
    @StateObject private var router = AppRouter()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
        Theme.applyUIKitAppearance()
        NetworkMonitor.shared.start()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(accounts)
                .environmentObject(router)
                .environmentObject(AudioPlayer.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
