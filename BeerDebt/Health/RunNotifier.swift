import Foundation
import UserNotifications

/// Local notifications for runs that arrive while the app is closed
/// (spec §22). No server, no push: iOS wakes the app via HealthKit background
/// delivery, the sync applies the run, and this posts the result.
@MainActor
final class RunNotifier {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks once; later calls return the stored answer.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ message: Message) async {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "run-\(UUID().uuidString)", content: content, trigger: nil
        )
        try? await center.add(request)
    }

    struct Message: Equatable, Sendable {
        let title: String
        let body: String
    }

    /// What changed in one sync, from the reports before and after it.
    struct Change: Sendable {
        var addedRuns: [RunEntry]
        var removedRuns: Int
        var before: Balance
        var after: Balance
        var beersPaidOff: Int
    }

    /// Pure, so the copy can be tested. Plain and fun, no ledger-speak.
    nonisolated static func message(for change: Change) -> Message? {
        let miles = change.addedRuns.reduce(0) { $0 + $1.distanceMiles }
        let after = change.after

        if change.addedRuns.isEmpty {
            guard change.removedRuns > 0 else { return nil }
            let title = change.removedRuns == 1 ? "A run was removed from Health" : "\(change.removedRuns) runs were removed from Health"
            return Message(title: title, body: "You're at \(standing(after)).")
        }

        let title = change.addedRuns.count == 1
            ? "Run logged: \(Format.miles(miles))"
            : "\(change.addedRuns.count) runs logged: \(Format.miles(miles))"

        let body: String
        switch (change.before.state, after.state) {
        case (.debt, .debt):
            let knocked = max(0, change.before.debtMiles - after.debtMiles)
            if change.beersPaidOff > 0 {
                body = "Paid off \(beers(change.beersPaidOff)). \(Format.miles(after.debtMiles)) still owed."
            } else {
                body = "Knocked \(Format.miles(knocked)) off your tab. \(Format.miles(after.debtMiles)) still owed."
            }
        case (.debt, .credit):
            body = "Tab paid, and \(Format.beersLabel(after.creditBeers)) banked. Cheers."
        case (.debt, .even):
            body = "Tab paid. Books are clean."
        case (_, .credit):
            let gained = after.creditBeers - change.before.creditBeers
            if gained < 0.05 {
                body = "You're maxed out at \(Format.beersLabel(after.creditBeers)) banked. Time to drink one."
            } else {
                body = "\(Format.beersLabel(after.creditBeers)) banked for later."
            }
        default:
            body = "Books are clean."
        }
        if change.removedRuns > 0 {
            return Message(title: "Runs updated", body: "You're at \(standing(after)).")
        }
        return Message(title: title, body: body)
    }

    nonisolated private static func standing(_ balance: Balance) -> String {
        switch balance.state {
        case .debt: "\(Format.miles(balance.debtMiles)) owed"
        case .credit: "\(Format.beersLabel(balance.creditBeers)) banked"
        case .even: "zero. Books are clean"
        }
    }

    nonisolated private static func beers(_ n: Int) -> String {
        n == 1 ? "1 beer" : "\(n) beers"
    }
}
