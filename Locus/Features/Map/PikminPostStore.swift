import Combine
import Foundation
import MapKit

struct PikminPost: Decodable, Identifiable, Equatable, Sendable {
    enum Kind: String, Decodable, CaseIterable, Hashable, Sendable {
        case mushroom = "Mushroom"
        case flower = "Big Flower"
        case hidden = "Hidden"
        case seedling = "Seedling"

        var title: String {
            switch self {
            case .mushroom: "菇點"
            case .flower: "花點"
            case .hidden: "隱藏"
            case .seedling: "金盆"
            }
        }

        var symbol: String {
            switch self {
            case .mushroom: "🍄"
            case .flower: "🌸"
            case .hidden: "🖼️"
            case .seedling: "🟡"
            }
        }
    }

    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let kind: Kind
    let country: String
    let location: String
    private let thumbnailPath: String

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: Kind,
        country: String,
        location: String,
        thumbnailPath: String
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.country = country
        self.location = location
        self.thumbnailPath = thumbnailPath
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? values.decode(String.self, forKey: .id) {
            id = "pikminposts:\(stringID)"
        } else {
            id = "pikminposts:\(try values.decode(Int.self, forKey: .id))"
        }
        name = try values.decode(String.self, forKey: .name)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        kind = try values.decode(Kind.self, forKey: .kind)
        country = try values.decodeIfPresent(String.self, forKey: .country) ?? ""
        location = try values.decodeIfPresent(String.self, forKey: .location) ?? ""
        thumbnailPath = try values.decodeIfPresent(String.self, forKey: .thumbnailPath) ?? ""
    }

    var thumbnailURL: URL? {
        guard !thumbnailPath.isEmpty else { return nil }
        if let absoluteURL = URL(string: thumbnailPath), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: thumbnailPath, relativeTo: URL(string: "https://pikminposts.com/"))?.absoluteURL
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func merging(_ newer: PikminPost) -> PikminPost {
        PikminPost(
            id: id,
            name: newer.name.isEmpty ? name : newer.name,
            latitude: newer.latitude,
            longitude: newer.longitude,
            kind: kind,
            country: newer.country.isEmpty ? country : newer.country,
            location: newer.location.isEmpty ? location : newer.location,
            thumbnailPath: newer.thumbnailPath.isEmpty ? thumbnailPath : newer.thumbnailPath
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, country, location
        case latitude = "lat"
        case longitude = "lng"
        case kind = "type"
        case thumbnailPath = "thumb"
    }
}

private struct PickminPublicPostcard: Decodable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let imageURL: String?
    let location: String?
    let country: String?
    let category: String

    var post: PikminPost? {
        let kind: PikminPost.Kind
        switch category {
        case "mushroom": kind = .mushroom
        case "flower": kind = .flower
        case "hidden": kind = .hidden
        case "seedling": kind = .seedling
        default: return nil
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return PikminPost(
            id: "pickmin:\(id)",
            name: name,
            latitude: latitude,
            longitude: longitude,
            kind: kind,
            country: country ?? "",
            location: location ?? "",
            thumbnailPath: imageURL ?? ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, location, country
        case latitude = "lat"
        case longitude = "lng"
        case imageURL = "image_url"
        case category = "cat"
    }
}

@MainActor
final class PikminPostStore: ObservableObject {
    @Published private(set) var mushroomPosts: [PikminPost] = []
    @Published private(set) var flowerPosts: [PikminPost] = []
    @Published private(set) var hiddenPosts: [PikminPost] = []
    @Published private(set) var seedlingPosts: [PikminPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingSeedlings = false
    @Published private(set) var errorMessage: String?

    private var allMushroomPosts: [PikminPost] = []
    private var allFlowerPosts: [PikminPost] = []
    private var allHiddenPosts: [PikminPost] = []
    private var allSeedlingPosts: [PikminPost] = []
    private var currentQuery = ""
    private var hasLoaded = false

    var mushroomCount: Int { allMushroomPosts.count }
    var flowerCount: Int { allFlowerPosts.count }
    var hiddenCount: Int { allHiddenPosts.count }
    var seedlingCount: Int { allSeedlingPosts.count }

    func posts(for kind: PikminPost.Kind) -> [PikminPost] {
        switch kind {
        case .mushroom: mushroomPosts
        case .flower: flowerPosts
        case .hidden: hiddenPosts
        case .seedling: seedlingPosts
        }
    }

    func count(for kind: PikminPost.Kind) -> Int {
        switch kind {
        case .mushroom: mushroomCount
        case .flower: flowerCount
        case .hidden: hiddenCount
        case .seedling: seedlingCount
        }
    }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            guard let pikminPostsURL = Bundle.main.url(forResource: "PikminPosts", withExtension: "json"),
                  let pickminSnapshotURL = Bundle.main.url(forResource: "PickminPostcards", withExtension: "json") else {
                throw PikminPostError.missingBundledData
            }

            let posts = try await Task.detached(priority: .userInitiated) {
                let baseData = try Data(contentsOf: pikminPostsURL, options: .mappedIfSafe)
                let snapshotData = try Data(contentsOf: pickminSnapshotURL, options: .mappedIfSafe)
                let base = try JSONDecoder().decode([PikminPost].self, from: baseData)
                let snapshot = try JSONDecoder().decode([PickminPublicPostcard].self, from: snapshotData)
                    .compactMap(\.post)
                return Self.mergeDuplicates(base + snapshot)
            }.value

            setAllPosts(posts)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        if hasLoaded {
            await refreshSeedlings()
        }
    }

    func refreshSeedlings() async {
        guard hasLoaded, !isRefreshingSeedlings else { return }
        isRefreshingSeedlings = true
        defer { isRefreshingSeedlings = false }

        do {
            var components = URLComponents(string: "https://easslafdarosxlmblvnq.supabase.co/rest/v1/public_postcards")
            components?.queryItems = [
                URLQueryItem(name: "select", value: "id,name,lat,lng,image_url,location,country,cat"),
                URLQueryItem(name: "cat", value: "eq.seedling"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1000")
            ]
            guard let url = components?.url else { throw PikminPostError.invalidLiveURL }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(Self.pickminPublicAPIKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(Self.pickminPublicAPIKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
                throw PikminPostError.invalidLiveResponse
            }

            let liveSeedlings = try JSONDecoder().decode([PickminPublicPostcard].self, from: data)
                .compactMap(\.post)
            // A successful response is authoritative so deleted/retired gold pots
            // disappear immediately; the snapshot is only the offline fallback.
            allSeedlingPosts = Self.mergeDuplicates(liveSeedlings)
            updateSearch(currentQuery)
        } catch {
            // The bundled snapshot remains available when the live source is offline.
            NSLog("[Locus] 金盆即時更新失敗：%@", error.localizedDescription)
        }
    }

    func updateSearch(_ query: String) {
        currentQuery = query
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            mushroomPosts = allMushroomPosts
            flowerPosts = allFlowerPosts
            hiddenPosts = allHiddenPosts
            seedlingPosts = allSeedlingPosts
            return
        }

        mushroomPosts = Self.filtered(allMushroomPosts, query: normalized)
        flowerPosts = Self.filtered(allFlowerPosts, query: normalized)
        hiddenPosts = Self.filtered(allHiddenPosts, query: normalized)
        seedlingPosts = Self.filtered(allSeedlingPosts, query: normalized)
    }

    private func setAllPosts(_ posts: [PikminPost]) {
        allMushroomPosts = posts.filter { $0.kind == .mushroom }
        allFlowerPosts = posts.filter { $0.kind == .flower }
        allHiddenPosts = posts.filter { $0.kind == .hidden }
        allSeedlingPosts = posts.filter { $0.kind == .seedling }
        updateSearch(currentQuery)
    }

    private nonisolated static func filtered(_ posts: [PikminPost], query: String) -> [PikminPost] {
        posts.filter { post in
            post.name.localizedCaseInsensitiveContains(query)
                || post.country.localizedCaseInsensitiveContains(query)
                || post.location.localizedCaseInsensitiveContains(query)
        }
    }

    private nonisolated static func mergeDuplicates(_ posts: [PikminPost]) -> [PikminPost] {
        var merged: [PikminPost] = []
        var indexByLocation: [String: Int] = [:]
        for post in posts {
            let latitudeKey = Int((post.latitude * 100_000).rounded())
            let longitudeKey = Int((post.longitude * 100_000).rounded())
            let key = "\(post.kind.rawValue)|\(latitudeKey)|\(longitudeKey)"
            if let index = indexByLocation[key] {
                merged[index] = merged[index].merging(post)
            } else {
                indexByLocation[key] = merged.count
                merged.append(post)
            }
        }
        return merged
    }

    // Supabase anon keys are public client credentials; row-level security limits access.
    private nonisolated static let pickminPublicAPIKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVhc3NsYWZkYXJvc3hsbWJsdm5xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMDcyMTksImV4cCI6MjA5NDU4MzIxOX0.VDExxbVXld4MHlDiYAdX0N0DmOijVKXv4kTa5uhJpa8"
}

private enum PikminPostError: LocalizedError {
    case missingBundledData
    case invalidLiveURL
    case invalidLiveResponse

    var errorDescription: String? {
        switch self {
        case .missingBundledData:
            "找不到內建的 Pikmin 地點資料。請重新安裝此版本。"
        case .invalidLiveURL, .invalidLiveResponse:
            "無法取得最新金盆資料，已改用內建快照。"
        }
    }
}
