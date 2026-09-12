import SwiftUI

/// Brand palette (spec §18): personal-finance seriousness for an unserious
/// liability. Beer gold, deep forest green, cream. Values sampled from the
/// concept art (docs/concept.png).
enum Theme {
    static let gold = Color(red: 0.961, green: 0.729, blue: 0.259)
    static let forest = Color(red: 0.118, green: 0.180, blue: 0.165)
    static let forestDeep = Color(red: 0.078, green: 0.125, blue: 0.114)
    static let cream = Color(red: 0.965, green: 0.941, blue: 0.894)
    static let ink = Color(red: 0.110, green: 0.110, blue: 0.100)
    /// "mi owed" — warm red, never alarming.
    static let debt = Color(red: 0.871, green: 0.333, blue: 0.239)
    /// "banked" / "paid" — the running green.
    static let credit = Color(red: 0.361, green: 0.722, blue: 0.471)
}
