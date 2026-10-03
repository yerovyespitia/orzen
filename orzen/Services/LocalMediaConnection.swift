import Foundation
import Network

struct LocalMediaSearchRequest: Codable {
    let item: CatalogItem
    let episode: CatalogEpisode?
    let includeSpanish: Bool
    let forceRefresh: Bool
}

struct LocalMediaDownloadRequest: Codable {
    let item: CatalogItem
    let episode: CatalogEpisode?
    let result: TorrentSearchResult
}

struct LocalMediaPairRequest: Codable { let code: String }
struct LocalMediaPairResponse: Codable { let token: String }
struct LocalMediaActionResponse: Codable { let success: Bool }

struct LocalMediaProgressRecord: Codable {
    let key: String
    let entry: PlaybackProgressEntry?
    let updatedAt: Date
    let isDeleted: Bool

    init(entry: PlaybackProgressEntry) {
        key = entry.id
        self.entry = entry
        updatedAt = entry.updatedAt
        isDeleted = false
    }

    init(deletedKey key: String, updatedAt: Date) {
        self.key = key
        entry = nil
        self.updatedAt = updatedAt
        isDeleted = true
    }
}

struct LocalMediaProgressSyncRequest: Codable {
    let records: [LocalMediaProgressRecord]
}

struct LocalMediaProgressSyncResponse: Codable {
    let records: [LocalMediaProgressRecord]
}

struct LocalMediaCollectionsSyncRequest: Codable {
    let collections: LocalMediaCollections
}

struct LocalMediaCollectionsSyncResponse: Codable {
    let collections: LocalMediaCollections
}

#if os(macOS)
@MainActor
final class LocalMediaServer: ObservableObject {
    static let shared = LocalMediaServer()
    static let port: UInt16 = {
        #if DEBUG
        if let value = LocalMediaServiceRuntime.testValue("ORZEN_SERVICE_TEST_PORT"),
           let port = UInt16(value), port > 1024 { return port }
        #endif
        return 8937
    }()

    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    let pairingCode: String
    let hostName: String
    private let token: String
    private var listener: NWListener?
    private var downloadManager: LocalMediaDownloadManager?
    private var failedPairings: [Date] = []
    private let queue = DispatchQueue(label: "Orzen.LocalMediaServer")

    private init() {
        let defaults = LocalMediaServiceRuntime.defaults
        let credentials = LocalMediaServiceRuntime.credentials(defaults: defaults)
        pairingCode = credentials.code
        token = credentials.token
        hostName = LocalMediaServiceRuntime.hostName
    }

    func start() {
        guard LocalMediaServiceRuntime.isService, listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.service = NWListener.Service(name: "Orzen on \(LocalMediaServiceRuntime.computerName)", type: "_orzen._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        guard let self else { return }
                        self.isRunning = true
                        self.errorMessage = nil
                        self.downloadManager = LocalMediaDownloadManager.shared
                    case .failed(let error): self?.isRunning = false; self?.errorMessage = error.localizedDescription
                    case .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        downloadManager?.shutdown()
        downloadManager = nil
        isRunning = false
    }

    func mediaURL(for version: LocalMediaVersion) -> URL? {
        guard version.status == .completed else { return nil }
        return URL(string: "http://127.0.0.1:\(Self.port)/media/\(version.id.uuidString)?token=\(token)")
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var data = accumulated
                if let chunk { data.append(chunk) }
                guard data.count <= 16_000_000, error == nil else { connection.cancel(); return }
                if let request = HTTPRequest(data: data) {
                    await self.respond(to: request, connection: connection)
                } else if !isComplete {
                    self.receive(connection, accumulated: data)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, connection: NWConnection) async {
        if request.path == "/pair", request.method == "POST" {
            failedPairings.removeAll { Date().timeIntervalSince($0) > 60 }
            guard failedPairings.count < 5 else {
                sendError(429, "Too many pairing attempts. Try again in one minute.", to: connection)
                return
            }
            if let input = try? JSONDecoder().decode(LocalMediaPairRequest.self, from: request.body), input.code == pairingCode {
                failedPairings.removeAll()
                sendJSON(LocalMediaPairResponse(token: token), to: connection)
            } else {
                failedPairings.append(Date())
                sendError(401, "Incorrect pairing code.", to: connection)
            }
            return
        }
        guard request.token == token else { sendError(401, "Pair with the Mac again.", to: connection); return }
        let parts = request.path.split(separator: "/").map(String.init)
        do {
            if request.method == "GET" && parts == ["snapshot"] {
                sendJSON(LocalMediaLibraryStore.shared.snapshot, to: connection)
            } else if request.method == "POST" && parts == ["configuration"],
                      case .hostPort(let host, _) = connection.endpoint,
                      host == NWEndpoint.Host("127.0.0.1") || host == NWEndpoint.Host("::1") {
                let input = try JSONDecoder().decode(LocalMediaSearchConfiguration.self, from: request.body)
                let settings = TorznabSettingsStore.shared
                settings.endpointText = input.endpoint
                settings.apiKey = input.apiKey
                settings.save()
                guard settings.saveMessage == "Search provider saved." else {
                    throw LocalMediaError.engine(settings.saveMessage ?? "Search configuration failed.")
                }
                sendJSON(LocalMediaActionResponse(success: true), to: connection)
            } else if request.method == "GET" && parts == ["library"] {
                sendJSON(LocalMediaLibraryStore.shared.versions, to: connection)
            } else if request.method == "POST" && parts == ["metadata"] {
                let item = try JSONDecoder().decode(CatalogItem.self, from: request.body)
                let library = LocalMediaLibraryStore.shared
                for version in library.versions where version.catalogID == item.id && version.contentType == item.cinemetaType {
                    var updated = version
                    updated.catalogItem = item
                    try library.update(updated)
                }
                sendJSON(LocalMediaActionResponse(success: true), to: connection)
            } else if request.method == "POST" && parts == ["progress"] {
                let input = try JSONDecoder().decode(LocalMediaProgressSyncRequest.self, from: request.body)
                let records = PlaybackProgressStore.shared.mergeLocalProgress(input.records)
                sendJSON(LocalMediaProgressSyncResponse(records: records), to: connection)
            } else if request.method == "POST" && parts == ["collections"] {
                let input = try JSONDecoder().decode(LocalMediaCollectionsSyncRequest.self, from: request.body)
                let collections = CollectionStore.shared.mergeLocalCollections(input.collections)
                sendJSON(LocalMediaCollectionsSyncResponse(collections: collections), to: connection)
            } else if request.method == "POST" && parts == ["search"] {
                let input = try JSONDecoder().decode(LocalMediaSearchRequest.self, from: request.body)
                let results = try await LocalTorrentSearchClient.search(item: input.item,
                    episode: input.episode, includeSpanish: input.includeSpanish, forceRefresh: input.forceRefresh)
                sendJSON(results, to: connection)
            } else if request.method == "POST" && parts == ["downloads"] {
                let input = try JSONDecoder().decode(LocalMediaDownloadRequest.self, from: request.body)
                let version = try await LocalMediaDownloadManager.shared.start(item: input.item, episode: input.episode, result: input.result)
                sendJSON(version, to: connection)
            } else if request.method == "POST" && parts.count == 3 && parts[0] == "downloads" && parts[2] == "pause" {
                guard let uuid = UUID(uuidString: parts[1]) else { throw LocalMediaError.invalidTorrent }
                try LocalMediaDownloadManager.shared.pause(uuid)
                sendJSON(LocalMediaActionResponse(success: true), to: connection)
            } else if request.method == "POST" && parts.count == 3 && parts[0] == "downloads" && parts[2] == "resume" {
                guard let uuid = UUID(uuidString: parts[1]) else { throw LocalMediaError.invalidTorrent }
                try LocalMediaDownloadManager.shared.resume(uuid)
                sendJSON(LocalMediaActionResponse(success: true), to: connection)
            } else if request.method == "DELETE" && parts.count == 2 && parts[0] == "downloads" {
                guard let uuid = UUID(uuidString: parts[1]) else { throw LocalMediaError.invalidTorrent }
                try LocalMediaDownloadManager.shared.delete(uuid)
                sendJSON(LocalMediaActionResponse(success: true), to: connection)
            } else if (request.method == "GET" || request.method == "HEAD") && parts.count == 2 && parts[0] == "media" {
                guard let uuid = UUID(uuidString: parts[1]),
                      let version = LocalMediaLibraryStore.shared.versions.first(where: { $0.id == uuid && $0.status == .completed }),
                      let file = LocalMediaLibraryStore.shared.fileURL(for: version) else {
                    sendError(404, "Video unavailable.", to: connection); return
                }
                sendMedia(file, range: request.headers["range"], headOnly: request.method == "HEAD", to: connection)
            } else { sendError(404, "Not found.", to: connection)
            }
        } catch {
            sendError(400, error.localizedDescription, to: connection)
        }
    }

    private func sendJSON<T: Encodable>(_ value: T, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(value) else { sendError(500, "Encoding failed.", to: connection); return }
        send(status: 200, headers: ["Content-Type": "application/json"], body: data, to: connection)
    }

    private func sendError(_ code: Int, _ message: String, to connection: NWConnection) {
        send(status: code, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(message.utf8), to: connection)
    }

    private func send(status: Int, headers: [String: String], body: Data, to connection: NWConnection) {
        let reason = [200: "OK", 206: "Partial Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 416: "Range Not Satisfiable", 429: "Too Many Requests", 500: "Internal Server Error"][status] ?? "Error"
        var text = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (key, value) in headers { text += "\(key): \(value)\r\n" }
        text += "\r\n"
        var packet = Data(text.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendMedia(_ url: URL, range: String?, headOnly: Bool, to connection: NWConnection) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              let file = try? FileHandle(forReadingFrom: url) else {
            sendError(404, "Video unavailable.", to: connection); return
        }
        let size = fileSize.int64Value
        guard size > 0 else { try? file.close(); sendError(404, "Video unavailable.", to: connection); return }
        var start: Int64 = 0
        var end = size - 1
        var partial = false
        if let range, range.lowercased().hasPrefix("bytes=") {
            let values = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            guard values.count == 2 else {
                try? file.close(); send(status: 416, headers: ["Content-Range": "bytes */\(size)"], body: Data(), to: connection); return
            }
            if values[0].isEmpty {
                guard let suffixLength = Int64(values[1]), suffixLength > 0 else {
                    try? file.close(); send(status: 416, headers: ["Content-Range": "bytes */\(size)"], body: Data(), to: connection); return
                }
                start = size - min(suffixLength, size)
            } else {
                guard let parsed = Int64(values[0]), parsed >= 0, parsed < size else {
                    try? file.close(); send(status: 416, headers: ["Content-Range": "bytes */\(size)"], body: Data(), to: connection); return
                }
                start = parsed
                if !values[1].isEmpty {
                    guard let requestedEnd = Int64(values[1]) else {
                        try? file.close(); send(status: 416, headers: ["Content-Range": "bytes */\(size)"], body: Data(), to: connection); return
                    }
                    end = min(requestedEnd, end)
                }
            }
            guard end >= start else { try? file.close(); sendError(416, "Invalid range.", to: connection); return }
            partial = true
        }
        let mime = ["mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "mkv": "video/x-matroska", "webm": "video/webm", "avi": "video/x-msvideo"][url.pathExtension.lowercased()] ?? "application/octet-stream"
        var header = "HTTP/1.1 \(partial ? "206 Partial Content" : "200 OK")\r\nContent-Type: \(mime)\r\nContent-Length: \(end - start + 1)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n"
        if partial { header += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        header += "\r\n"
        if headOnly {
            try? file.close()
            connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        try? file.seek(toOffset: UInt64(start))
        connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
            guard error == nil else { try? file.close(); connection.cancel(); return }
            Self.sendChunk(file: file, remaining: end - start + 1, connection: connection)
        })
    }

    private nonisolated static func sendChunk(file: FileHandle, remaining: Int64, connection: NWConnection) {
        guard remaining > 0 else { try? file.close(); connection.cancel(); return }
        let data = (try? file.read(upToCount: Int(min(remaining, 256 * 1024)))) ?? nil
        guard let data, !data.isEmpty else { try? file.close(); connection.cancel(); return }
        connection.send(content: data, completion: .contentProcessed { error in
            guard error == nil else { try? file.close(); connection.cancel(); return }
            sendChunk(file: file, remaining: remaining - Int64(data.count), connection: connection)
        })
    }
}
#endif

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let token: String?

    init?(data: Data) {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        let headers = lines.dropFirst().compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }.reduce(into: [String: String]()) { result, pair in result[pair.0] = pair.1 }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[boundary.upperBound...]
        guard body.count >= length else { return nil }
        guard let components = URLComponents(string: String(first[1])) else { return nil }
        method = String(first[0])
        path = components.path
        self.headers = headers
        self.body = Data(body.prefix(length))
        token = headers["x-orzen-token"] ?? components.queryItems?.first(where: { $0.name == "token" })?.value
    }
}
