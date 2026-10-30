import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int)
    case server(String)
    case unauthorized
    case notTheRightServer(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That server address doesn't look right. It should look like http://100.x.x.x:8096"
        case .http(let code):
            return "The server answered with an error (HTTP \(code))."
        case .server(let message):
            return message
        case .unauthorized:
            return "Wrong username or password, or your sign-in has expired. Sign in again in Settings."
        case .notTheRightServer(let service):
            return "Something answered at that address, but it doesn't look like \(service). Check the port number."
        }
    }
}

func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}

/// A plain coding key used by the Jellyfin decoder to turn `PascalCase` keys into `camelCase`.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum ServerAddress {
    /// Trims whitespace, adds `http://` when no scheme was typed and drops trailing slashes.
    static func normalize(_ raw: String) -> String {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = address.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            address = "http://" + address
        }
        while address.hasSuffix("/") {
            address.removeLast()
        }
        return address
    }
}

func queryItem(_ name: String, _ value: String) -> URLQueryItem {
    URLQueryItem(name: name, value: value)
}

func makeURL(base: String, path: String, query: [URLQueryItem] = []) -> URL? {
    guard var components = URLComponents(string: base + path) else { return nil }
    if !query.isEmpty {
        components.queryItems = (components.queryItems ?? []) + query
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
    return components.url
}

func appendingQuery(_ url: URL, _ query: [URLQueryItem]) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    components.queryItems = (components.queryItems ?? []) + query
    return components.url ?? url
}

let httpSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 20
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
}()

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    if total >= 3600 {
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
    return String(format: "%d:%02d", total / 60, total % 60)
}
