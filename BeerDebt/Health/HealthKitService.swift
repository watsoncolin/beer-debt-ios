import Foundation
import HealthKit

/// Read-only bridge to HealthKit. Requests the minimum for the payment mode
/// (spec §14, §28): in runs mode, workouts (filtered to running) and the
/// distance type needed to read a workout's distance; calorie mode adds every
/// workout type and active energy, asked for only when the user picks it.
/// Nothing is written to Health.
@MainActor
final class HealthKitService {
    struct FetchResult: Sendable {
        let runs: [RunEntry]
        /// Workouts deleted from Health since the last anchor. Their runs must
        /// come off the books too.
        let deletedWorkoutIDs: [UUID]
        /// Opaque `HKQueryAnchor`, archived. Persist and pass back next time.
        let anchor: Data
    }

    private let store = HKHealthStore()
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private var observer: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private func readTypes(for mode: PaymentMode) -> Set<HKObjectType> {
        switch mode {
        case .runs: [HKObjectType.workoutType(), distanceType]
        case .calories: [HKObjectType.workoutType(), distanceType, energyType]
        }
    }

    /// Runs only, or every workout. Nil means no filter.
    private func predicate(for mode: PaymentMode) -> NSPredicate? {
        switch mode {
        case .runs: HKQuery.predicateForWorkouts(with: .running)
        case .calories: nil
        }
    }

    /// HealthKit never reveals whether *read* access was granted, only whether
    /// the user has been asked. This is the best available "connected" signal.
    func hasBeenAsked(for mode: PaymentMode) async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes(for: mode))
        return status == .unnecessary
    }

    func requestAuthorization(for mode: PaymentMode) async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes(for: mode))
    }

    /// Workouts the mode reads, added or deleted since `anchor` (everything
    /// when nil). Incremental and idempotent: the returned anchor picks up
    /// where this call left off.
    func fetchWorkouts(for mode: PaymentMode, anchor anchorData: Data?) async throws -> FetchResult {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(predicate(for: mode))],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        let importedAt = Date.now.flooredToSecond

        let runs = result.addedSamples.compactMap { workout -> RunEntry? in
            let isRun = workout.workoutActivityType == .running
            // Apps that record a run attach distance samples, which land in the
            // workout's statistics. A workout typed into the Health app by hand
            // carries its distance only as `totalDistance`, so fall back to it.
            var meters = isRun
                ? workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                : 0
            if meters <= 0, let total = workout.totalDistance?.doubleValue(for: .meter()) {
                meters = total
            }
            // A run pays by distance, so one without any pays nothing in
            // either mode. Anything else pays by calories and is kept even
            // with none recorded, so the card can say so (spec §28).
            if isRun, meters <= 0 { return nil }
            return RunEntry(
                healthKitWorkoutID: workout.uuid,
                startedAt: workout.startDate.flooredToSecond,
                endedAt: workout.endDate.flooredToSecond,
                distanceMeters: meters,
                importedAt: importedAt,
                sourceName: workout.sourceRevision.source.name,
                activityType: workout.workoutActivityType.rawValue,
                activeEnergyKcal: activeKilocalories(of: workout)
            )
        }
        let newAnchor = try NSKeyedArchiver.archivedData(
            withRootObject: result.newAnchor, requiringSecureCoding: true
        )
        return FetchResult(
            runs: runs,
            deletedWorkoutIDs: result.deletedObjects.map(\.uuid),
            anchor: newAnchor
        )
    }

    // MARK: Background delivery

    /// Ask iOS to wake the app when a workout is saved, so a run can pay the
    /// tab (and notify) without the app being opened. Needs the
    /// `healthkit.background-delivery` entitlement.
    func enableBackgroundDelivery() async throws {
        try await store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }

    /// Runs `onChange` whenever the workouts `mode` reads change, in the
    /// foreground or on a background wake. Must be called at every launch,
    /// including background launches, and again when the mode changes.
    func startObservingWorkouts(for mode: PaymentMode, _ onChange: @escaping @Sendable () async -> Void) {
        stopObservingWorkouts()
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: predicate(for: mode)) { _, completion, _ in
            // HealthKit's completion handler isn't marked Sendable; it is safe
            // to call once from any context, which is all we do.
            let done = CompletionBox(completion)
            Task {
                await onChange()
                done.call()
            }
        }
        store.execute(query)
        observer = query
    }

    func stopObservingWorkouts() {
        if let observer { store.stop(observer) }
        observer = nil
    }

    /// Active energy only: total energy includes resting burn (decisions
    /// §B.10). Nil when the source recorded none or the user didn't share it.
    private func activeKilocalories(of workout: HKWorkout) -> Double? {
        if let kcal = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()), kcal > 0 {
            return kcal
        }
        // A workout typed into Health by hand carries it only here. Despite
        // the name this is active energy, not basal plus active.
        if let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), kcal > 0 {
            return kcal
        }
        return nil
    }
}

private struct CompletionBox: @unchecked Sendable {
    let call: () -> Void
    init(_ call: @escaping () -> Void) { self.call = call }
}
