import SwiftUI

/// The Ledger (spec §12): chronological beers and runs, grouped by day.
/// Concept art splits this into "Your Debt" (active / paid) and "Runs"; one
/// screen with a segment control covers both — see docs/decisions.md #2.
struct LedgerView: View {
    var body: some View {
        List {
            Section("Today") {
                Text("Nothing on the books yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("The Ledger")
    }
}

#Preview {
    NavigationStack { LedgerView() }
}
