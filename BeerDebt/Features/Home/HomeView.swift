import SwiftUI

/// The product (spec §10). The balance dominates; one big + Beer button; one
/// line of running context; one line of copy. Nothing else.
struct HomeView: View {
    var body: some View {
        ZStack {
            Theme.forest.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Beer Debt")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.cream)
                    Text("Drink now. Run later.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                }

                Spacer()

                // Placeholder: the "even" state. The real view switches on
                // Balance.state (credit / even / debt).
                VStack(spacing: 8) {
                    Text("0")
                        .font(.system(size: 104, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.cream)
                    Text("BOOKS ARE CLEAN")
                        .font(.headline.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(Theme.gold)
                }

                Spacer()

                Button {
                    // TODO: LedgerStore.addBeer() + feedback sheet (spec §11)
                } label: {
                    Label("+ Beer", systemImage: "mug.fill")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.gold)
                .foregroundStyle(Theme.ink)

                NavigationLink {
                    LedgerView()
                } label: {
                    HStack {
                        Image(systemName: "figure.run")
                        Text("0.0 mi run this week")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .padding()
                    .background(Theme.forestDeep, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { HomeView() }
}
