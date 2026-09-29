import Foundation

#if os(iOS)
@MainActor
final class RemoteLocalMediaClient: ObservableObject {
    static let shared = RemoteLocalMediaClient()

    @Published var host: String { didSet {
        UserDefaults.standard.set(host, forKey: "localMedia.macHost")
        if host != oldValue { token = nil }
    } }
    @Published var pairingCode = ""
    @Published private(set) var isPaired: Bool
    @Published private(set) var message: String?
    private var token: String? { didSet {
        UserDefaults.standard.set(token, forKey: "localMedia.macToken")
        isPaired = token != nil
    } }

    private init() {
        host = UserDefaults.standard.string(forKey: "localMedia.macHost") ?? ""
        token = UserDefaults.standard.string(forKey: "localMedia.macToken")
        isPaired = token != nil
    }

    var baseURL: URL? {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let string = value.contains("://") ? value : "http://\(value)"
        guard var components = URLComponents(string: string), components.host != nil else { return nil }
        components.scheme = "http"
        if components.port == nil { components.port = 8937 }
        components.path = ""
        components.query = nil
        return components.url
    }

    func pair() async {
        do {
            let response: LocalMediaPairResponse = try await request("pair", method: "POST", body: LocalMediaPairRequest(code: pairingCode), authenticated: false)
            token = response.token
            pairingCode = ""
            message = nil
            await PlaybackProgressStore.shared.synchronizeLocalProgress()
        } catch {
            if case LocalMediaError.unauthorized = error {
                message = "Incorrect pairing code."
            } else {
                message = error.localizedDescription
            }
        }
    }

    func disconnect() {
        token = nil
        pairingCode = ""
        message = nil
    }

    func versions() async throws -> [LocalMediaVersion] {
        try await request("library")
    }

    func syncLocalProgress(_ records: [LocalMediaProgressRecord]) async throws -> [LocalMediaProgressRecord] {
        let response: LocalMediaProgressSyncResponse = try await request(
            "progress",
            method: "POST",
            body: LocalMediaProgressSyncRequest(records: records)
        )
        return response.records
    }

    func search(item: CatalogItem, episode: CatalogEpisode?, includeSpanish: Bool, forceRefresh: Bool = false) async throws -> [TorrentSearchResult] {
        try await request("search", method: "POST", body: LocalMediaSearchRequest(item: item, episode: episode,
            includeSpanish: includeSpanish, forceRefresh: forceRefresh))
    }

    func download(item: CatalogItem, episode: CatalogEpisode?, result: TorrentSearchResult) async throws -> LocalMediaVersion {
        try await request("downloads", method: "POST", body: LocalMediaDownloadRequest(item: item, episode: episode, result: result))
    }

    func action(_ action: String, id: UUID) async throws {
        let path = action == "delete" ? "downloads/\(id.uuidString)" : "downloads/\(id.uuidString)/\(action)"
        let _: LocalMediaActionResponse = try await request(path, method: action == "delete" ? "DELETE" : "POST")
    }

    func mediaURL(for version: LocalMediaVersion) -> URL? {
        guard version.status == .completed, let baseURL, let token else { return nil }
        return baseURL.appending(path: "media/\(version.id.uuidString)").appending(queryItems: [URLQueryItem(name: "token", value: token)])
    }

    private func request<Response: Decodable>(_ path: String, method: String = "GET", authenticated: Bool = true) async throws -> Response {
        try await perform(path, method: method, body: nil, authenticated: authenticated)
    }

    private func request<Response: Decodable, Body: Encodable>(_ path: String, method: String, body: Body, authenticated: Bool = true) async throws -> Response {
        try await perform(path, method: method, body: try JSONEncoder().encode(body), authenticated: authenticated)
    }

    private func perform<Response: Decodable>(_ path: String, method: String, body: Data?, authenticated: Bool) async throws -> Response {
        guard let baseURL else { throw LocalMediaError.macUnavailable }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = path == "search" ? 120 : 12
        if authenticated {
            guard let token else { throw LocalMediaError.unauthorized }
            request.setValue(token, forHTTPHeaderField: "X-Orzen-Token")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw LocalMediaError.macUnavailable
        }
        guard let response = response as? HTTPURLResponse else { throw LocalMediaError.macUnavailable }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw LocalMediaError.unauthorized }
            throw LocalMediaError.engine(String(data: data, encoding: .utf8) ?? "Mac request failed.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
#endif
