import SwiftUI

/// Single NavigationStack rooted at Home. Ledger and Settings are pushed;
/// beer feedback and transaction detail are sheets (spec §20 — no tab bar).
struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView()
        }
        .tint(Theme.gold)
    }
}

#Preview {
    RootView()
}
