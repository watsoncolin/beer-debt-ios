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
}
