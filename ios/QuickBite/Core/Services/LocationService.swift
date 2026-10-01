import CoreLocation
import MapKit

/// One-shot "where am I" with async/await on top of CLLocationManager,
/// plus reverse geocoding for a human-readable label.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Returns nil when permission is denied or location is unavailable.
    func currentLocation() async -> CLLocation? {
        if continuation != nil { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(nil)
            }
        }
    }

    func label(for location: CLLocation) async -> (title: String, subtitle: String) {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let title = placemark?.subLocality ?? placemark?.name ?? "Current location"
        let subtitle = [placemark?.locality, placemark?.postalCode].compactMap { $0 }.joined(separator: " ")
        return (title, subtitle.isEmpty ? "Near you" : subtitle)
    }

    func placemark(for location: CLLocation) async -> CLPlacemark? {
        try? await CLGeocoder().reverseGeocodeLocation(location).first
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .notDetermined: break
            default: self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.finish(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
