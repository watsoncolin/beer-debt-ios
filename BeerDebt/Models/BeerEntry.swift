import Foundation

/// One beer, recorded at the moment it was consumed. Immutable event.
///
/// Deliberately minimal: what the beer cost, whether credit covered it, and how
/// much interest it has accrued are all derived during replay from the rules in
/// force at `createdAt` (spec §5, §16, §17).
struct BeerEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date

    init(id: UUID = UUID(), createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}
