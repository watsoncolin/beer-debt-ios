import Foundation

/// One running workout imported from HealthKit. Immutable event.
///
/// `healthKitWorkoutID` is the dedup key: importing the same workout twice must
/// be a no-op (spec §14, acceptance criterion 15). Distance is stored in meters
/// (HealthKit's native unit; also Health Connect's on Android) and converted to
/// miles at the engine boundary.
struct RunEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let healthKitWorkoutID: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let importedAt: Date
    /// e.g. "Apple Watch", "Strava". Display only.
    let sourceName: String?

    static let metersPerMile = 1609.344

    init(
        id: UUID = UUID(),
        healthKitWorkoutID: UUID,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        importedAt: Date,
        sourceName: String? = nil
    ) {
        self.id = id
        self.healthKitWorkoutID = healthKitWorkoutID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.importedAt = importedAt
        self.sourceName = sourceName
    }

    var distanceMiles: Double { distanceMeters / Self.metersPerMile }
}
