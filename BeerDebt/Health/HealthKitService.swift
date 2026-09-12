import Foundation
import HealthKit

/// Read-only bridge to HealthKit. Requests the minimum: workouts (filtered to
/// running) and the distance type needed to read a workout's distance
/// (spec §14). Nothing is written to Health.
@MainActor
final class HealthKitService {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Fetches running workouts not yet seen, using a persisted query anchor so
    /// sync on app-active is incremental and idempotent.
    func fetchNewRunningWorkouts() async throws -> [RunEntry] {
        // TODO: HKAnchoredObjectQuery on workoutType(), predicate
        //   HKQuery.predicateForWorkouts(with: .running), persist the anchor,
        //   distance from workout.statistics(for: distanceWalkingRunning)?.sumQuantity()
        //   (fall back to totalDistance), map to RunEntry keyed by workout.uuid.
        return []
    }
}
