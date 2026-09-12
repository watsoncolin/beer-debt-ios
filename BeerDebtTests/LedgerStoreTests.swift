import Foundation
import Testing
@testable import BeerDebt

@MainActor
struct LedgerStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("beerdebt-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func freshStoreOpensTheBooksAtZero() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        #expect(store.ledger.beers.isEmpty)
        #expect(store.ledger.runs.isEmpty)
        #expect(store.ledger.rulesHistory.count == 1)
        #expect(store.ledger.booksOpenedAt == t0)
        #expect(store.currentRules == .default)
        #expect(store.report(at: at(hour)).balance == .even)
    }

    @Test func beersSurviveARelaunchWithTheSameBalance() {
        let dir = tempDir()
        let first = LedgerStore(directory: dir, now: t0)
        let added = first.addBeer(at: at(hour))
        let second = LedgerStore(directory: dir, now: at(day))
        #expect(second.ledger.beers == [added])
        #expect(second.ledger.booksOpenedAt == t0)
        #expect(second.report(at: at(3 * day)) == first.report(at: at(3 * day)))
    }

    @Test func sameWorkoutIsNeverCountedTwice() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        let workout = UUID()
        let entry = run(3, endedAt: at(hour), workoutID: workout)
        #expect(store.importRuns([entry]) == 1)
        #expect(store.importRuns([entry]) == 0)
        #expect(store.importRuns([run(3, endedAt: at(hour), workoutID: workout)]) == 0)
        #expect(store.ledger.runs.count == 1)
        #expect(close(store.report(at: at(hour)).balance.creditMiles, 3.0))
    }

    @Test func rulesChangesAppendForwardOnly() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        var rules = store.currentRules
        rules.interestRate = 0.2
        store.updateRules(rules, at: at(hour))
        store.updateRules(rules, at: at(2 * hour))
        #expect(store.ledger.rulesHistory.count == 2)
        #expect(store.ledger.rulesHistory.last?.effectiveAt == at(hour))
        #expect(store.currentRules.interestRate == 0.2)
    }

    @Test func aForgottenBeerCanBeDatedBack() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        let beer = store.addBeer(at: at(2 * day))
        #expect(beer.recordedAt == at(2 * day))
        #expect(!beer.isBackdated)

        let moved = store.updateBeerDate(id: beer.id, to: at(day + 0.4), now: at(2 * day))
        #expect(moved?.createdAt == at(day))
        #expect(moved?.recordedAt == at(2 * day))
        #expect(moved?.isBackdated == true)
        // The books are redone: it is a day old now, so interest has posted.
        #expect(close(store.report(at: at(2 * day)).balance.debtMiles, 1.10))

        let reloaded = LedgerStore(directory: store.directory, now: at(3 * day))
        #expect(reloaded.ledger.beers == store.ledger.beers)
    }

    @Test func aBeerCanBeTakenOffTheBooks() {
        let dir = tempDir()
        let store = LedgerStore(directory: dir, now: t0)
        let keep = store.addBeer(at: at(hour))
        let mistake = store.addBeer(at: at(2 * hour))
        #expect(store.removeBeer(id: mistake.id))
        #expect(!store.removeBeer(id: mistake.id))
        #expect(store.ledger.beers == [keep])
        #expect(close(store.report(at: at(3 * hour)).balance.debtMiles, 1.0))
        #expect(LedgerStore(directory: dir, now: at(day)).ledger.beers == [keep])
    }

    @Test func beerDatesAreClampedToTheBooks() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        let beer = store.addBeer(at: at(hour))
        #expect(store.updateBeerDate(id: beer.id, to: at(-day), now: at(hour))?.createdAt == t0)
        #expect(store.updateBeerDate(id: beer.id, to: at(5 * day), now: at(hour))?.createdAt == at(hour))
        #expect(store.updateBeerDate(id: UUID(), to: t0, now: at(hour)) == nil)
    }

    @Test func unreadableLedgerIsSetAsideNotDeleted() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("ledger.json"))
        let store = LedgerStore(directory: dir, now: t0)
        #expect(store.loadError != nil)
        #expect(store.ledger.beers.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("ledger-unreadable-") })
        #expect(files.contains("ledger.json"))
    }

    @Test func timestampsAreWholeSecondsSoAReloadIsExact() {
        let dir = tempDir()
        let store = LedgerStore(directory: dir, now: t0.addingTimeInterval(0.7))
        store.addBeer(at: at(hour + 0.3))
        var rules = store.currentRules
        rules.milesPerBeer = 2
        store.updateRules(rules, at: at(2 * hour + 0.9))
        let reloaded = LedgerStore(directory: dir, now: at(day))
        #expect(reloaded.ledger == store.ledger)
        #expect(reloaded.ledger.booksOpenedAt == t0)
    }
}
