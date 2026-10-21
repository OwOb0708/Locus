import Combine
import Foundation
import MapKit

struct PikminPost: Decodable, Identifiable, Equatable, Sendable {
    enum Kind: String, Decodable, Hashable, Sendable {
        case mushroom = "Mushroom"
        case flower = "Big Flower"

        var title: String {
            switch self {
            case .mushroom: "菇點"
            case .flower: "花點"
            }
        }

        var symbol: String {
            switch self {
            case .mushroom: "🍄"
            case .flower: "🌸"
            }
        }
    }

    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let kind: Kind
    let country: String
    private let thumbnailPath: String

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

    private enum CodingKeys: String, CodingKey {
        case id, name, country
        case latitude = "lat"
        case longitude = "lng"
        case kind = "type"
        case thumbnailPath = "thumb"
    }
}

@MainActor
final class PikminPostStore: ObservableObject {
    @Published private(set) var mushroomPosts: [PikminPost] = []
    @Published private(set) var flowerPosts: [PikminPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var allMushroomPosts: [PikminPost] = []
    private var allFlowerPosts: [PikminPost] = []
    private var hasLoaded = false

    var mushroomCount: Int { allMushroomPosts.count }
    var flowerCount: Int { allFlowerPosts.count }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            guard let url = Bundle.main.url(forResource: "PikminPosts", withExtension: "json") else {
                throw PikminPostError.missingBundledData
            }

            let posts = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                return try JSONDecoder().decode([PikminPost].self, from: data)
            }.value

            allMushroomPosts = posts.filter { $0.kind == .mushroom }
            allFlowerPosts = posts.filter { $0.kind == .flower }
            mushroomPosts = allMushroomPosts
            flowerPosts = allFlowerPosts
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func updateSearch(_ query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            mushroomPosts = allMushroomPosts
            flowerPosts = allFlowerPosts
            return
        }

        mushroomPosts = allMushroomPosts.filter { post in
            post.name.localizedCaseInsensitiveContains(normalized)
                || post.country.localizedCaseInsensitiveContains(normalized)
        }
        flowerPosts = allFlowerPosts.filter { post in
            post.name.localizedCaseInsensitiveContains(normalized)
                || post.country.localizedCaseInsensitiveContains(normalized)
        }
    }
}

private enum PikminPostError: LocalizedError {
    case missingBundledData

    var errorDescription: String? {
        "找不到內建的 Pikmin 地點資料。請重新安裝此版本。"
    }
}
