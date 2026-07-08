import Foundation

struct StremioAddonManifest: Decodable, Sendable {
    struct Resource: Codable, Equatable, Sendable {
        let name: String
        let types: [String]?
        let idPrefixes: [String]?

        private enum CodingKeys: String, CodingKey {
            case name
            case types
            case idPrefixes
        }

        init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
            self.name = name
            self.types = types
            self.idPrefixes = idPrefixes
        }

        init(from decoder: Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                self.init(name: name)
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                types: try container.decodeIfPresent([String].self, forKey: .types),
                idPrefixes: try container.decodeIfPresent([String].self, forKey: .idPrefixes)
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(types, forKey: .types)
            try container.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
        }
    }

    let id: String
    let name: String
    let description: String?
    let types: [String]
    let resources: [Resource]
    let idPrefixes: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case types
        case resources
        case idPrefixes
    }
}

enum StremioManifestClient {
    static func fetchManifest(from manifestURL: URL) async throws -> StremioAddonManifest {
        let (data, response) = try await URLSession.shared.data(from: manifestURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(StremioAddonManifest.self, from: data)
    }
}
