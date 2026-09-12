import Foundation
import HealthKit

/// Read-only bridge to HealthKit. Requests the minimum: workouts (filtered to
/// running) and the distance type needed to read a workout's distance
/// (spec §14). Nothing is written to Health.
@MainActor
final class HealthKitService {
    struct FetchResult: Sendable {
        let runs: [RunEntry]
        /// Opaque `HKQueryAnchor`, archived. Persist and pass back next time.
        let anchor: Data
    }

    private let store = HKHealthStore()
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), distanceType]
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

    /// Running workouts added since `anchor` (all of them when nil). Incremental
    /// and idempotent: the returned anchor picks up where this call left off.
    func fetchRunningWorkouts(anchor anchorData: Data?) async throws -> FetchResult {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForWorkouts(with: .running))],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        let importedAt = Date.now.flooredToSecond

        let runs = result.addedSamples.compactMap { workout -> RunEntry? in
            let meters = workout.statistics(for: distanceType)?
                .sumQuantity()?
                .doubleValue(for: .meter()) ?? 0
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
        return FetchResult(runs: runs, anchor: newAnchor)
    }
}
