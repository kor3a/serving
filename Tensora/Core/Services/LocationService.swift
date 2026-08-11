import CoreLocation
import Foundation

/// Wraps `CLLocationManager` so Discover can ask for a one-shot fix and fall
/// back to a default region when permission is denied.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isResolving = false

    private let manager = CLLocationManager()

    /// Used until the device reports a real position — keeps the map from
    /// opening on Null Island.
    static let fallbackCoordinate = MockData.baseCoordinate

    var effectiveCoordinate: Coordinate { coordinate ?? LocationService.fallbackCoordinate }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermissionIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            refresh()
        default:
            break
        }
    }

    func refresh() {
        guard isAuthorized else { return }
        isResolving = true
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized { refresh() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isResolving = false
        guard let location = locations.last else { return }
        coordinate = Coordinate(location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isResolving = false
    }
}
