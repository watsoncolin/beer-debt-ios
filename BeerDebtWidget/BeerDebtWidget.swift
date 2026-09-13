import SwiftUI
import WidgetKit

@main
struct BeerDebtWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
    }
}

/// Home Screen and Lock Screen glance at the tab (spec §22). Reads the shared
/// ledger and replays it, so the numbers are exactly the app's; timeline
/// entries land on each upcoming interest posting.
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BalanceWidget", provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Beer Debt")
        .description("Your tab, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: .now, report: BalanceEngine.report(for: SampleLedger.make(), at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        let now = Date.now
        // The sample ledger is for the gallery only. Anywhere else, a missing
        // shared file means something is wrong, and inventing a balance would
        // read as a real one.
        guard let ledger = context.isPreview ? SampleLedger.make(now: now) : LedgerFile.load() else {
            completion(BalanceEntry(date: now, report: nil))
            return
        }
        completion(BalanceEntry(date: now, report: BalanceEngine.report(for: ledger, at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let now = Date.now
        let refresh = BalanceTimeline.refresh(after: now)
        guard let ledger = LedgerFile.load() else {
            completion(Timeline(entries: [BalanceEntry(date: now, report: nil)], policy: .after(refresh)))
            return
        }
        let dates = BalanceTimeline.entryDates(
            now: now,
            nextInterestAt: BalanceEngine.report(for: ledger, at: now).nextInterestAt
        )
        let entries = dates.map { BalanceEntry(date: $0, report: BalanceEngine.report(for: ledger, at: $0)) }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

/// Placeholder content for the widget gallery.
enum SampleLedger {
    static func make(now: Date = .now) -> Ledger {
        var ledger = Ledger(openedAt: now.addingTimeInterval(-10 * 86_400))
        let day = 86_400.0
        ledger.beers = [
            BeerEntry(createdAt: now.addingTimeInterval(-5 * day - 3_600)),
            BeerEntry(createdAt: now.addingTimeInterval(-3 * day - 7_200)),
            BeerEntry(createdAt: now.addingTimeInterval(-2 * day - 10_800)),
            BeerEntry(createdAt: now.addingTimeInterval(-6 * 3_600)),
        ]
        ledger.runs = [
            RunEntry(healthKitWorkoutID: UUID(), startedAt: now.addingTimeInterval(-4 * day), endedAt: now.addingTimeInterval(-4 * day + 3_600),
                     distanceMeters: 1.0 * RunEntry.metersPerMile, importedAt: now, sourceName: "Apple Watch"),
        ]
        return ledger
    }
}
