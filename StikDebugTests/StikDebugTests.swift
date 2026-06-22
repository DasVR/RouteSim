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
}
