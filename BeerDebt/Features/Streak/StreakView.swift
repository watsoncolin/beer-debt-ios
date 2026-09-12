import SwiftUI

/// "Your Streak" (spec §25): the number, what it has earned, this week's days,
/// the records, and the rule in plain words.
struct StreakView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        let now = Date.now
        let report = store.report(at: now)
        let streak = report.streak
        List {
            Section {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        StreakFlame(lit: streak.currentStreakDays >= 1, size: 64)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(streak.currentStreakDays == 1 ? "1 day" : "\(streak.currentStreakDays) days")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.cream)
                            Text(StreakCopy.standing(streak))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(streak.interestProtectionActive ? Theme.gold : Theme.cream.opacity(0.7))
                        }
                        Spacer()
                    }
                    Text(StreakCopy.detail(streak))
                        .font(.footnote)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            }
            .cardRow()

            Section("This week") {
                WeekRow(streak: streak, now: now)
                    .padding(.vertical, 6)
            }
            .cardRow()

            Section {
                LabeledContent("Longest streak", value: days(streak.longestStreakDays))
                LabeledContent("Total streak days", value: "\(streak.totalQualifyingDays)")
            }
            .cardRow()

            Section("How it works") {
                VStack(alignment: .leading, spacing: 8) {
                    rule("Run at least 1.0 mile of verified running each day. Two short runs add up.")
                    rule("After two days in a row, interest on your beer debt pauses.")
                    rule("Keep running daily to keep your 0% rate. Miss a day and the streak ends.")
                    rule("Your streak never reduces what you already owe.")
                }
                .padding(.vertical, 4)
            }
            .cardRow()
        }
        .forestScreen()
        .navigationTitle("Your Streak")
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Theme.gold)
            Text(text).foregroundStyle(Theme.cream.opacity(0.85))
        }
        .font(.subheadline)
    }
}

/// Seven circles for the current calendar week: done, today (pending), future, missed.
private struct WeekRow: View {
    let streak: StreakStatus
    let now: Date

    var body: some View {
        let calendar = streak.calendar
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let symbols = calendar.veryShortWeekdaySymbols
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let entry = streak.day(on: day)
                let weekday = calendar.component(.weekday, from: day)
                VStack(spacing: 6) {
                    circle(for: day, entry: entry, today: today)
                    Text(symbols[(weekday - 1) % 7])
                        .font(.caption2)
                        .foregroundStyle(Theme.cream.opacity(day > today ? 0.4 : 0.7))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func circle(for day: Date, entry: StreakDay?, today: Date) -> some View {
        if let entry, entry.qualifies {
            ZStack {
                Circle().fill(Theme.credit)
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
            }
            .frame(width: 28, height: 28)
        } else if day == today {
            Circle().strokeBorder(Theme.gold, lineWidth: 2).frame(width: 28, height: 28)
        } else if day > today {
            Circle().strokeBorder(Theme.cream.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 28, height: 28)
        } else {
            Circle().strokeBorder(Theme.cream.opacity(0.25), lineWidth: 1).frame(width: 28, height: 28)
        }
    }
}
