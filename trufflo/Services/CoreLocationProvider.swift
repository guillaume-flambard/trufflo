import CoreLocation
import Foundation

@MainActor
public final class CoreLocationProvider: NSObject, LocationProviding {
    private let manager: CLLocationManager
    private var handler: LocationEventHandler?
    private var state: LocationServiceState = .idle
    private var started = false

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        if Self.allowsBackgroundUpdates {
            manager.allowsBackgroundLocationUpdates = true
        }
    }

    public var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    public func setHandler(_ handler: @escaping LocationEventHandler) {
        self.handler = handler
    }

    public func requestWhenInUse() async {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    public func start() async {
        guard await Self.servicesEnabled() else {
            report(.stateChanged(.unavailable))
            return
        }
        switch authorization {
        case .denied:
            report(.stateChanged(.denied))
            return
        case .restricted:
            report(.stateChanged(.restricted))
            return
        case .notDetermined:
            report(.stateChanged(.signalSought))
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            report(.stateChanged(.acquiring))
        }
        started = true
        manager.startUpdatingLocation()
    }

    public func stop() async {
        started = false
        state = .idle
        manager.stopUpdatingLocation()
    }

    private func report(_ event: LocationServiceEvent) {
        switch event {
        case .stateChanged(let newState):
            state = newState
        case .fix:
            break
        }
        handler?(event)
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways: return .authorizedAlways
        case .authorizedWhenInUse: return .authorizedWhenInUse
        @unknown default: return .notDetermined
        }
    }

    private static var allowsBackgroundUpdates: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") == true
    }

    private static func servicesEnabled() async -> Bool {
        await Task.detached(priority: .utility) {
            CLLocationManager.locationServicesEnabled()
        }.value
    }

    private nonisolated func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onMain { [self] in
            switch Self.map(status) {
            case .denied:
                if started {
                    started = false
                    self.manager.stopUpdatingLocation()
                }
                report(.stateChanged(.denied))
            case .restricted:
                if started {
                    started = false
                    self.manager.stopUpdatingLocation()
                }
                report(.stateChanged(.restricted))
            case .notDetermined:
                report(.stateChanged(.signalSought))
            case .authorizedWhenInUse, .authorizedAlways:
                guard started else { return }
                report(.stateChanged(state == .active ? .active : .acquiring))
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager,
                                            didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        onMain { [self] in
            guard started else { return }
            if latest.horizontalAccuracy >= 0, state != .active {
                report(.stateChanged(.active))
            }
            report(.fix(LocationFix(latitude: latest.coordinate.latitude,
                                    longitude: latest.coordinate.longitude,
                                    horizontalAccuracy: latest.horizontalAccuracy,
                                    timestamp: latest.timestamp)))
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        onMain { [self] in
            switch clError.code {
            case .denied:
                started = false
                self.manager.stopUpdatingLocation()
                report(.stateChanged(.denied))
            case .locationUnknown:
                guard started else { return }
                if state != .active {
                    report(.stateChanged(.acquiring))
                }
            default:
                break
            }
        }
    }
}
