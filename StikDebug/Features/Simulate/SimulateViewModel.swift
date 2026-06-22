import Foundation
import CoreLocation
import SwiftUI
import MapKit
import Combine

@MainActor
final class SimulateViewModel: ObservableObject {

    // MARK: - Route editor state
    @Published var waypoints: [Waypoint] = []
    @Published var routeName: String = "New Route"
    @Published var selectedMode: MovementMode = .drive
    @Published var customSpeedMph: Double = 30
    @Published var speedMultiplier: Double = 1.0
    @Published var loopEnabled: Bool = false
    @Published var mapPosition: MapCameraPosition = .automatic

    // MARK: - MKDirections route overlay (optional, for Drive/Bus)
    @Published var routePolyline: MKPolyline?
    @Published var isCalculatingRoute = false

    // MARK: - Playback
    @Published var isPlaying: Bool = false
    @Published var isPreparing: Bool = false
    @Published var stats: RouteStats = RouteStats()
    @Published var currentCoordinate: CLLocationCoordinate2D?

    // MARK: - File import
    @Published var showFilePicker = false
    @Published var importError: String?

    // MARK: - Save/load
    @Published var showSaveSheet = false

    let player = RoutePlayer()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Mirror player state
        player.$isPlaying.assign(to: &$isPlaying)
        player.$isPreparing.assign(to: &$isPreparing)
        player.$stats.assign(to: &$stats)
        player.$currentCoordinate.assign(to: &$currentCoordinate)
    }

    // MARK: - Waypoint editing

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        waypoints.append(Waypoint(coordinate: coordinate))
        refreshRoutePolyline()
    }

    func move(waypoint: Waypoint, to coordinate: CLLocationCoordinate2D) {
        guard let idx = waypoints.firstIndex(where: { $0.id == waypoint.id }) else { return }
        waypoints[idx].latitude  = coordinate.latitude
        waypoints[idx].longitude = coordinate.longitude
        refreshRoutePolyline()
    }

    func deleteWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        refreshRoutePolyline()
    }

    func moveWaypointsInList(from source: IndexSet, to destination: Int) {
        waypoints.move(fromOffsets: source, toOffset: destination)
        refreshRoutePolyline()
    }

    // MARK: - Prepare and play

    func prepare() async {
        let coords = waypoints.map(\.coordinate)
        guard !coords.isEmpty else { return }

        var profile = MovementProfile.default(for: selectedMode)
        if selectedMode == .custom {
            let mps = customSpeedMph * 0.44704
            profile = .custom(speedMps: mps)
        }

        player.waypoints        = coords
        player.profile          = profile
        player.speedMultiplier  = speedMultiplier
        player.loop             = loopEnabled

        await player.prepare()
    }

    func playPause() {
        if isPlaying { player.pause() } else { player.play() }
    }

    func stop() {
        player.stop()
    }

    func scrub(to progress: Double) {
        player.scrub(to: progress)
    }

    // MARK: - GPX import

    func handleImport(url: URL) {
        do {
            let coords = try GPXImporter.parse(url: url)
            waypoints = coords.map { Waypoint(coordinate: $0) }
            refreshRoutePolyline()
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Load from library

    func load(_ route: SavedRoute) {
        routeName       = route.name
        selectedMode    = route.mode
        waypoints       = route.waypoints
        refreshRoutePolyline()
    }

    // MARK: - Save to library

    func saveToLibrary() {
        var route = SavedRoute(
            name: routeName.isEmpty ? "Unnamed Route" : routeName,
            mode: selectedMode,
            waypoints: waypoints,
            stops: []
        )
        if selectedMode == .custom {
            route.profileOverride = ProfileOverride(
                cruiseSpeedMps: customSpeedMph * 0.44704,
                speedMultiplier: speedMultiplier,
                loop: loopEnabled
            )
        }
        RouteStore.shared.save(route)
    }

    // MARK: - Route overlay (MKDirections for drive/bus)

    private func refreshRoutePolyline() {
        routePolyline = nil
        guard waypoints.count >= 2,
              (selectedMode == .drive || selectedMode == .bus) else {
            let coords = waypoints.map(\.coordinate)
            if !coords.isEmpty {
                var mutable = coords
                routePolyline = MKPolyline(coordinates: &mutable, count: mutable.count)
            }
            return
        }

        let coords = waypoints.map(\.coordinate)
        var mutable = coords
        routePolyline = MKPolyline(coordinates: &mutable, count: mutable.count)

        // Optionally calculate directions (best-effort; fails gracefully)
        Task {
            await calculateDirections(from: coords.first!, to: coords.last!)
        }
    }

    private func calculateDirections(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        let request = MKDirections.Request()
        if #available(iOS 26.0, *) {
            request.source = MKMapItem(
                location: CLLocation(latitude: from.latitude, longitude: from.longitude),
                address: nil
            )
            request.destination = MKMapItem(
                location: CLLocation(latitude: to.latitude, longitude: to.longitude),
                address: nil
            )
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        }
        request.transportType = selectedMode == .bus ? .transit : .automobile
        isCalculatingRoute = true
        if let response = try? await MKDirections(request: request).calculate(),
           let route = response.routes.first {
            routePolyline = route.polyline
        }
        isCalculatingRoute = false
    }
}
