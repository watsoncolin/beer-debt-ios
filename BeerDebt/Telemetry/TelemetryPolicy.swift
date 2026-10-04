import Foundation

/// Decides whether Sentry should run in this process, and which `environment`
/// it reports under. Ported from Pourcraft / Pawfect Edit, where simulator
/// test runs once reported fatal app hangs tagged `production`: the test
/// bundle is injected into the app process, so `App.init` started Sentry
/// inside the test host, and app-hang tracking only runs without a debugger
/// attached, which is exactly the `xcodebuild test` case. Test processes must
/// not report, and dev builds must be separable from production.
enum TelemetryPolicy {
    /// The facts about the running process the policy depends on, split out so
    /// tests can build them directly instead of relying on the live process.
    struct Host {
        var arguments: [String]
        var environment: [String: String]
        /// XCTest is linked into this process (unit-test host).
        var isXCTestLoaded: Bool
        var isDebugBuild: Bool

        static var current: Host {
            Host(
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment,
                isXCTestLoaded: NSClassFromString("XCTestCase") != nil,
                isDebugBuild: {
                    #if DEBUG
                    return true
                    #else
                    return false
                    #endif
                }()
            )
        }
    }

    /// Environment variables xcodebuild sets on a test host process (Swift
    /// Testing runs through the same harness). Checked as well as the class
    /// lookup because the test bundle is injected after the app has started,
    /// so XCTest may not be loaded yet when `App.init` runs.
    static let xcTestEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestSessionIdentifier",
        "XCTestBundlePath",
    ]

    /// Prefix shared by every launch argument a UI test would pass to the app.
    static let uiTestArgumentPrefix = "-UITest_"

    /// True for a test host process or an app launched by a UI test.
    static func isTestRun(_ host: Host = .current) -> Bool {
        if host.isXCTestLoaded { return true }
        if xcTestEnvironmentKeys.contains(where: { host.environment[$0] != nil }) { return true }
        return host.arguments.contains { $0.hasPrefix(uiTestArgumentPrefix) }
    }

    static func shouldStartSentry(_ host: Host = .current) -> Bool {
        !isTestRun(host)
    }

    /// Sentry `environment` tag. Debug builds (Xcode runs, simulator, phones
    /// built from Xcode) report as `development`; anything else is
    /// `production`.
    static func sentryEnvironment(_ host: Host = .current) -> String {
        host.isDebugBuild ? "development" : "production"
    }

    /// `mechanism.type` on every app-hang event the SDK builds
    /// (`SentryANRTrackingIntegration.m`: `initWithType:@"AppHang"`). The
    /// exception `type` is one of five strings that vary with severity, so the
    /// mechanism is the stable thing to match on.
    static let appHangMechanism = "AppHang"

    /// Whether an event is worth sending, given whether this process has ever
    /// been foreground-active.
    ///
    /// App hangs are the one kind we second-guess, because HealthKit
    /// background delivery launches this app with no UI and the SDK's own
    /// guard against that does not hold. `SentryANRTrackerV2` skips hang
    /// detection while `isApplicationInForeground` is false, but that flag
    /// starts life as a lie: `SentryCrashMonitor_AppState.c` sets it `true` at
    /// init under the comment "Simulate first transition to foreground", and
    /// only a `UIApplication` lifecycle notification ever corrects it. A
    /// background-launched process posts no such notification -- it was never
    /// in the foreground, so it never leaves it -- and the flag stays `true`
    /// for the life of that process. Hang detection therefore runs on exactly
    /// the launches where an idle main thread is the correct and expected
    /// state, and reports it as a fully-blocking hang with a stack that
    /// contains no app frames at all: just `main` under the parked run loop.
    ///
    /// So: trust a hang only from a process the user has actually seen. A real
    /// hang blocks something the user was looking at, which means the app was
    /// active, which means `didBecomeActive` has fired.
    ///
    /// This is deliberately a filter on reporting rather than
    /// `enableAppHangTracking = false`: a hang on screen is still worth
    /// knowing about, and this keeps those. One gap stays open -- a *fatal*
    /// hang is stored and sent on the next launch, so it is judged by that
    /// launch's foreground state rather than by the one that hung.
    static func shouldSend(mechanism: String?, everForegroundActive: Bool) -> Bool {
        guard mechanism == appHangMechanism else { return true }
        return everForegroundActive
    }
}
