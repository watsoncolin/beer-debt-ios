import Foundation
import Observation
import WidgetKit

/// Owns the persisted event ledger and exposes derived reports to the UI.
/// Local-first: one JSON file in Application Support, written atomically
/// (spec §15, §16). Views never touch the engine directly.
@MainActor
@Observable
final class LedgerStore {
    private(set) var ledger: Ledger
    /// Set when an existing ledger file couldn't be read (it is kept, renamed).
    private(set) var loadError: String?
    /// Folder holding `ledger.json`.
    let directory: URL
    private let fileURL: URL

    /// - Parameters:
    ///   - directory: where `ledger.json` lives. Defaults to
    ///     Application Support/BeerDebt. Tests pass a temporary directory.
    ///   - now: the instant the books open if there is no ledger yet.
    init(directory: URL? = nil, now: Date = .now) {
        let dir = directory ?? LedgerFile.sharedDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        fileURL = dir.appendingPathComponent(LedgerFile.fileName)
        let opened = now.flooredToSecond
        if directory == nil { Self.migrateLegacyFile(to: fileURL) }

        if let data = try? Data(contentsOf: fileURL) {
            do {
                ledger = try LedgerFile.decoder.decode(Ledger.self, from: data)
            } catch {
                // Never silently discard the books: set the unreadable file
                // aside and start fresh.
                let aside = dir.appendingPathComponent(
                    "ledger-unreadable-\(Int(opened.timeIntervalSince1970)).json"
                )
                try? FileManager.default.moveItem(at: fileURL, to: aside)
                ledger = Ledger(openedAt: opened)
                loadError = "Couldn't read the ledger, so the books were reopened. The old file was kept as \(aside.lastPathComponent)."
                Telemetry.report(error, context: "store", ["op": "load", "bytes": data.count])
                save()
            }
        } else {
            ledger = Ledger(openedAt: opened)
            save()
        }
        // Streak protection arrived after 1.0. Ledgers from before decode it as
        // off; switch it on from now, as a rules change, so history stands.
        if !ledger.currentRules.streakProtection {
            var rules = ledger.currentRules
            rules.streakProtection = true
            updateRules(rules, at: now)
        }
    }

    // MARK: Reading

    func report(at now: Date = .now) -> Report {
        BalanceEngine.report(for: ledger, at: now)
    }

    var currentRules: Rules { ledger.currentRules }

    // MARK: Events

    /// Records one beer immediately, no confirmation (spec §3).
    @discardableResult
    func addBeer(at date: Date = .now) -> BeerEntry {
        let at = date.flooredToSecond
        let beer = BeerEntry(createdAt: at, recordedAt: at)
        ledger.beers.append(beer)
        save()
        return beer
    }

    func beer(id: UUID) -> BeerEntry? {
        ledger.beers.first { $0.id == id }
    }

    /// How far back a forgotten beer can be dated.
    static let backdatingWindow: TimeInterval = 30 * 24 * 60 * 60

    /// Earliest date a beer may carry. A beer may predate the books (you can
    /// own up to last week's beers on day one); runs from before the books
    /// opened still never count.
    func earliestBeerDate(now: Date = .now) -> Date {
        now.addingTimeInterval(-Self.backdatingWindow).flooredToSecond
    }

    /// Moves a beer on the timeline, for one logged late. Clamped to the last
    /// 30 days and no later than `now`. The next replay redoes the books as if
    /// the beer had been logged then. Returns the stored entry, or nil if there
    /// is no such beer.
    @discardableResult
    func updateBeerDate(id: UUID, to date: Date, now: Date = .now) -> BeerEntry? {
        guard let index = ledger.beers.firstIndex(where: { $0.id == id }) else { return nil }
        let clamped = min(max(date.flooredToSecond, earliestBeerDate(now: now)), now.flooredToSecond)
        if clamped != ledger.beers[index].createdAt {
            ledger.beers[index].createdAt = clamped
            save()
        }
        return ledger.beers[index]
    }

    /// Idempotent. Returns the runs that were new; a HealthKit workout already
    /// on the books is skipped (spec §14).
    @discardableResult
    func importRuns(_ runs: [RunEntry]) -> [RunEntry] {
        var added: [RunEntry] = []
        for run in runs where !ledger.containsRun(healthKitWorkoutID: run.healthKitWorkoutID)
            && !ledger.excludedWorkoutIDs.contains(run.healthKitWorkoutID) {
            ledger.runs.append(run)
            added.append(run)
        }
        if !added.isEmpty { save() }
        return added
    }

    /// Takes a run off the books by the user's choice, and keeps it off: the
    /// workout stays in Health but is never imported again. The next replay
    /// puts whatever it paid back on the tab.
    @discardableResult
    func deleteRun(id: UUID) -> Bool {
        guard let index = ledger.runs.firstIndex(where: { $0.id == id }) else { return false }
        let run = ledger.runs.remove(at: index)
        ledger.excludedWorkoutIDs.insert(run.healthKitWorkoutID)
        save()
        return true
    }

    /// Takes runs off the books when their workouts were deleted from Health.
    /// The next replay puts any beers they paid back on the tab. Returns how
    /// many were removed.
    @discardableResult
    func removeRuns(healthKitWorkoutIDs ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        let before = ledger.runs.count
        ledger.runs.removeAll { ids.contains($0.healthKitWorkoutID) }
        let removed = before - ledger.runs.count
        if removed > 0 { save() }
        return removed
    }

    /// Takes a beer off the books entirely, for an accidental tap. The next
    /// replay re-routes any run that paid for it. Returns false if no such beer.
    @discardableResult
    func removeBeer(id: UUID) -> Bool {
        guard let index = ledger.beers.firstIndex(where: { $0.id == id }) else { return false }
        ledger.beers.remove(at: index)
        save()
        return true
    }

    /// Moves the opening of the books earlier, so runs that ended in the newly
    /// covered window can count. Earlier only (a later date would strand runs
    /// already on the books), no more than a year back. The opening rules
    /// move with it so they stay effective from day one. The caller must
    /// re-read Health from scratch afterwards, since older workouts were
    /// dropped at import. Returns false if the date wasn't earlier.
    @discardableResult
    func reopenBooks(at date: Date, now: Date = .now) -> Bool {
        let earliest = now.addingTimeInterval(-Self.reopeningWindow).flooredToSecond
        let opened = max(date.flooredToSecond, earliest)
        guard opened < ledger.booksOpenedAt else { return false }
        let previous = ledger.booksOpenedAt
        ledger.booksOpenedAt = opened
        if let first = ledger.rulesHistory.first, first.effectiveAt == previous {
            ledger.rulesHistory[0] = RulesChange(effectiveAt: opened, rules: first.rules)
        }
        save()
        return true
    }

    /// How far back the books can be reopened.
    static let reopeningWindow: TimeInterval = 365 * 24 * 60 * 60

    /// Records a rules change effective from `date` forward. No-op if nothing
    /// changed. History is append-only so replay stays deterministic.
    func updateRules(_ rules: Rules, at date: Date = .now) {
        guard rules != ledger.currentRules else { return }
        let lastEffective = ledger.rulesHistory.last?.effectiveAt ?? ledger.booksOpenedAt
        let effectiveAt = max(date.flooredToSecond, lastEffective)
        ledger.rulesHistory.append(RulesChange(effectiveAt: effectiveAt, rules: rules))
        save()
    }

    // MARK: Persistence

    /// One-time move from Application Support into the App Group container
    /// (added with the widget). Nothing to do once the shared file exists.
    private static func migrateLegacyFile(to shared: URL) {
        let legacy = LedgerFile.legacyDirectory.appendingPathComponent(LedgerFile.fileName)
        guard legacy != shared,
              FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: shared.path) else { return }
        try? FileManager.default.moveItem(at: legacy, to: shared)
    }

    /// Asks WidgetKit to re-read the ledger and rebuild its timeline.
    ///
    /// Called on every save, and again whenever the app becomes active or a
    /// sync finishes. The repeat is the point: a widget timeline is built from
    /// the ledger as it stood at the time, so a run imported afterwards is
    /// invisible until something asks for a reload, and a reload requested
    /// from a background wake can be dropped. Without a retry a dropped one
    /// sticks, because a sync that imports nothing never saves.
    func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func save() {
        do {
            let data = try LedgerFile.encoder.encode(ledger)
            try data.write(to: fileURL, options: .atomic)
            refreshWidgets()
        } catch {
            Telemetry.report(error, context: "store", [
                "op": "save", "beers": ledger.beers.count, "runs": ledger.runs.count,
            ])
            assertionFailure("Failed to save ledger: \(error)")
        }
    }
}
