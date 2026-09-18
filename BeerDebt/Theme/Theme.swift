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
    /// "mi owed": warm red, never alarming.
    static let debt = Color(red: 0.937, green: 0.424, blue: 0.318)
    /// "banked" / "paid": the running green.
    static let credit = Color(red: 0.361, green: 0.722, blue: 0.471)
    /// Pale green for chart bars, like the concept art.
    static let creditSoft = Color(red: 0.612, green: 0.847, blue: 0.663)
    /// A beer that grew: amber for the ones that cost more running than they
    /// should have, `debt` for the ones that really got away. Deliberately not
    /// `gold`, which in this app means earned.
    static let caution = Color(red: 0.949, green: 0.600, blue: 0.263)
    /// A streak freeze: cool against the flame's warmth, so a rest day reads as
    /// a different kind of thing from a run (spec §25.1). Light enough to stay
    /// legible on forest and on the Home backdrop.
    static let frost = Color(red: 0.639, green: 0.831, blue: 0.909)
    /// Raised card on the forest background.
    static let card = Color(red: 0.165, green: 0.235, blue: 0.216)
    static let cardStroke = Color(red: 0.235, green: 0.318, blue: 0.290)

    /// One-time UIKit appearance so segmented controls match the art:
    /// dark track, cream selected pill.
    @MainActor
    static func applyAppearance() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(cream)
        segmented.backgroundColor = UIColor(forestDeep)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(ink)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(cream.opacity(0.85))], for: .normal)
    }
}

/// Every secondary screen: forest background under a List/Form, dark bars.
struct ForestScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(colors: [Theme.forest, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// A List row drawn as a floating card.
struct CardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 16, leading: 36, bottom: 16, trailing: 36))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 20)
            )
    }
}

extension View {
    func forestScreen() -> some View { modifier(ForestScreen()) }
    func cardRow() -> some View { modifier(CardRow()) }
}

/// Dark forest background for Home and the sheets: the painted trail-and-
/// mountains scene (`HomeBackdrop`, docs/art) under a scrim that keeps cream
/// text legible over the sunset band and darkens the bottom for the controls.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.forest, Theme.forestDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(.clear)
                .overlay {
                    Image("HomeBackdrop")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
            LinearGradient(
                stops: [
                    .init(color: Theme.forestDeep.opacity(0.55), location: 0),
                    .init(color: Theme.forestDeep.opacity(0.30), location: 0.30),
                    .init(color: Theme.forestDeep.opacity(0.45), location: 0.55),
                    .init(color: Theme.forestDeep.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// The big gold capsule: + Beer, Cheers!, Connect.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.gold, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Small rounded status tag: PAID, Applied, Ignored.
struct Pill: View {
    let text: String
    var color: Color = Theme.credit

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
