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
}
