import Foundation
@testable import trufflo

@MainActor
final class FakeLocationProvider: LocationProviding {
    var authorization: LocationAuthorization
    var servicesEnabled = true
    var servicesAvailable: Bool { servicesEnabled }
    var requestGrants = true
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var requestCount = 0
    private(set) var started = false
    private(set) var emitted: [LocationFix] = []
    private(set) var states: [LocationServiceState] = []
    private var handler: LocationEventHandler?

    init(authorization: LocationAuthorization = .authorizedWhenInUse) {
        self.authorization = authorization
    }

    func setHandler(_ handler: @escaping LocationEventHandler) {
        self.handler = handler
    }

    func requestWhenInUse() async {
        requestCount += 1
        if authorization == .notDetermined, requestGrants {
            authorization = .authorizedWhenInUse
        }
    }

    func start() async {
        startCount += 1
        guard servicesEnabled else {
            report(.stateChanged(.unavailable))
            return
        }
        switch authorization {
        case .denied:
            report(.stateChanged(.denied))
        case .restricted:
            report(.stateChanged(.restricted))
        case .notDetermined:
            report(.stateChanged(.signalSought))
            started = true
        case .authorizedWhenInUse, .authorizedAlways:
            report(.stateChanged(.acquiring))
            started = true
        }
    }

    func stop() async {
        stopCount += 1
        started = false
        state = .idle
    }

    func emit(latitude: Double, longitude: Double, accuracy: Double, at date: Date) {
        let fix = LocationFix(latitude: latitude, longitude: longitude,
                               horizontalAccuracy: accuracy, timestamp: date)
        emitted.append(fix)
        if accuracy >= 0, state != .active {
            report(.stateChanged(.active))
        }
        report(.fix(fix))
    }

    func emitFixes(_ fixes: [LocationFix]) {
        for fix in fixes {
            emit(latitude: fix.latitude, longitude: fix.longitude,
                 accuracy: fix.horizontalAccuracy, at: fix.timestamp)
        }
    }

    func setServicesEnabled(_ enabled: Bool) {
        servicesEnabled = enabled
        if !enabled, started {
            started = false
            state = .idle
            report(.stateChanged(.unavailable))
        }
    }

    func revoke() {
        authorization = .denied
        started = false
        report(.stateChanged(.denied))
    }

    func restrict() {
        authorization = .restricted
        started = false
        report(.stateChanged(.restricted))
    }

    private var state: LocationServiceState = .idle

    private func report(_ event: LocationServiceEvent) {
        if case .stateChanged(let newState) = event {
            state = newState
            states.append(newState)
        }
        handler?(event)
    }
}
