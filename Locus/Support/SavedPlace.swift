import CoreLocation
import Foundation
import SwiftUI

/// Small fixed palette so categories stay visually consistent instead of an
/// unbounded color picker — pick one, give the category a name, done.
enum PlaceCategoryColor: String, CaseIterable, Identifiable, Codable {
    case red, orange, yellow, green, teal, blue, purple, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return Color(red: 0.92, green: 0.32, blue: 0.36)
        case .orange: return Color(red: 0.95, green: 0.55, blue: 0.28)
        case .yellow: return Color(red: 0.95, green: 0.78, blue: 0.25)
        case .green: return Color(red: 0.30, green: 0.86, blue: 0.55)
        case .teal: return Color(red: 0.35, green: 0.78, blue: 0.72)
        case .blue: return Color(red: 0.30, green: 0.55, blue: 0.92)
        case .purple: return Color(red: 0.62, green: 0.45, blue: 0.92)
        case .pink: return Color(red: 0.92, green: 0.45, blue: 0.70)
        }
    }
}

struct SavedPlace: Identifiable, Codable, Equatable {
    var id: String { "\(latitude),\(longitude)" }
    var name: String
    var latitude: Double
    var longitude: Double
    /// Freeform label the person types themselves (e.g. "補給點", "A 區") —
    /// optional so existing saved places without one decode unaffected.
    var categoryName: String? = nil
    var categoryColor: PlaceCategoryColor? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Trimmed, non-empty category name, or nil if uncategorized.
    var displayCategory: String? {
        guard let categoryName else { return nil }
        let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedColor: Color {
        categoryColor?.color ?? Color.primary.opacity(0.4)
    }

    static func load(key: String) -> [SavedPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ places: [SavedPlace], key: String) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
