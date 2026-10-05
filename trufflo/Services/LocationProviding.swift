import Foundation

public enum LocationAuthorization: String, Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways
}

public enum LocationServiceState: String, Sendable, Equatable {
    case idle
    case signalSought
    case acquiring
    case active
    case lost
    case denied
    case restricted
    case unavailable
}

public enum LocationServiceEvent: Sendable, Equatable {
    case stateChanged(LocationServiceState)
    case fix(LocationFix)
}

public typealias LocationEventHandler = @MainActor (LocationServiceEvent) -> Void

/// Why location cannot be used right now. The three cases are not
/// interchangeable: only a refusal is fixed in Settings, and each one carries
/// its own copy so the app never blames a permission the user still holds.
public enum LocationBlock: String, Sendable, Equatable {
    case permissionDenied
    case permissionRestricted
    case servicesUnavailable

    public var message: String {
        switch self {
        case .permissionDenied:
            return "La localisation est refusée. Autorisez-la dans les réglages pour lancer une balade."
        case .permissionRestricted:
            return "La localisation est restreinte sur cet appareil."
        case .servicesUnavailable:
            return "La localisation est désactivée sur cet appareil. Activez-la pour enregistrer un parcours."
        }
    }

    /// A refusal is the one case where Settings is the way out. A restriction
    /// comes from parental controls or MDM, and a disabled service is toggled
    /// outside the app, so offering the Settings deep link there would be a
    /// dead end.
    public var offersSettings: Bool { self == .permissionDenied }
}

@MainActor
public protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    /// Whether the device's location services are switched on at all. Distinct
    /// from `authorization`: the user can hold a valid permission with every
    /// service disabled, which yields no fix and no error either.
    var servicesAvailable: Bool { get }
    func setHandler(_ handler: @escaping LocationEventHandler)
    func requestWhenInUse() async
    func start() async
    func stop() async
}
