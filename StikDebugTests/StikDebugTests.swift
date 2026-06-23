import CoreLocation
import XCTest
@testable import StikDebug

final class RouteSimTests: XCTestCase {
    func testRouteGeometryBearing() {
        let a = CLLocationCoordinate2D(latitude: 27.9472, longitude: -82.4586)
        let b = CLLocationCoordinate2D(latitude: 27.9550, longitude: -82.4500)
        let bearing = RouteGeometry.bearing(from: a, to: b)
        XCTAssertGreaterThan(bearing, 0)
        XCTAssertLessThan(bearing, 360)
    }

    func testDensifyIncreasesPoints() {
        let coords = [
            CLLocationCoordinate2D(latitude: 27.9472, longitude: -82.4586),
            CLLocationCoordinate2D(latitude: 27.9600, longitude: -82.4500)
        ]
        let dense = RouteGeometry.densify(coords, maxStepMeters: 20)
        XCTAssertGreaterThan(dense.count, 2)
    }

    func testMovementProfileDefaults() {
        let drive = MovementProfile.drive
        XCTAssertGreaterThanOrEqual(drive.cruiseSpeed, DrivingDynamics.minimumDrivingSpeedMps)
    }

    @MainActor
    func testStandstillProfileHasZeroSpeed() {
        let profile = MovementProfile.standstill
        XCTAssertEqual(profile.cruiseSpeed, 0)
        XCTAssertEqual(profile.maxSpeed, 0)
        XCTAssertEqual(profile.mode, .standstill)
    }

    @MainActor
    func testBeginNewRouteEntersPickingHoldForStandstill() {
        let vm = SimulateViewModel()
        vm.selectMode(.standstill)
        XCTAssertEqual(vm.placementPhase, .pickingHold)
        XCTAssertEqual(vm.placementPrompt, "Tap map to set hold location")
        XCTAssertTrue(vm.waypoints.isEmpty)
    }

    @MainActor
    func testMapTapInStandstillSetsSingleWaypoint() {
        let vm = SimulateViewModel()
        vm.selectMode(.standstill)
        let coord = CLLocationCoordinate2D(latitude: 27.95, longitude: -82.45)
        vm.handleMapTap(at: coord)
        XCTAssertEqual(vm.placementPhase, .ready)
        XCTAssertEqual(vm.waypoints.count, 1)
        XCTAssertTrue(vm.canPlay)
    }

    @MainActor
    func testMovementModeTapSetsStartThenEnd() {
        let vm = SimulateViewModel()
        vm.selectMode(.drive)
        let start = CLLocationCoordinate2D(latitude: 27.94, longitude: -82.46)
        let end = CLLocationCoordinate2D(latitude: 27.96, longitude: -82.44)
        vm.handleMapTap(at: start)
        XCTAssertEqual(vm.placementPhase, .pickingEnd)
        XCTAssertEqual(vm.waypoints.count, 1)
        vm.handleMapTap(at: end)
        XCTAssertEqual(vm.placementPhase, .ready)
        XCTAssertEqual(vm.waypoints.count, 2)
    }
}
