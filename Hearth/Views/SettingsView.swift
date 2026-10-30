import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountForm(service: .jellyfin)
                } header: {
                    Label("Jellyfin: movies & TV", systemImage: "film")
                } footer: {
                    Text("The address you open Jellyfin with in a browser, for example http://100.x.x.x:8096 (your NAS's Tailscale address). On TrueNAS the port is shown on the app's page.")
                }

                Section {
                    AccountForm(service: .navidrome)
                } header: {
                    Label("Navidrome: music", systemImage: "music.note")
                } footer: {
                    Text("The address you open Navidrome with in a browser, for example http://100.x.x.x:4533.")
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Text("Hearth only talks to your own servers. Passwords and sign-in tokens are kept in the iPhone Keychain. Make sure Tailscale is connected on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Either the sign-in fields or "signed in as …" with a Sign Out button.
struct AccountForm: View {
    enum Service {
        case jellyfin, navidrome
    }

    let service: Service
    @EnvironmentObject private var accounts: AccountStore
    @State private var server: String
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    init(service: Service) {
        self.service = service
        let key = service == .jellyfin ? "lastJellyfinURL" : "lastNavidromeURL"
        _server = State(initialValue: UserDefaults.standard.string(forKey: key) ?? "")
    }

    private var signedIn: (server: String, user: String)? {
        switch service {
        case .jellyfin:
            return accounts.jellyfin.map { (server: $0.serverURL, user: $0.username) }
        case .navidrome:
            return accounts.navidrome.map { (server: $0.serverURL, user: $0.username) }
        }
    }

    private var placeholder: String {
        service == .jellyfin ? "http://100.x.x.x:8096" : "http://100.x.x.x:4533"
    }

    var body: some View {
        if let signedIn {
            LabeledContent("Server", value: signedIn.server)
            LabeledContent("Signed in as", value: signedIn.user)
            Button("Sign Out", role: .destructive) {
                switch service {
                case .jellyfin: accounts.signOutJellyfin()
                case .navidrome: accounts.signOutNavidrome()
                }
            }
        } else {
            TextField("Server address", text: $server, prompt: Text(placeholder))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    Text("Sign In")
                    Spacer()
                    if busy { ProgressView() }
                }
            }
            .disabled(busy || server.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty)
        }
    }

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            switch service {
            case .jellyfin:
                try await accounts.signInJellyfin(server: server, username: username, password: password)
            case .navidrome:
                try await accounts.signInNavidrome(server: server, username: username, password: password)
            }
            password = ""
        } catch let urlError as URLError {
            self.error = Self.describe(urlError)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
            return "Couldn't reach the server. Check that Tailscale is on and that the address and port are right."
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS blocked the plain-http connection."
        default:
            return error.localizedDescription
        }
    }
}
