import Foundation
import Sentry

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
        }
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
