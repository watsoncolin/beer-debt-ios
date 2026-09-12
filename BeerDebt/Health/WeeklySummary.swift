import Foundation
import Observation
import UserNotifications

/// A once-a-week local notification with the week's beers, miles, and where
/// the tab stands. Because the engine is deterministic, the standing quoted
/// for each future fire time is the exact balance at that instant assuming
/// nothing new happens; every ledger change reschedules the next four.
@MainActor
@Observable
final class WeeklySummary {
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private static let enabledKey = "weekly.enabled"
    private static let weekdayKey = "weekly.weekday"
    private static let hourKey = "weekly.hour"
    private static let minuteKey = "weekly.minute"
    static let identifierPrefix = "weekly-"

    private(set) var enabled: Bool
    /// 1 = Sunday … 7 = Saturday, like `Calendar`.
    var weekday: Int { didSet { defaults.set(weekday, forKey: Self.weekdayKey) } }
    var hour: Int { didSet { defaults.set(hour, forKey: Self.hourKey) } }
    var minute: Int { didSet { defaults.set(minute, forKey: Self.minuteKey) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        weekday = defaults.object(forKey: Self.weekdayKey) as? Int ?? 1
        hour = defaults.object(forKey: Self.hourKey) as? Int ?? 18
        minute = defaults.object(forKey: Self.minuteKey) as? Int ?? 0
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
    }

    /// The time of day as a Date, for a DatePicker.
    var timeOfDay: Date {
        get { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = parts.hour ?? 18
            minute = parts.minute ?? 0
        }
    }

    /// Replaces the pending weekly notifications with the next four, or clears
    /// them when off.
    func reschedule(ledger: Ledger, now: Date = .now, calendar: Calendar = .current) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }

        for (index, fireDate) in Self.nextFireDates(after: now, weekday: weekday, hour: hour, minute: minute, count: 4, calendar: calendar).enumerated() {
            let message = Self.message(ledger: ledger, at: fireDate, calendar: calendar)
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    nonisolated static func nextFireDates(after now: Date, weekday: Int, hour: Int, minute: Int, count: Int, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var cursor = now
        let target = DateComponents(hour: hour, minute: minute, weekday: weekday)
        while dates.count < count, let next = calendar.nextDate(after: cursor, matching: target, matchingPolicy: .nextTime) {
            dates.append(next)
            cursor = next
        }
        return dates
    }

    /// Pure, so the copy can be tested. Plain and fun.
    nonisolated static func message(ledger: Ledger, at fireDate: Date, calendar: Calendar) -> RunNotifier.Message {
        let weekStart = fireDate.addingTimeInterval(-7 * 86_400)
        let beers = ledger.beers.filter { $0.createdAt >= weekStart && $0.createdAt < fireDate }.count
        let miles = ledger.runs
            .filter { $0.endedAt >= weekStart && $0.endedAt < fireDate && $0.endedAt >= ledger.booksOpenedAt }
            .reduce(0) { $0 + $1.distanceMiles }
        let balance = BalanceEngine.report(for: ledger, at: fireDate).balance

        let standing: String
        switch balance.state {
        case .debt: standing = "You're at \(Format.miles(balance.debtMiles)) owed."
        case .credit: standing = "You've got \(Format.beersLabel(balance.creditBeers)) banked."
        case .even: standing = "Books are clean."
        }
        let tally = "\(beers == 1 ? "1 beer" : "\(beers) beers"), \(Format.miles(miles)) run."
        let body: String
        if beers == 0 && miles < 0.05 {
            body = "\(tally) Nothing to report. Suspicious."
        } else if beers > 0 && miles < 0.05 {
            body = "\(tally) The running part is optional, apparently. \(standing)"
        } else {
            body = "\(tally) \(standing)"
        }
        return RunNotifier.Message(title: "Your week in beer", body: body)
    }
}
