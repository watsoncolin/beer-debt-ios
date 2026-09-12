import Foundation

/// One beer. Immutable except for its place on the timeline: a beer you forgot
/// to log can be dated back later (up to 30 days, and it may predate the
/// books, unlike a run).
///
/// Deliberately minimal: what the beer cost, whether credit covered it, and how
/// much interest it has accrued are all derived during replay from the rules in
/// force at `createdAt` (spec §5, §16, §17).
struct BeerEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// When the beer happened. This is its position on the ledger timeline.
    var createdAt: Date
    /// When the entry was recorded. Nil only for entries written before this
    /// field existed.
    let recordedAt: Date?

    init(id: UUID = UUID(), createdAt: Date, recordedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.recordedAt = recordedAt
    }

    /// Logged at one time, dated to another.
    var isBackdated: Bool {
        guard let recordedAt else { return false }
        return recordedAt != createdAt
    }
}
