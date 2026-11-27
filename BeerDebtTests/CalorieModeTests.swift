import Foundation
import Testing
@testable import BeerDebt

/// Calorie mode (spec §28, decisions §B.10): which workouts pay, how much, and
/// that switching is forward-only: a workout pays under the basis in force
/// when it ended, and what it paid never changes afterwards.
struct CalorieModeTests {

    // MARK: What pays

    @Test func runsModeIgnoresEverythingButRuns() {
        let l = ledger(beers: [beer(t0)], runs: [ride(kcal: 300, endedAt: at(hour))])
        let r = report(l, at: at(2 * hour))
        #expect(close(r.balance.debtMiles, 1.0))
        // Not even a zero statement: in runs mode a ride is not on the books.
        #expect(r.runs.isEmpty)
    }

    @Test func aRidePaysItsCaloriesAtTheRate() {
        let l = inCalories(ledger(rules: noDecay, beers: [beer(t0)], runs: [ride(kcal: 150, endedAt: at(hour))]))
        let r = report(l, at: at(2 * hour))
        #expect(r.balance.state == .credit)
        #expect(close(r.balance.creditMiles, 0.5))
        #expect(close(r.runs[0].debtPaidMiles, 1.0))
        #expect(close(r.runs[0].creditEarnedMiles, 0.5))
    }

    @Test func aRunPaysItsDistanceInEitherMode() {
        // Plenty of calories recorded, but a run is measured by the road.
        let run = RunEntry(healthKitWorkoutID: UUID(), startedAt: t0, endedAt: at(hour), distanceMeters: RunEntry.metersPerMile,
                           importedAt: at(hour), activityType: RunEntry.runningActivityType, activeEnergyKcal: 500)
        let runs = ledger(rules: noDecay, beers: [beer(t0)], runs: [run])
        #expect(report(runs, at: at(2 * hour)).balance == report(inCalories(runs), at: at(2 * hour)).balance)
        #expect(report(inCalories(runs), at: at(2 * hour)).balance == .even)
    }

    @Test func aWorkoutWithNoCaloriesPaysNothingButIsListed() {
        let l = inCalories(ledger(beers: [beer(t0)], runs: [ride(kcal: nil, endedAt: at(hour))]))
        let r = report(l, at: at(2 * hour))
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(r.runs.count == 1)
        #expect(r.runs[0].debtPaidMiles == 0)
        #expect(!r.runs[0].ignored)
    }

    @Test func aRideBeforeTheBooksOpenedIsIgnored() {
        let l = inCalories(ledger(runs: [ride(kcal: 500, endedAt: at(-hour))]))
        let r = report(l, at: at(hour))
        #expect(r.balance == .even)
        #expect(r.runs.map(\.ignored) == [true])
    }

    // MARK: Switching is forward-only

    @Test func aRidePaidInCaloriesStaysPaidAfterSwitchingToRuns() {
        // Colin's case: walks paid the tab down, then a switch to runs put it back up.
        let calories = inCalories(ledger(rules: noDecay, beers: [beer(t0), beer(t0)],
                                         runs: [ride(kcal: 100, endedAt: at(hour))]))
        let back = switched(calories, at: at(2 * hour), to: .runs)
        #expect(close(report(back, at: at(3 * hour)).balance.debtMiles, 1.0))
        #expect(report(back, at: at(3 * hour)).balance == report(calories, at: at(3 * hour)).balance)
        #expect(report(back, at: at(3 * hour)).runs.map(\.run.activityType) == [cyclingActivityType])
    }

    @Test func aRideAfterSwitchingToRunsPaysNothing() {
        let calories = inCalories(ledger(rules: noDecay, beers: [beer(t0)], runs: [ride(kcal: 300, endedAt: at(3 * hour))]))
        let back = switched(calories, at: at(2 * hour), to: .runs)
        let r = report(back, at: at(4 * hour))
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(r.runs.isEmpty)
    }

    @Test func aRideBeforeSwitchingToCaloriesNeverPays() {
        // No backfill: the ride ended while runs were in force.
        let runsOnly = ledger(rules: noDecay, beers: [beer(t0)], runs: [ride(kcal: 300, endedAt: at(hour))])
        let calories = switched(runsOnly, at: at(2 * hour), to: PaymentBasis(mode: .calories))
        let r = report(calories, at: at(3 * hour))
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(r.runs.isEmpty)
    }

    @Test func switchingChangesNothingAlreadyOnTheBooks() {
        let l = ledger(beers: [beer(t0), beer(t0)],
                       runs: [run(1, endedAt: at(hour)), ride(kcal: 100, endedAt: at(2 * hour))])
        let later = at(5 * day)
        for basis in [PaymentBasis(mode: .calories), PaymentBasis(mode: .calories, caloriesPerMile: 150)] {
            #expect(report(switched(l, at: later, to: basis), at: later) == report(l, at: later))
            let c = inCalories(l)
            #expect(report(switched(c, at: later, to: .runs), at: later) == report(c, at: later))
        }
    }

    @Test func theRateRescalesRidesButNotRuns() {
        let l = ledger(rules: noDecay, beers: [beer(t0), beer(t0), beer(t0)],
                       runs: [run(1, endedAt: at(hour)), ride(kcal: 150, endedAt: at(2 * hour))])
        #expect(close(report(inCalories(l, caloriesPerMile: 100), at: at(3 * hour)).balance.debtMiles, 0.5))
        #expect(close(report(inCalories(l, caloriesPerMile: 150), at: at(3 * hour)).balance.debtMiles, 1.0))
    }

    @Test func aRateChangeIsForwardOnly() {
        let l = inCalories(ledger(rules: noDecay, beers: [beer(t0), beer(t0), beer(t0)],
                                  runs: [ride(kcal: 150, endedAt: at(hour)), ride(kcal: 150, endedAt: at(3 * hour))]))
        let rerated = switched(l, at: at(2 * hour), to: PaymentBasis(mode: .calories, caloriesPerMile: 150))
        let r = report(rerated, at: at(4 * hour))
        // 1.5 mi at the old rate, then 1 mi at the new one.
        #expect(close(r.runs[0].paidMiles, 1.5))
        #expect(close(r.runs[1].paidMiles, 1.0))
        #expect(close(r.balance.debtMiles, 0.5))
    }

    // MARK: Streaks

    @Test func aRideCarriesTheStreakInCalorieModeOnly() {
        let l = ledger(beers: (0..<5).map { _ in beer(t0) },
                       runs: [run(1, endedAt: morning(1)), ride(kcal: 120, endedAt: morning(2))])
        #expect(report(l, at: at(2 * day + hour)).streak.currentStreakDays == 1)
        let calories = report(inCalories(l), at: at(2 * day + hour))
        #expect(calories.streak.currentStreakDays == 2)
        #expect(calories.streak.todayProtected)
    }

    @Test func aDayQualifiesAtOneMilesWorthOfCalories() {
        let rate = 100.0
        let under = inCalories(ledger(openedAt: at(-day), runs: [ride(kcal: rate - 1, endedAt: morning(0))]), caloriesPerMile: rate)
        let at100 = inCalories(ledger(openedAt: at(-day), runs: [ride(kcal: rate, endedAt: morning(0))]), caloriesPerMile: rate)
        #expect(!report(under, at: t0).streak.todayQualifies)
        #expect(report(at100, at: t0).streak.todayQualifies)
    }

    @Test func aRideDayStillCarriesTheStreakAfterSwitchingToRuns() {
        let l = inCalories(ledger(beers: (0..<5).map { _ in beer(t0) },
                                  runs: [run(1, endedAt: morning(1)), ride(kcal: 120, endedAt: morning(2))]))
        let back = switched(l, at: morning(2).addingTimeInterval(hour), to: .runs)
        #expect(report(back, at: at(2 * day + 2 * hour)).streak.currentStreakDays == 2)
    }

    @Test func aFreezeOnARideDayIsRefundedInCalorieMode() {
        var l = ledger(openedAt: utc.startOfDay(for: morning(0)), beers: (0..<5).map { _ in beer(t0) },
                       runs: (0..<5).map { run(1, endedAt: morning($0)) } + [ride(kcal: 200, endedAt: morning(5))])
        l.freezeApplications = [FreezeApplication.forDay(containing: morning(5), calendar: utc, appliedAt: morning(5))]
        let runsMode = report(l, at: at(5 * day + hour)).streak
        #expect(runsMode.todayFrozen)
        #expect(runsMode.freezesHeld == 0)
        let calorieMode = report(inCalories(l), at: at(5 * day + hour)).streak
        #expect(!calorieMode.todayFrozen)
        #expect(calorieMode.todayQualifies)
        #expect(calorieMode.freezesHeld == 1)
    }

    // MARK: On disk

    @Test func aLedgerFromBeforeCalorieModeReadsAsRuns() throws {
        let json = """
        {"version":1,"booksOpenedAt":"2026-09-12T20:00:00Z","beers":[],"excludedWorkoutIDs":[],
         "rulesHistory":[{"effectiveAt":"2026-09-12T20:00:00Z","rules":{"creditDecayRatePerWeek":0.1,"gracePeriod":86400,
           "interestPeriod":"daily","interestRate":0.1,"maximumCreditBeers":3,"milesPerBeer":1,"streakProtection":true}}],
         "runs":[{"id":"00000000-0000-4000-8000-000000000001","healthKitWorkoutID":"00000000-0000-4000-8000-000000000002",
           "startedAt":"2026-09-12T20:00:00Z","endedAt":"2026-09-12T20:30:00Z","distanceMeters":1609.344,
           "importedAt":"2026-09-12T20:30:00Z"}]}
        """
        let l = try LedgerFile.decoder.decode(Ledger.self, from: Data(json.utf8))
        #expect(l.payment == .runs)
        #expect(l.paymentHistory == [PaymentChange(effectiveAt: l.booksOpenedAt, payment: .runs)])
        #expect(l.runs[0].isRunning)
        #expect(l.runs[0].activeEnergyKcal == nil)
    }

    @Test func a12LedgerInCaloriesKeepsItsNumbers() throws {
        // 1.2 replayed everything under one basis, so it reads as in force
        // since the books opened and nothing moves on upgrade.
        let json = """
        {"version":1,"booksOpenedAt":"2026-09-12T20:00:00Z","beers":[],"excludedWorkoutIDs":[],"freezeApplications":[],
         "paymentMode":"calories","caloriesPerMile":120,
         "rulesHistory":[{"effectiveAt":"2026-09-12T20:00:00Z","rules":{"creditDecayRatePerWeek":0.1,"gracePeriod":86400,
           "interestPeriod":"daily","interestRate":0.1,"maximumCreditBeers":3,"milesPerBeer":1,"streakProtection":true}}],
         "runs":[]}
        """
        let l = try LedgerFile.decoder.decode(Ledger.self, from: Data(json.utf8))
        let basis = PaymentBasis(mode: .calories, caloriesPerMile: 120)
        #expect(l.paymentHistory == [PaymentChange(effectiveAt: l.booksOpenedAt, payment: basis)])
        #expect(l.hasCaloriePeriod)
    }

    @Test func theBasisRoundTrips() throws {
        let l = switched(inCalories(ledger(runs: [ride(kcal: 240, endedAt: at(hour))]), caloriesPerMile: 120),
                         at: at(2 * hour), to: .runs)
        let back = try LedgerFile.decoder.decode(Ledger.self, from: LedgerFile.encoder.encode(l))
        #expect(back == l)
    }
}

@MainActor
struct CalorieModeStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("beerdebt-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func switchingIsSavedAndClamped() {
        let dir = tempDir()
        let store = LedgerStore(directory: dir, now: t0)
        store.updatePayment(PaymentBasis(mode: .calories, caloriesPerMile: 99.6), at: at(hour))
        #expect(store.ledger.payment == PaymentBasis(mode: .calories, caloriesPerMile: 100))
        store.updatePayment(PaymentBasis(mode: .calories, caloriesPerMile: 5), at: at(2 * hour))
        #expect(store.ledger.caloriesPerMile == LedgerStore.caloriesPerMileRange.lowerBound)
        // Not a rules change: nothing is appended to the rules history.
        #expect(store.ledger.rulesHistory.count == 1)
        #expect(store.ledger.paymentHistory.map(\.effectiveAt) == [t0, at(hour), at(2 * hour)])
        #expect(LedgerStore(directory: dir, now: at(3 * hour)).ledger.paymentMode == .calories)
    }

    @Test func switchingAppendsAndKeepsWhatWasPaid() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        store.updatePayment(PaymentBasis(mode: .calories), at: t0)
        store.addBeer(at: t0)
        store.addBeer(at: t0)
        store.importRuns([ride(kcal: 100, endedAt: at(hour))])
        let paid = store.report(at: at(2 * hour)).balance
        store.updatePayment(.runs, at: at(2 * hour))
        #expect(store.ledger.paymentHistory.map(\.mode) == [.runs, .calories, .runs])
        #expect(store.report(at: at(2 * hour)).balance == paid)
    }

    @Test func flippingBackWithinASecondRecordsNothing() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        store.updatePayment(PaymentBasis(mode: .calories), at: at(hour))
        store.updatePayment(.runs, at: at(hour))
        #expect(store.ledger.paymentHistory.map(\.mode) == [.runs])
    }

    @Test func theOpeningChoiceCoversTheBooksFromDayOne() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        store.chooseOpeningPayment(PaymentBasis(mode: .calories))
        #expect(store.ledger.paymentHistory == [PaymentChange(effectiveAt: t0, payment: PaymentBasis(mode: .calories))])
    }

    @Test func reopeningTheBooksMovesTheOpeningBasis() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        store.chooseOpeningPayment(PaymentBasis(mode: .calories))
        #expect(store.reopenBooks(at: at(-day), now: t0))
        #expect(store.ledger.paymentHistory.first?.effectiveAt == at(-day))
    }

    @Test func bankruptcyKeepsTheBasisAndWritesOffRides() {
        let store = LedgerStore(directory: tempDir(), now: t0)
        store.updatePayment(PaymentBasis(mode: .calories, caloriesPerMile: 120), at: t0)
        let workout = UUID()
        store.importRuns([ride(kcal: 300, endedAt: at(hour), workoutID: workout)])
        #expect(store.declareBankruptcy(now: at(2 * hour)))
        #expect(store.ledger.paymentHistory == [PaymentChange(effectiveAt: at(2 * hour),
                                                              payment: PaymentBasis(mode: .calories, caloriesPerMile: 120))])
        #expect(store.ledger.excludedWorkoutIDs.contains(workout))
    }
}
