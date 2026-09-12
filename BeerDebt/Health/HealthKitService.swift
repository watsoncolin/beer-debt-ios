import Foundation
import HealthKit

/// Read-only bridge to HealthKit. Requests the minimum: workouts (filtered to
/// running) and the distance type needed to read a workout's distance
/// (spec §14). Nothing is written to Health.
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
    private var observer: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), distanceType]
    }

    private var runningPredicate: NSPredicate {
        HKQuery.predicateForWorkouts(with: .running)
    }

    /// HealthKit never reveals whether *read* access was granted, only whether
    /// the user has been asked. This is the best available "connected" signal.
    func hasBeenAsked() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        return status == .unnecessary
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Running workouts added or deleted since `anchor` (everything when nil).
    /// Incremental and idempotent: the returned anchor picks up where this
    /// call left off.
    func fetchRunningWorkouts(anchor anchorData: Data?) async throws -> FetchResult {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(runningPredicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        let importedAt = Date.now.flooredToSecond

        let runs = result.addedSamples.compactMap { workout -> RunEntry? in
            // Apps that record a run attach distance samples, which land in the
            // workout's statistics. A workout typed into the Health app by hand
            // carries its distance only as `totalDistance`, so fall back to it.
            var meters = workout.statistics(for: distanceType)?
                .sumQuantity()?
                .doubleValue(for: .meter()) ?? 0
            if meters <= 0, let total = workout.totalDistance?.doubleValue(for: .meter()) {
                meters = total
            }
            guard meters > 0 else { return nil }
            return RunEntry(
                healthKitWorkoutID: workout.uuid,
                startedAt: workout.startDate.flooredToSecond,
                endedAt: workout.endDate.flooredToSecond,
                distanceMeters: meters,
                importedAt: importedAt,
                sourceName: workout.sourceRevision.source.name
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

    /// Runs `onChange` whenever running workouts change, in the foreground or
    /// on a background wake. Must be called at every launch, including
    /// background launches, for delivery to keep working.
    func startObservingWorkouts(_ onChange: @escaping @Sendable () async -> Void) {
        stopObservingWorkouts()
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: runningPredicate) { _, completion, _ in
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
}

private struct CompletionBox: @unchecked Sendable {
    let call: () -> Void
    init(_ call: @escaping () -> Void) { self.call = call }
}
