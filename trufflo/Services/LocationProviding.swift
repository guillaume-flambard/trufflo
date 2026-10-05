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

@MainActor
public protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    func setHandler(_ handler: @escaping LocationEventHandler)
    func requestWhenInUse() async
    func start() async
    func stop() async
}
