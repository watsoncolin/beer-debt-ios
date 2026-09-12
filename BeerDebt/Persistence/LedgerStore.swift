import Foundation
import Observation

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
        let dir = directory ?? Self.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        fileURL = dir.appendingPathComponent("ledger.json")
        let opened = now.flooredToSecond

        if let data = try? Data(contentsOf: fileURL) {
            do {
                ledger = try Self.decoder.decode(Ledger.self, from: data)
            } catch {
                // Never silently discard the books: set the unreadable file
                // aside and start fresh.
                let aside = dir.appendingPathComponent(
                    "ledger-unreadable-\(Int(opened.timeIntervalSince1970)).json"
                )
                try? FileManager.default.moveItem(at: fileURL, to: aside)
                ledger = Ledger(openedAt: opened)
                loadError = "Couldn't read the ledger, so the books were reopened. The old file was kept as \(aside.lastPathComponent)."
                save()
            }
        } else {
            ledger = Ledger(openedAt: opened)
            save()
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

    /// Idempotent. Returns how many runs were new; a HealthKit workout already
    /// on the books is skipped (spec §14).
    @discardableResult
    func importRuns(_ runs: [RunEntry]) -> Int {
        var added = 0
        for run in runs where !ledger.containsRun(healthKitWorkoutID: run.healthKitWorkoutID) {
            ledger.runs.append(run)
            added += 1
        }
        if added > 0 { save() }
        return added
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

    private static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeerDebt", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func save() {
        do {
            let data = try Self.encoder.encode(ledger)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save ledger: \(error)")
        }
    }
}
