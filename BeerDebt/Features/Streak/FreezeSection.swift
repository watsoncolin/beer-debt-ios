import SwiftUI

/// The freeze half of "Your Streak" (spec §25.1): what is in hand, and the
/// only two things that can be done with it.
///
/// A freeze is never spent automatically, so every path here is a tap. The
/// two offers are mutually exclusive by construction: `canFreezeToday` needs a
/// live streak and no mile yet today, while `repairableDay` only exists once a
/// day has already been missed.
struct FreezeSection: View {
    @Environment(LedgerStore.self) private var store
    let report: Report
    let now: Date

    private var streak: StreakStatus { report.streak }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if streak.todayFrozen {
                restDay
            } else if streak.canFreezeToday {
                offer(
                    title: StreakCopy.freezeOfferTitle,
                    body: StreakCopy.freezeOfferBody,
                    button: StreakCopy.freezeOfferButton
                ) { store.freezeToday(now: now) }
            } else if let day = streak.repairableDay {
                offer(
                    title: StreakCopy.freezeOfferTitle,
                    body: StreakCopy.repairOfferBody(streak, formattedDay: Format.dayPhrase(day, now: now, calendar: streak.calendar)),
                    button: StreakCopy.repairOfferButton
                ) { store.applyFreeze(on: day, now: now) }
            } else if let progress = StreakCopy.freezeProgress(streak) {
                Text(progress)
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.7))
            } else {
                // A freeze in hand with nothing to spend it on: today's mile is
                // already run, so it keeps until a day is missed.
                Text("1 freeze in hand, ready for a day off.")
                    .font(.footnote)
                    .foregroundStyle(Theme.frost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("🧊")
                Text(StreakCopy.restDayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.frost)
            }
            Text("\(StreakCopy.restDayStanding(streak)). Get back out there tomorrow.")
                .font(.footnote)
                .foregroundStyle(Theme.cream.opacity(0.75))
        }
    }

    private func offer(title: String, body: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("🧊")
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.frost)
            }
            Text(body)
                .font(.footnote)
                .foregroundStyle(Theme.cream.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(GoldButtonStyle())
        }
    }
}
