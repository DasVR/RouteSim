import Foundation
import CoreLocation
import SwiftUI
import MapKit
import Combine

enum RoutePlacementPhase: Equatable {
    case idle
    case pickingStart
    case pickingEnd
    case pickingHold
    case ready
}

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

    @Published var placementPhase: RoutePlacementPhase = .idle
    @Published var placementPrompt: String?
    @Published private(set) var startWaypoint: Waypoint?
    @Published private(set) var endWaypoint: Waypoint?

    // MARK: - MKDirections route overlay
    @Published var routePolyline: MKPolyline?
    @Published var isCalculatingRoute = false

    // MARK: - Device location
    @Published var userLocation: CLLocationCoordinate2D?

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

    private var routedPlaybackCoordinates: [CLLocationCoordinate2D] = []
    private let deviceLocation = DeviceLocationManager.shared
    private var cancellables = Set<AnyCancellable>()

    var startPinCoordinate: CLLocationCoordinate2D? {
        if selectedMode == .standstill {
            return waypoints.first?.coordinate
        }
        return startWaypoint?.coordinate
    }

    var endPinCoordinate: CLLocationCoordinate2D? {
        guard selectedMode != .standstill else { return nil }
        return endWaypoint?.coordinate
    }

    var canPlay: Bool {
        if selectedMode == .standstill {
            return placementPhase == .ready && waypoints.count == 1
        }
        return placementPhase == .ready && !waypoints.isEmpty
    }

    init() {
        player.$isPlaying.assign(to: &$isPlaying)
        player.$isPreparing.assign(to: &$isPreparing)
        player.$stats.assign(to: &$stats)
        player.$currentCoordinate.assign(to: &$currentCoordinate)

        player.onRouteFinished = { [weak self] in
            self?.selectedMode = .standstill
            self?.placementPhase = .ready
            self?.placementPrompt = nil
        }

        deviceLocation.$coordinate
            .receive(on: DispatchQueue.main)
            .assign(to: &$userLocation)
    }

    // MARK: - Route placement

    func clearRoute() {
        waypoints = []
        startWaypoint = nil
        endWaypoint = nil
        routePolyline = nil
        routedPlaybackCoordinates = []
        placementPhase = .idle
        placementPrompt = nil
        player.stop()
    }

    func beginNewRoute(for mode: MovementMode) {
        clearRoute()
        if mode == .standstill {
            placementPhase = .pickingHold
            placementPrompt = "Tap map to set hold location"
        } else {
            placementPhase = .pickingStart
            placementPrompt = "Tap map to set start"
        }
    }

    func selectMode(_ mode: MovementMode) {
        selectedMode = mode
        beginNewRoute(for: mode)
    }

    func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        switch placementPhase {
        case .idle, .pickingStart:
            clearRoute()
            if selectedMode == .standstill {
                let hold = Waypoint(coordinate: coordinate, name: "Hold")
                waypoints = [hold]
                startWaypoint = hold
                placementPhase = .ready
                placementPrompt = nil
            } else {
                let start = Waypoint(coordinate: coordinate, name: "Start")
                startWaypoint = start
                waypoints = [start]
                placementPhase = .pickingEnd
                placementPrompt = "Tap map to set destination"
            }

        case .pickingEnd:
            guard let start = startWaypoint else {
                beginNewRoute(for: selectedMode)
                handleMapTap(at: coordinate)
                return
            }
            let end = Waypoint(coordinate: coordinate, name: "End")
            endWaypoint = end
            waypoints = [start, end]
            placementPhase = .ready
            placementPrompt = nil
            Task { await refreshRoutedPolyline() }

        case .pickingHold:
            let hold = Waypoint(coordinate: coordinate, name: "Hold")
            waypoints = [hold]
            startWaypoint = hold
            endWaypoint = nil
            placementPhase = .ready
            placementPrompt = nil

        case .ready:
            beginNewRoute(for: selectedMode)
            handleMapTap(at: coordinate)
        }
    }

    // MARK: - Device location

    func startUserLocationUpdates() {
        deviceLocation.startUpdating()
    }

    func stopUserLocationUpdates() {
        deviceLocation.stopUpdating()
    }

    func requestUserLocationAccess() {
        deviceLocation.requestAuthorizationIfNeeded()
        deviceLocation.startUpdating()
    }

    func useCurrentLocationAsStart() {
        guard let coord = userLocation else {
            requestUserLocationAccess()
            return
        }
        if selectedMode == .standstill {
            beginNewRoute(for: .standstill)
            handleMapTap(at: coord)
        } else {
            beginNewRoute(for: selectedMode)
            handleMapTap(at: coord)
        }
        mapPosition = .camera(MapCamera(centerCoordinate: coord, distance: 1500))
    }

    // MARK: - Prepare and play

    func prepare() async {
        let coords = playbackCoordinates()
        guard !coords.isEmpty else { return }

        var profile = MovementProfile.default(for: selectedMode)
        if selectedMode == .custom {
            let mps = customSpeedMph * 0.44704
            profile = .custom(speedMps: mps)
        }

        player.waypoints = coords
        player.profile = profile
        player.speedMultiplier = speedMultiplier
        player.loop = loopEnabled

        await player.prepare()
    }

    func playPause() {
        if isPlaying {
            player.pause()
            return
        }

        if selectedMode == .standstill {
            if placementPhase != .ready || waypoints.count != 1 {
                beginNewRoute(for: .standstill)
                return
            }
            Task {
                await prepare()
                player.play()
            }
            return
        }

        guard placementPhase == .ready else { return }
        Task {
            await prepare()
            player.play()
        }
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
            finalizeLoadedRoute()
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Load from library

    func load(_ route: SavedRoute) {
        routeName = route.name
        selectedMode = route.mode
        waypoints = route.waypoints
        finalizeLoadedRoute()
    }

    private func finalizeLoadedRoute() {
        startWaypoint = waypoints.first
        endWaypoint = waypoints.count >= 2 ? waypoints.last : nil
        routedPlaybackCoordinates = waypoints.map(\.coordinate)
        placementPhase = .ready
        placementPrompt = nil

        if selectedMode == .standstill {
            if waypoints.count > 1 {
                waypoints = [waypoints[0]]
                startWaypoint = waypoints.first
                endWaypoint = nil
            }
            routedPlaybackCoordinates = waypoints.map(\.coordinate)
            return
        }

        if waypoints.count >= 2 {
            Task { await refreshRoutedPolyline() }
        } else if !waypoints.isEmpty {
            var mutable = waypoints.map(\.coordinate)
            routePolyline = MKPolyline(coordinates: &mutable, count: mutable.count)
        }
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

    // MARK: - Routed polyline

    private func playbackCoordinates() -> [CLLocationCoordinate2D] {
        if !routedPlaybackCoordinates.isEmpty {
            return routedPlaybackCoordinates
        }
        return waypoints.map(\.coordinate)
    }

    func refreshRoutedPolyline() async {
        routePolyline = nil
        routedPlaybackCoordinates = []

        guard selectedMode != .standstill else { return }

        if waypoints.count < 2 {
            if !waypoints.isEmpty {
                var mutable = waypoints.map(\.coordinate)
                routePolyline = MKPolyline(coordinates: &mutable, count: mutable.count)
                routedPlaybackCoordinates = mutable
            }
            return
        }

        guard let start = startWaypoint?.coordinate ?? waypoints.first?.coordinate,
              let end = endWaypoint?.coordinate ?? waypoints.last?.coordinate else {
            return
        }

        var fallback = [start, end]
        routePolyline = MKPolyline(coordinates: &fallback, count: fallback.count)
        routedPlaybackCoordinates = fallback

        isCalculatingRoute = true
        defer { isCalculatingRoute = false }

        let request = MKDirections.Request()
        if #available(iOS 26.0, *) {
            request.source = MKMapItem(
                location: CLLocation(latitude: start.latitude, longitude: start.longitude),
                address: nil
            )
            request.destination = MKMapItem(
                location: CLLocation(latitude: end.latitude, longitude: end.longitude),
                address: nil
            )
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        }
        request.transportType = transportType(for: selectedMode)

        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else {
            return
        }

        routePolyline = route.polyline
        routedPlaybackCoordinates = coordinates(from: route.polyline)
    }

    private func transportType(for mode: MovementMode) -> MKDirectionsTransportType {
        switch mode {
        case .walk, .bike, .custom:
            return .walking
        case .drive:
            return .automobile
        case .bus:
            return .transit
        case .standstill:
            return .walking
        }
    }

    private func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords
    }
}
