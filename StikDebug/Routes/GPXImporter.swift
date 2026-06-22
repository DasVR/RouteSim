import Foundation
import CoreLocation
import UniformTypeIdentifiers

// MARK: - Errors

enum GPXImportError: LocalizedError {
    case emptyFile
    case noCoordinates
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:       return "The selected file is empty."
        case .noCoordinates:   return "No valid coordinates found. Use GPX, GeoJSON, JSON, CSV, or plain text with lat/lon values."
        case .parseFailure(let msg): return "Parse error: \(msg)"
        }
    }
}

// MARK: - Supported types

enum GPXImporter {
    static let supportedTypes: [UTType] = [
        .plainText,
        .commaSeparatedText,
        .json,
        .xml,
        UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml,
        UTType(filenameExtension: "kml", conformingTo: .xml) ?? .xml,
        UTType(filenameExtension: "geojson", conformingTo: .json) ?? .json
    ]

    // MARK: - Main entry point

    static func parse(url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GPXImportError.emptyFile
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw GPXImportError.emptyFile }

        let coords: [CLLocationCoordinate2D]
        switch url.pathExtension.lowercased() {
        case "gpx":
            coords = parseGPX(data: data)
        case "kml":
            coords = parseKML(data: data)
        case "geojson", "json":
            coords = (try? parseGeoJSON(data: data)) ?? parseText(data: data)
        case "csv", "txt":
            coords = parseText(data: data)
        default:
            coords = parseGPX(data: data).nonEmpty
                ?? (try? parseGeoJSON(data: data))?.nonEmpty
                ?? parseText(data: data)
        }

        let valid = coords.filter { CLLocationCoordinate2DIsValid($0) }
        if valid.isEmpty { throw GPXImportError.noCoordinates }
        return valid
    }

    // MARK: - GPX / KML (XML)

    private static func parseGPX(data: Data) -> [CLLocationCoordinate2D] {
        let parser = XMLCoordinateParser(mode: .gpx)
        return parser.parse(data: data)
    }

    private static func parseKML(data: Data) -> [CLLocationCoordinate2D] {
        let parser = XMLCoordinateParser(mode: .kml)
        return parser.parse(data: data)
    }

    // MARK: - GeoJSON

    private static func parseGeoJSON(data: Data) throws -> [CLLocationCoordinate2D] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GPXImportError.parseFailure("Not valid JSON")
        }
        var coords: [CLLocationCoordinate2D] = []

        func extractCoords(from obj: Any) {
            if let arr = obj as? [[Double]], arr.first?.count ?? 0 >= 2 {
                coords += arr.compactMap { c in
                    let count = c.count
                    if count >= 2 { return CLLocationCoordinate2D(latitude: c[1], longitude: c[0]) }
                    return nil
                }
            } else if let arr = obj as? [Any] {
                arr.forEach { extractCoords(from: $0) }
            } else if let dict = obj as? [String: Any] {
                if let type = dict["type"] as? String {
                    if type == "Point", let c = dict["coordinates"] as? [Double], c.count >= 2 {
                        coords.append(CLLocationCoordinate2D(latitude: c[1], longitude: c[0]))
                    } else if let c = dict["coordinates"] {
                        extractCoords(from: c)
                    }
                }
                dict.values.forEach { extractCoords(from: $0) }
            }
        }
        extractCoords(from: json)
        return coords
    }

    // MARK: - Plain text / CSV

    private static func parseText(data: Data) -> [CLLocationCoordinate2D] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines)
        return lines.compactMap { line -> CLLocationCoordinate2D? in
            let tokens = line
                .components(separatedBy: CharacterSet(charactersIn: ",\t "))
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard tokens.count >= 2 else { return nil }
            let a = CLLocationCoordinate2D(latitude: tokens[0], longitude: tokens[1])
            let b = CLLocationCoordinate2D(latitude: tokens[1], longitude: tokens[0])
            if CLLocationCoordinate2DIsValid(a) { return a }
            if CLLocationCoordinate2DIsValid(b) { return b }
            return nil
        }
    }
}

// MARK: - XML parser helper

private final class XMLCoordinateParser: NSObject, XMLParserDelegate {
    enum Mode { case gpx, kml }
    private let mode: Mode
    private var coords: [CLLocationCoordinate2D] = []
    private var currentText = ""
    private var insideCoordinates = false

    init(mode: Mode) { self.mode = mode }

    func parse(data: Data) -> [CLLocationCoordinate2D] {
        coords = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return coords
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        switch mode {
        case .gpx:
            if element == "trkpt" || element == "wpt" || element == "rtept" {
                if let latStr = attributes["lat"], let lonStr = attributes["lon"],
                   let lat = Double(latStr), let lon = Double(lonStr) {
                    let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    if CLLocationCoordinate2DIsValid(c) { coords.append(c) }
                }
            }
        case .kml:
            if element == "coordinates" { insideCoordinates = true; currentText = "" }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if mode == .kml, insideCoordinates { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if mode == .kml, element == "coordinates" {
            insideCoordinates = false
            let tokens = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
            for token in tokens {
                let parts = token.split(separator: ",").compactMap { Double($0) }
                if parts.count >= 2 {
                    let c = CLLocationCoordinate2D(latitude: parts[1], longitude: parts[0])
                    if CLLocationCoordinate2DIsValid(c) { coords.append(c) }
                }
            }
        }
    }
}

private extension Array {
    var nonEmpty: [Element]? { isEmpty ? nil : self }
}
