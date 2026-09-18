import SwiftUI

/// The streak mark. Uses the painted flame from the asset catalog when it is
/// there (`StreakFlame` / `StreakFlameUnlit`), otherwise the SF Symbol, so the
/// feature works before the art lands.
struct StreakFlame: View {
    var lit: Bool = true
    var size: CGFloat = 40

    private var assetName: String { lit ? "StreakFlame" : "StreakFlameUnlit" }

    var body: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: lit ? "flame.fill" : "flame")
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(lit ? Theme.gold : Theme.cream.opacity(0.45))
                .frame(width: size, height: size)
        }
    }
}

/// Words for the streak, shared by the Home card, the detail screen, the
/// sheets, and the notification (spec §25). The bank's voice: the streak is
/// a rate you earned, not a cheer.
enum StreakCopy {
    static func title(_ streak: StreakStatus) -> String {
        switch streak.currentStreakDays {
        case 0: "Start a streak"
        case 1: "1 day streak"
        default: "\(streak.currentStreakDays) day streak"
        }
    }

    /// The line under the title on the Home card.
    static func subtitle(_ streak: StreakStatus, balance: BalanceState) -> String {
        // A rest day speaks for itself, whatever the streak length.
        if streak.todayFrozen {
            return balance == .debt ? "Rest day — interest still paused" : "Rest day — 0% APR still active"
        }
        switch streak.currentStreakDays {
        case 0: return "Run 1+ mile today and tomorrow to pause interest."
        case 1: return "Run 1+ mile tomorrow to unlock 0% APR."
        default:
            if streak.todayProtected {
                return balance == .debt ? "Interest paused" : "0% APR — earned. Keep it going."
            }
            // A freeze in hand turns the nudge into a choice.
            if streak.canFreezeToday {
                return "Run 1+ mile today, or spend your freeze."
            }
            return balance == .debt ? "Run 1+ mile today to keep interest paused." : "Run 1+ mile today to keep it."
        }
    }

    // MARK: Freezes (spec §25.1)

    /// "🧊 1 Freeze" — the inventory badge. Nil when there is none to show.
    static func freezeBadge(_ streak: StreakStatus) -> String? {
        streak.freezesHeld > 0 ? "\(streak.freezesHeld) Freeze" : nil
    }

    /// Progress toward the next one, for the detail screen. Nil while one is
    /// held, since holding one stops the next accruing.
    static func freezeProgress(_ streak: StreakStatus) -> String? {
        guard streak.freezesHeld == 0 else { return nil }
        let left = StreakEngine.daysPerFreeze - streak.freezeProgressDays
        if left == 1 { return "1 more running day earns a freeze." }
        return "\(left) more running days earn a freeze."
    }

    /// The title on the rest-day state.
    static let restDayTitle = "Rest day"

    /// What a frozen streak reads as on the detail screen.
    static func restDayStanding(_ streak: StreakStatus) -> String {
        "\(streak.currentStreakDays) day streak protected"
    }

    /// The offer to spend one on today.
    static let freezeOfferTitle = "Freeze available"
    static let freezeOfferBody = "Taking today off? Use your streak freeze to protect your streak and keep 0% APR."
    static let freezeOfferButton = "Use Freeze Today"

    /// The offer to repair the day that broke the streak.
    static func repairOfferBody(_ streak: StreakStatus, formattedDay: String) -> String {
        "You missed \(formattedDay). Spend your freeze to keep the \(streak.currentStreakDays) day streak it broke."
    }
    static let repairOfferButton = "Use Freeze"

    /// The earned sheet.
    static let freezeEarnedTitle = "Streak freeze earned"
    static func freezeEarnedBody() -> String {
        "\(StreakEngine.daysPerFreeze) qualifying run days. You've earned a day off without losing your streak."
    }

    /// The big line on the detail screen.
    static func standing(_ streak: StreakStatus) -> String {
        switch streak.currentStreakDays {
        case 0: "No streak yet."
        case 1: "Day one. Nothing earned yet."
        default: streak.todayProtected ? "0% APR — earned." : "0% APR — earned, if you run today."
        }
    }

    static func detail(_ streak: StreakStatus) -> String {
        switch streak.currentStreakDays {
        case 0: "Run 1+ mile today and tomorrow. From day two, interest on your tab pauses."
        case 1: "Run 1+ mile tomorrow to unlock 0% APR."
        default: "Keep running 1+ mile each day to keep interest paused."
        }
    }
}
