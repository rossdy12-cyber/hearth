import SwiftUI

enum LibraryKind: Hashable {
    case movies, shows

    var title: String { self == .movies ? "Movies" : "TV Shows" }
    var itemType: String { self == .movies ? "Movie" : "Series" }
    var systemImage: String { self == .movies ? "film" : "tv" }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var hero: JFItem?
    @Published var latest: [JFItem] = []
    @Published var genreRows: [JFGenreRow] = []
    @Published var error: String?
    @Published var loaded = false

    func load(_ kind: LibraryKind, client: JellyfinClient) async {
        do {
            async let featured = client.featured(includeTypes: kind.itemType)
            async let recent = client.latest(includeTypes: kind.itemType)
            let (featuredItems, recentItems) = try await (featured, recent)
            if hero == nil {
                hero = featuredItems.first
            }
            latest = recentItems
            error = nil
        } catch {
            if isCancellation(error) { return }
            self.error = error.localizedDescription
        }
        loaded = true
        let rows = await client.genreRows(includeTypes: kind.itemType, maxRows: 10)
        if !rows.isEmpty {
            genreRows = rows
        }
    }
}

/// The Movies and TV Shows tabs: a featured banner, then rows by genre.
struct LibraryView: View {
    let kind: LibraryKind
    @EnvironmentObject private var accounts: AccountStore
    @StateObject private var model = LibraryModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let client = accounts.jellyfinClient {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            if let hero = model.hero {
                                HeroBanner(item: hero, client: client)
                            }
                            NavigationLink(value: kind) {
                                HStack {
                                    Image(systemName: "square.grid.3x3.fill")
                                    Text("Browse all \(kind.title.lowercased())")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            if let error = model.error {
                                ErrorBanner(message: error)
                            }
                            PosterRow(title: "Recently Added", items: model.latest, client: client)
                            ForEach(model.genreRows) { row in
                                PosterRow(title: row.title, items: row.items, client: client)
                            }
                            if !model.loaded {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 80)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        model.hero = nil
                        await model.load(kind, client: client)
                    }
                    .task(id: client.session.accessToken) {
                        await model.load(kind, client: client)
                    }
                } else {
                    SignInPrompt(service: "Jellyfin", systemImage: kind.systemImage,
                                 message: "Sign in to your Jellyfin server to browse \(kind.title.lowercased()).")
                }
            }
            .navigationTitle(kind.title)
            .hearthChrome()
            .jellyfinDestinations()
        }
        .miniPlayerInset()
    }
}

/// Every movie or show as a poster grid, loaded page by page.
struct AllItemsGrid: View {
    enum Sort: String, CaseIterable, Identifiable {
        case name = "A–Z"
        case added = "Recently added"
        case year = "Release year"
        case rating = "Rating"

        var id: String { rawValue }

        var sortBy: String {
            switch self {
            case .name: return "SortName"
            case .added: return "DateCreated,SortName"
            case .year: return "ProductionYear,SortName"
            case .rating: return "CommunityRating,SortName"
            }
        }

        var descending: Bool { self != .name }
    }

    let kind: LibraryKind
    @EnvironmentObject private var accounts: AccountStore
    @State private var items: [JFItem] = []
    @State private var total = Int.max
    @State private var isLoading = false
    @State private var sort: Sort = .name
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            if let error {
                ErrorBanner(message: error).padding(.top, 12)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        PosterCard(url: accounts.jellyfinClient?.posterURL(item), title: item.title, width: nil, progress: item.progress)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await loadMore() }
                        }
                    }
                }
            }
            .padding(16)
            if isLoading {
                ProgressView().padding()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: sort) {
            items = []
            total = Int.max
            await loadMore()
        }
    }

    private func loadMore() async {
        guard let client = accounts.jellyfinClient, !isLoading, items.count < total else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.browse(includeTypes: kind.itemType, sortBy: sort.sortBy,
                                               descending: sort.descending, start: items.count, limit: 60)
            items += page.items
            total = page.totalRecordCount ?? items.count
            error = nil
        } catch {
            if !isCancellation(error) {
                self.error = error.localizedDescription
            }
        }
    }
}
