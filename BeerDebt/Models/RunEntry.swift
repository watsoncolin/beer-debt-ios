import Foundation

/// One workout imported from HealthKit. Immutable event. Named for the runs it
/// held before calorie mode (spec §28); every other workout type is only
/// imported, and only pays, in that mode.
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
    /// `HKWorkoutActivityType` raw value. Nil means running: every entry
    /// written before calorie mode was a run.
    let activityType: UInt?
    /// Active energy burned, in kilocalories. Nil when none was recorded or
    /// when the entry predates calorie mode.
    let activeEnergyKcal: Double?

    static let metersPerMile = 1609.344
    /// `HKWorkoutActivityType.running.rawValue`. Spelled out so the models
    /// stay free of HealthKit (the widget and the fixtures compile them).
    static let runningActivityType: UInt = 37

    init(
        id: UUID = UUID(),
        healthKitWorkoutID: UUID,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        importedAt: Date,
        sourceName: String? = nil,
        activityType: UInt? = nil,
        activeEnergyKcal: Double? = nil
    ) {
        self.id = id
        self.healthKitWorkoutID = healthKitWorkoutID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.importedAt = importedAt
        self.sourceName = sourceName
        self.activityType = activityType
        self.activeEnergyKcal = activeEnergyKcal
    }

    var distanceMiles: Double { distanceMeters / Self.metersPerMile }

    var isRunning: Bool { activityType == nil || activityType == Self.runningActivityType }
}
