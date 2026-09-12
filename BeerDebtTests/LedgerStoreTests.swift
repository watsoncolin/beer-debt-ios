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
        #expect(store.importRuns([entry]).count == 1)
        #expect(store.importRuns([entry]).isEmpty)
        #expect(store.importRuns([run(3, endedAt: at(hour), workoutID: workout)]).isEmpty)
        #expect(store.ledger.runs.count == 1)
        #expect(close(store.report(at: at(hour)).balance.creditMiles, 3.0))
    }

    @Test func aWorkoutDeletedFromHealthComesOffTheBooks() {
        let dir = tempDir()
        let store = LedgerStore(directory: dir, now: t0)
        store.addBeer(at: t0)
        let workout = UUID()
        store.importRuns([run(1, endedAt: at(hour), workoutID: workout)])
        #expect(store.report(at: at(2 * hour)).balance.state == .even)

        #expect(store.removeRuns(healthKitWorkoutIDs: [workout]) == 1)
        #expect(store.removeRuns(healthKitWorkoutIDs: [workout]) == 0)
        #expect(store.removeRuns(healthKitWorkoutIDs: []) == 0)
        // The beer it paid is back on the tab, as if the run never happened.
        let r = store.report(at: at(2 * hour))
        #expect(r.balance.state == .debt)
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(!r.beers[0].isPaid)
        #expect(LedgerStore(directory: dir, now: at(day)).ledger.runs.isEmpty)
    }

    @Test func aRunDeletedInTheAppStaysOffTheBooks() {
        let dir = tempDir()
        let store = LedgerStore(directory: dir, now: t0)
        store.addBeer(at: t0)
        let workout = UUID()
        let entry = run(1, endedAt: at(hour), workoutID: workout)
        store.importRuns([entry])
        #expect(store.report(at: at(2 * hour)).balance.state == .even)

        #expect(store.deleteRun(id: entry.id))
        #expect(!store.deleteRun(id: entry.id))
        #expect(store.report(at: at(2 * hour)).balance.state == .debt)
        // A fresh sync offering the same workout again is refused.
        #expect(store.importRuns([run(1, endedAt: at(hour), workoutID: workout)]).isEmpty)
        let reloaded = LedgerStore(directory: dir, now: at(day))
        #expect(reloaded.ledger.runs.isEmpty)
        #expect(reloaded.ledger.excludedWorkoutIDs == [workout])
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

    @Test func beerDatesAreClampedToTheLastThirtyDaysAndNow() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        let beer = store.addBeer(at: at(hour))
        // Before the books opened is fine: day-one users own up to last night's beers.
        #expect(store.updateBeerDate(id: beer.id, to: at(-day), now: at(hour))?.createdAt == at(-day))
        #expect(store.updateBeerDate(id: beer.id, to: at(-40 * day), now: at(hour))?.createdAt == at(hour - 30 * day))
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

    @Test func theBooksCanBeOpenedEarlierButNotLater() {
        let dir = tempDir()
        let store = LedgerStore(directory: dir, now: t0)
        #expect(!store.reopenBooks(at: at(day), now: at(2 * day)))          // later: refused
        #expect(!store.reopenBooks(at: t0, now: at(2 * day)))               // same: refused
        #expect(store.reopenBooks(at: at(-3 * day), now: at(2 * day)))
        #expect(store.ledger.booksOpenedAt == at(-3 * day))
        // The opening rules move with the books, so day one is still under them.
        #expect(store.ledger.rulesHistory.first?.effectiveAt == at(-3 * day))
        // A run from the newly covered days now counts.
        store.importRuns([run(2, endedAt: at(-2 * day))])
        #expect(store.report(at: at(2 * day)).runs.first?.ignored == false)
        #expect(LedgerStore(directory: dir, now: at(3 * day)).ledger.booksOpenedAt == at(-3 * day))
    }

    @Test func reopeningIsClampedToAYear() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        #expect(store.reopenBooks(at: at(-800 * day), now: t0))
        #expect(store.ledger.booksOpenedAt == at(-365 * day))
    }
}
