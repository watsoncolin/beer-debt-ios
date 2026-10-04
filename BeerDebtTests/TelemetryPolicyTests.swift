import Testing
@testable import BeerDebt

struct TelemetryPolicyTests {
    private func host(
        arguments: [String] = ["BeerDebt"],
        environment: [String: String] = [:],
        xcTestLoaded: Bool = false,
        debug: Bool = false
    ) -> TelemetryPolicy.Host {
        TelemetryPolicy.Host(
            arguments: arguments, environment: environment,
            isXCTestLoaded: xcTestLoaded, isDebugBuild: debug
        )
    }

    @Test func aPlainLaunchStartsSentry() {
        #expect(TelemetryPolicy.shouldStartSentry(host()))
        #expect(TelemetryPolicy.shouldStartSentry(host(arguments: ["BeerDebt", "-debugScreen", "streak"])))
    }

    @Test func aUnitTestHostDoesNot() {
        #expect(!TelemetryPolicy.shouldStartSentry(host(xcTestLoaded: true)))
    }

    @Test func xcodebuildTestEnvironmentDoesNot() {
        for key in TelemetryPolicy.xcTestEnvironmentKeys {
            #expect(!TelemetryPolicy.shouldStartSentry(host(environment: [key: "/tmp/x"])), "\(key)")
        }
    }

    @Test func aUITestLaunchDoesNot() {
        #expect(!TelemetryPolicy.shouldStartSentry(host(arguments: ["BeerDebt", "-UITest_Mode"])))
    }

    @Test func thisTestProcessIsRecognised() {
        #expect(TelemetryPolicy.isTestRun())
        #expect(!TelemetryPolicy.shouldStartSentry())
    }

    @Test func debugBuildsReportAsDevelopment() {
        #expect(TelemetryPolicy.sentryEnvironment(host(debug: true)) == "development")
        #expect(TelemetryPolicy.sentryEnvironment(host(debug: false)) == "production")
    }

    // MARK: App hangs from background launches

    /// The case that brought this in: BEER-DEBT-IOS-5, ten events across six
    /// users on 1.0+41, every one an "11-second hang" whose stack was nothing
    /// but a parked run loop. HealthKit wakes the app with no UI, Sentry's own
    /// foreground flag still reads true from its simulated first transition,
    /// and an idle main thread gets reported as blocked.
    @Test func anAppHangFromAProcessNeverOnScreenIsDropped() {
        #expect(!TelemetryPolicy.shouldSend(
            mechanism: TelemetryPolicy.appHangMechanism, everForegroundActive: false
        ))
    }

    /// A hang the user was actually present for still reports: this filters
    /// the background launches, it does not turn hang tracking off.
    @Test func anAppHangFromAForegroundProcessStillReports() {
        #expect(TelemetryPolicy.shouldSend(
            mechanism: TelemetryPolicy.appHangMechanism, everForegroundActive: true
        ))
    }

    /// Only hangs are second-guessed. A crash or a hand-reported HealthKit
    /// error from a background launch is exactly what we built the background
    /// sync to tell us about, and must survive.
    @Test func everythingElseReportsFromABackgroundLaunch() {
        for mechanism in [nil, "", "UncaughtExceptionHandler", "NSError", "signalhandler"] {
            #expect(TelemetryPolicy.shouldSend(mechanism: mechanism, everForegroundActive: false),
                    "\(mechanism ?? "nil")")
        }
    }
}
