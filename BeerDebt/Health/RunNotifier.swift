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
        /// What the new runs actually took off the tab, summed from their own
        /// statements.
        ///
        /// Not the drop in the balance between the two reports. A run that
        /// carries the streak to two days makes today interest-protected, and
        /// the replay then skips today's postings that the earlier report had
        /// already made — so the balance falls by the miles run *plus* the
        /// interest that un-posted, and attributing all of it to the run
        /// overstates it, often by more than the run itself. The streak's share
        /// is already announced on its own line; counting it here said it twice.
        var debtPaidMiles: Double
        var beersPaidOff: Int
        /// The streak after the sync, and whether the new runs landed on a streak day.
        var streakDays: Int = 0
        var streakDay: Bool = false
        /// This sync made it two days in a row: interest just paused.
        var streakActivated: Bool = false
        /// Miles or calories, and which workouts count (spec §28).
        var units: Units = .miles
    }

    /// Pure, so the copy can be tested. Plain and fun, no ledger-speak.
    nonisolated static func message(for change: Change) -> Message? {
        let units = change.units
        let miles = change.addedRuns.reduce(0) { $0 + (units.payment.miles(paidBy: $1) ?? 0) }
        let after = change.after
        let noun = units.workout

        if change.addedRuns.isEmpty {
            guard change.removedRuns > 0 else { return nil }
            let title = change.removedRuns == 1 ? "A \(noun) was removed from Health" : "\(change.removedRuns) \(noun)s were removed from Health"
            return Message(title: title, body: "You're at \(standing(after, units)).")
        }

        let title = change.addedRuns.count == 1
            ? "\(WorkoutKind(change.addedRuns[0]).name) logged: \(units.amount(miles))"
            : "\(change.addedRuns.count) \(noun)s logged: \(units.amount(miles))"

        let body: String
        switch (change.before.state, after.state) {
        case (.debt, .debt):
            let knocked = max(0, change.debtPaidMiles)
            if change.beersPaidOff > 0 {
                body = "Paid off \(beers(change.beersPaidOff)). \(units.amount(after.debtMiles)) still owed."
            } else {
                body = "Knocked \(units.amount(knocked)) off your tab. \(units.amount(after.debtMiles)) still owed."
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
            return Message(title: "\(units.workoutsTitle) updated", body: "You're at \(standing(after, units)).")
        }
        if change.streakActivated {
            return Message(
                title: "\(change.streakDays) day streak: 0% APR, earned",
                body: "\(title). \(body) Your debt interest is now paused."
            )
        }
        if change.streakDay, change.streakDays >= 2 {
            return Message(title: title, body: "\(body) 🔥 \(change.streakDays) day streak, interest paused.")
        }
        if change.streakDay, change.streakDays == 1 {
            return Message(title: title, body: "\(body) 🔥 Day one of a streak. \(units.dailyGoal) tomorrow to pause interest.")
        }
        return Message(title: title, body: body)
    }

    nonisolated private static func standing(_ balance: Balance, _ units: Units) -> String {
        switch balance.state {
        case .debt: "\(units.amount(balance.debtMiles)) owed"
        case .credit: "\(Format.beersLabel(balance.creditBeers)) banked"
        case .even: "zero. Books are clean"
        }
    }

    nonisolated private static func beers(_ n: Int) -> String {
        n == 1 ? "1 beer" : "\(n) beers"
    }
}
