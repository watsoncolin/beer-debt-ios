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
        switch streak.currentStreakDays {
        case 0: "Run 1+ mile today and tomorrow to pause interest."
        case 1: "Run 1+ mile tomorrow to unlock 0% APR."
        default:
            if streak.todayProtected {
                balance == .debt ? "Interest paused" : "0% APR — earned. Keep it going."
            } else {
                balance == .debt ? "Run 1+ mile today to keep interest paused." : "Run 1+ mile today to keep it."
            }
        }
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
