import Foundation
import HealthKit

/// What a thrown HealthKit error actually means, so the app can tell an
/// environment condition from a defect.
///
/// Every catch in `HealthSync` used to report to Sentry and put the system's
/// own `localizedDescription` in front of the user. Both were wrong. Health
/// data is sealed while the phone is locked, and background delivery wakes the
/// app exactly when the phone is usually locked, so the routine case was
/// paging us often enough to bury a real one. And the strings iOS produces for
/// these are nested Foundation dumps that name no remedy.
///
/// Pure, so the mapping is tested rather than trusted.
enum HealthFailure: Equatable, Sendable {
    /// Protected health data is unreadable because the phone is locked.
    /// Routine on a background wake, and it fixes itself on the next unlock.
    case deviceLocked
    /// Access has not been asked for yet.
    case notDetermined
    /// The user turned access off.
    case denied
    /// No HealthKit on this device at all.
    case unavailable
    /// Guided Access was on, so iOS refused to open the Health permission
    /// screen. Named separately because the user can act on it.
    case guidedAccess
    /// iOS declined to present the Health permission screen for some other
    /// reason.
    case sheetBlocked
    /// Not recognised. The only kind worth reporting.
    case unknown

    init(_ error: Error) {
        let chain = Self.chain(of: error)

        if let health = chain.first(where: { $0.domain == HKError.errorDomain }),
           let code = HKError.Code(rawValue: health.code) {
            switch code {
            case .errorDatabaseInaccessible: self = .deviceLocked
            case .errorAuthorizationNotDetermined: self = .notDetermined
            case .errorAuthorizationDenied, .errorRequiredAuthorizationDenied: self = .denied
            case .errorHealthDataUnavailable, .errorHealthDataRestricted: self = .unavailable
            default: self = .unknown
            }
            return
        }

        if chain.contains(where: Self.isPresentationFailure) {
            self = chain.contains { $0.localizedDescription.range(of: "Guided Access", options: .caseInsensitive) != nil }
                ? .guidedAccess
                : .sheetBlocked
            return
        }

        self = .unknown
    }

    /// Only what we couldn't explain. Everything named above is the phone or
    /// the user, not the app, and reporting it is noise that hides the rest.
    var isReportable: Bool { self == .unknown }

    /// Words with a remedy in them, or `fallback` when the system's own
    /// description is the best there is.
    func message(or fallback: String) -> String {
        switch self {
        case .deviceLocked:
            "Apple Health keeps your data sealed while your phone is locked. Your runs will come in the next time you unlock it."
        case .notDetermined:
            "Beer Debt hasn't been granted access to Apple Health yet."
        case .denied:
            "Apple Health access is off for Beer Debt. Turn it on in Settings › Health › Data Access & Devices › Beer Debt."
        case .unavailable:
            "Apple Health isn't available on this device."
        case .guidedAccess:
            "Guided Access is on, so iOS won't open the Health permission screen. Turn it off and try again."
        case .sheetBlocked:
            "iOS wouldn't open the Health permission screen. Try again in a moment."
        case .unknown:
            fallback
        }
    }

    // MARK: Reading the error

    /// The domain iOS reports when a remote view service, which is what the
    /// Health permission screen is, can't be brought up. Private, and only
    /// ever read here, never called into.
    private static let viewServiceDomain = "_UIViewServiceHostSessionErrorDomain"

    private static func isPresentationFailure(_ error: NSError) -> Bool {
        error.domain == viewServiceDomain || error.domain.hasPrefix("FBSOpenApplication")
    }

    /// The error and everything nested under it. iOS buries the cause several
    /// levels down and under two different keys, so both are followed; the
    /// depth cap keeps a self-referencing chain from spinning.
    private static func chain(of error: Error) -> [NSError] {
        var found: [NSError] = []
        var pending: [NSError] = [error as NSError]
        while let next = pending.popLast(), found.count < 8 {
            found.append(next)
            for key in [NSUnderlyingErrorKey, "OriginalError"] {
                if let nested = next.userInfo[key] as? NSError { pending.append(nested) }
            }
        }
        return found
    }
}
