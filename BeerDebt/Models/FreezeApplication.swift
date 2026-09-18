import Foundation

/// The user's decision to spend a streak freeze on one calendar day
/// (spec §25.1, APPS-6). Append-only and immutable like every other event.
///
/// This is the *only* freeze state on disk. How many freezes have been earned,
/// which applications were honoured, and which were refunded are all derived
/// from the runs by `StreakEngine` every replay — because all three change when
/// the runs do. A late HealthKit import that brings a frozen day to a mile
/// makes that day qualify on its own, so its application is simply ignored and
/// the freeze is back in inventory: the refund needs no event and no
/// reconciliation pass, which is the part that would otherwise carry the bugs.
struct FreezeApplication: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// An instant inside the frozen local day -- midday, not midnight.
    ///
    /// The engine re-buckets this through whatever calendar it is replaying
    /// with, exactly as it buckets a run by `endedAt`. Midnight would sit on a
    /// day boundary, so a user who crossed a time zone between the tap and the
    /// replay would see the freeze slide onto the day before. Midday has
    /// twelve hours of slack either side, which covers every real zone.
    let day: Date
    /// When the user tapped. Kept for ordering and for the record; the engine
    /// keys off `day`.
    let appliedAt: Date

    init(id: UUID = UUID(), day: Date, appliedAt: Date) {
        self.id = id
        self.day = day.flooredToSecond
        self.appliedAt = appliedAt.flooredToSecond
    }

    /// The application for the local day containing `instant`, keyed to midday.
    static func forDay(containing instant: Date, calendar: Calendar, appliedAt: Date) -> FreezeApplication {
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: instant)) ?? instant
        return FreezeApplication(day: noon, appliedAt: appliedAt)
    }
}
