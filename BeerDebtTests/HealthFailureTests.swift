import Foundation
import HealthKit
import Testing
@testable import BeerDebt

/// Both payloads below are the ones Sentry actually received on 2026-09-13
/// (BEER-DEBT-IOS-1 and -2), rebuilt here so the classification can't drift
/// away from what iOS really throws.
struct HealthFailureTests {
    private func error(_ domain: String, _ code: Int, _ description: String? = nil,
                       underlying: NSError? = nil, original: NSError? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let description { info[NSLocalizedDescriptionKey] = description }
        if let underlying { info[NSUnderlyingErrorKey] = underlying }
        if let original { info["OriginalError"] = original }
        return NSError(domain: domain, code: code, userInfo: info)
    }

    /// What a background wake hits whenever the phone is locked, which is most
    /// of the time a workout lands.
    @Test func lockedPhoneIsNotSomethingToReport() {
        let locked = error("com.apple.healthkit", 6, "Protected health data is inaccessible")
        #expect(HealthFailure(locked) == .deviceLocked)
        #expect(!HealthFailure(locked).isReportable)
        #expect(HealthFailure(locked).message(or: "raw").contains("unlock"))
    }

    @Test func theLockedCodeIsTheOneHealthKitDocuments() {
        #expect(HKError.Code.errorDatabaseInaccessible.rawValue == 6)
    }

    @Test func guidedAccessIsFoundThroughTheWholeNestedChain() {
        // _UIViewServiceHostSessionErrorDomain → OriginalError → NSUnderlyingError.
        let cause = error("FBSOpenApplicationErrorDomain", 1, "Guided Access active")
        let openRequest = error("FBSOpenApplicationServiceErrorDomain", 1,
                                "The request to open \"com.apple.HealthPrivacyService\" failed.",
                                underlying: cause)
        let thrown = error("_UIViewServiceHostSessionErrorDomain", 0, original: openRequest)

        #expect(HealthFailure(thrown) == .guidedAccess)
        #expect(!HealthFailure(thrown).isReportable)
        #expect(HealthFailure(thrown).message(or: "raw").contains("Guided Access"))
    }

    @Test func aBlockedSheetWithoutGuidedAccessIsStillNotADefect() {
        let openRequest = error("FBSOpenApplicationServiceErrorDomain", 1, "The request failed.")
        let thrown = error("_UIViewServiceHostSessionErrorDomain", 0, original: openRequest)
        #expect(HealthFailure(thrown) == .sheetBlocked)
        #expect(!HealthFailure(thrown).isReportable)
    }

    @Test func theOtherHealthKitConditionsAreNamed() {
        func failure(_ code: HKError.Code) -> HealthFailure {
            HealthFailure(error(HKError.errorDomain, code.rawValue))
        }
        #expect(failure(.errorAuthorizationNotDetermined) == .notDetermined)
        #expect(failure(.errorAuthorizationDenied) == .denied)
        #expect(failure(.errorRequiredAuthorizationDenied) == .denied)
        #expect(failure(.errorHealthDataUnavailable) == .unavailable)
        #expect(failure(.errorHealthDataRestricted) == .unavailable)
    }

    @Test func everythingNamedKeepsItsWordsAndItsSilence() {
        for failure in [HealthFailure.deviceLocked, .notDetermined, .denied, .unavailable, .guidedAccess, .sheetBlocked] {
            #expect(!failure.isReportable)
            // Real copy, not the system's nested dump.
            #expect(failure.message(or: "raw") != "raw")
        }
    }

    @Test func anythingUnrecognisedStillReachesUs() {
        let odd = HealthFailure(error("com.example.nonsense", 42, "Something new"))
        #expect(odd == .unknown)
        #expect(odd.isReportable)
        // Nothing better to say than whatever the system said.
        #expect(odd.message(or: "Something new") == "Something new")
    }

    @Test func anUnknownHealthKitCodeIsReported() {
        // A code HealthKit adds later must page us rather than be swallowed.
        #expect(HealthFailure(error(HKError.errorDomain, 99)) == .unknown)
    }

    @Test func aCauseBuriedBeyondTheDepthCapIsReportedRatherThanGuessedAt() {
        // The walk stops after eight links. Anything deeper reads as unknown,
        // which pages us: better a noisy report than a silently swallowed one.
        var nested = error(HKError.errorDomain, HKError.Code.errorDatabaseInaccessible.rawValue)
        for i in 0..<12 {
            nested = error("com.example.wrapper", i, underlying: nested)
        }
        #expect(HealthFailure(nested) == .unknown)
        #expect(HealthFailure(nested).isReportable)
    }

    @Test func aCauseWithinTheDepthCapIsStillFound() {
        var nested = error(HKError.errorDomain, HKError.Code.errorDatabaseInaccessible.rawValue)
        for i in 0..<5 {
            nested = error("com.example.wrapper", i, underlying: nested)
        }
        #expect(HealthFailure(nested) == .deviceLocked)
    }
}
