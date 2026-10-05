import HealthKit

/// What a workout on the books was, for its card (spec §28: "Workout cards
/// show the activity's own SF Symbol and name"). The ledger stores the raw
/// `HKWorkoutActivityType`; only the app turns it into words, so the models
/// and the widget stay free of HealthKit.
struct WorkoutKind: Equatable {
    let name: String
    let symbol: String

    init(_ workout: RunEntry) {
        guard let raw = workout.activityType, !workout.isRunning,
              let type = HKWorkoutActivityType(rawValue: raw) else {
            self.init(name: "Run", symbol: "figure.run")
            return
        }
        switch type {
        case .cycling: self.init(name: "Ride", symbol: "figure.outdoor.cycle")
        case .walking: self.init(name: "Walk", symbol: "figure.walk")
        case .hiking: self.init(name: "Hike", symbol: "figure.hiking")
        case .swimming: self.init(name: "Swim", symbol: "figure.pool.swim")
        case .rowing: self.init(name: "Row", symbol: "figure.rower")
        case .elliptical: self.init(name: "Elliptical", symbol: "figure.elliptical")
        case .stairClimbing, .stairs: self.init(name: "Stairs", symbol: "figure.stair.stepper")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            self.init(name: "Strength", symbol: "figure.strengthtraining.traditional")
        case .highIntensityIntervalTraining: self.init(name: "HIIT", symbol: "figure.highintensity.intervaltraining")
        case .yoga: self.init(name: "Yoga", symbol: "figure.yoga")
        case .crossTraining: self.init(name: "Cross training", symbol: "figure.cross.training")
        case .mixedCardio: self.init(name: "Cardio", symbol: "figure.mixed.cardio")
        case .dance, .cardioDance, .socialDance: self.init(name: "Dance", symbol: "figure.dance")
        case .tennis: self.init(name: "Tennis", symbol: "figure.tennis")
        case .soccer: self.init(name: "Soccer", symbol: "figure.soccer")
        case .basketball: self.init(name: "Basketball", symbol: "figure.basketball")
        case .downhillSkiing, .crossCountrySkiing: self.init(name: "Ski", symbol: "figure.skiing.downhill")
        case .snowboarding: self.init(name: "Snowboard", symbol: "figure.snowboarding")
        case .climbing: self.init(name: "Climb", symbol: "figure.climbing")
        case .pilates: self.init(name: "Pilates", symbol: "figure.pilates")
        case .coreTraining: self.init(name: "Core", symbol: "figure.core.training")
        case .wheelchairRunPace, .wheelchairWalkPace: self.init(name: "Push", symbol: "figure.roll")
        default: self.init(name: "Workout", symbol: "figure.mixed.cardio")
        }
    }

    private init(name: String, symbol: String) {
        self.name = name
        self.symbol = symbol
    }
}
