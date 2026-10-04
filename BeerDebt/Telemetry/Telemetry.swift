import Foundation
import Sentry
import UIKit
import os

/// The app's one door to Sentry, the Pourcraft / Pawfect Edit convention and
/// the same door the Android app has in `Telemetry.kt`: crash reporting only.
/// Crashes, app hangs, and hand-reported errors go out; nothing identifies the
/// user (no `setUser`, no PII), and there is no session replay, tracing,
/// screenshot, or network capture. A hand-reported error carries one context
/// block keyed by domain (`health`, `store`) with the facts a reader needs.
/// Report an error once, at its source; a caller that only rethrows must not
/// report it again.
enum Telemetry {
    /// Sentry project `beer-debt-ios` in the `pawfect-edit` org. A DSN is a
    /// public ingest address, not a secret. `SENTRY_DSN` in the environment
    /// overrides it (set it empty in an Xcode scheme to switch reporting off).
    static let defaultDSN = "https://783ad5b112b6f4d7b3c0bb61d164aae6@o4508774188711936.ingest.us.sentry.io/4512076463341568"

    static func configure(host: TelemetryPolicy.Host = .current) {
        // Unit tests run inside this app; their hangs and crashes belong to
        // the harness, not to users. See TelemetryPolicy.
        guard TelemetryPolicy.shouldStartSentry(host) else { return }
        let dsn = host.environment["SENTRY_DSN"] ?? defaultDSN
        guard !dsn.isEmpty else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            // Debug builds report as "development" so simulator and
            // dev-phone events stay out of production issues.
            options.environment = TelemetryPolicy.sentryEnvironment(host)
            // The release defaults to "me.colinwatson.beerdebt@1.0+23", the
            // shape the Android app sets by hand.

            options.sendDefaultPii = false
            // Tracing stays off (tracesSampleRate unset); no replay, no
            // screenshots, no view hierarchy, no network breadcrumbs.
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableNetworkTracking = false
            options.enableUserInteractionTracing = false
            options.enableAutoBreadcrumbTracking = true

            // App hangs: only fully blocking ones (main thread stuck, stack
            // trustworthy) are actionable.
            options.enableAppHangTracking = true
            options.enableAppHangTrackingV2 = true
            options.enableReportNonFullyBlockingAppHangs = false
            options.appHangTimeoutInterval = 2.0

            // ...and only from a process that has actually been on screen.
            // HealthKit background launches otherwise report an idle main
            // thread as an 11-second hang; see TelemetryPolicy.shouldSend.
            options.beforeSend = { event in
                TelemetryPolicy.shouldSend(
                    mechanism: event.exceptions?.first?.mechanism?.type,
                    everForegroundActive: ForegroundWitness.shared.hasBeenActive
                ) ? event : nil
            }
        }

        ForegroundWitness.shared.start()
    }

    static func report(_ error: Error, context key: String, _ values: [String: Any] = [:]) {
        SentrySDK.capture(error: error) { scope in
            scope.setContext(value: values, key: key)
        }
    }

    static func report(message: String, level: SentryLevel = .warning, context key: String, _ values: [String: Any] = [:]) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            scope.setContext(value: values, key: key)
        }
    }
}


/// Whether this process has ever been foreground-active, which is the fact
/// `TelemetryPolicy.shouldSend` needs and the one Sentry's own
/// `isApplicationInForeground` gets wrong on a background launch.
///
/// Read from `beforeSend`, which Sentry calls on whatever thread the event
/// came from, so the flag is behind a lock. `token` is touched only by
/// `start()`, once, from `App.init` on the main actor -- hence the unchecked
/// conformance. Holding the token is what keeps the observation alive.
private final class ForegroundWitness: @unchecked Sendable {
    static let shared = ForegroundWitness()

    private let active = OSAllocatedUnfairLock(initialState: false)
    private var token: (any NSObjectProtocol)?

    var hasBeenActive: Bool { active.withLock { $0 } }

    func start() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [active] _ in
            active.withLock { $0 = true }
        }
    }
}
