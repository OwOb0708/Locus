import CoreLocation
import Foundation
import MapKit

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "Locus", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到路線"])
        }
        return sample(polyline: route.polyline, every: 12)
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1, meters.isFinite, meters > 0 else { return coordinates }
        var sampled = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let steps = max(1, Int(ceil(dist / meters)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                sampled.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        return sampled
    }
}

enum GPXCodec {
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize, fileSize > 25 * 1024 * 1024 {
            throw NSError(domain: "Locus", code: 3, userInfo: [NSLocalizedDescriptionKey: "GPX 檔案超過 25 MB，為避免 App 記憶體不足，請先縮小檔案。"])
        }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var coords: [CLLocationCoordinate2D] = []
        let pattern = #"lat="([^"]+)"[^>]*lon="([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let latR = Range(match.range(at: 1), in: text),
                  let lonR = Range(match.range(at: 2), in: text),
                  let lat = Double(text[latR]),
                  let lon = Double(text[lonR]) else { return }
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if CLLocationCoordinate2DIsValid(coordinate), coords.count < 200_000 {
                coords.append(coordinate)
            }
        }
        // Also support lon before lat
        if coords.isEmpty {
            let alt = #"lon="([^"]+)"[^>]*lat="([^"]+)""#
            let altRegex = try NSRegularExpression(pattern: alt)
            altRegex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match,
                      let lonR = Range(match.range(at: 1), in: text),
                      let latR = Range(match.range(at: 2), in: text),
                      let lon = Double(text[lonR]),
                      let lat = Double(text[latR]) else { return }
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if CLLocationCoordinate2DIsValid(coordinate), coords.count < 200_000 {
                    coords.append(coordinate)
                }
            }
        }
        guard !coords.isEmpty else {
            throw NSError(domain: "Locus", code: 2, userInfo: [NSLocalizedDescriptionKey: "GPX 檔案裡沒有找到任何軌跡點"])
        }
        return coords
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        var body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(name)</name>
            <trkseg>

        """
        for c in coordinates {
            body += String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>\n", c.latitude, c.longitude)
        }
        body += """
            </trkseg>
          </trk>
        </gpx>
        """
        return body
    }
}
