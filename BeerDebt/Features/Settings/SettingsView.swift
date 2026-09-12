import SwiftUI

/// Tune the rules (spec §13). Read-only placeholder showing the defaults; the
/// real view binds to LedgerStore.rules.
struct SettingsView: View {
    private let rules = Rules.default

    var body: some View {
        Form {
            Section {
                LabeledContent("Miles per Beer", value: rules.milesPerBeer.formatted() + " mi")
                LabeledContent("Interest Rate", value: rules.interest.rate.formatted(.percent))
                LabeledContent("Interest Frequency", value: rules.interest.period.rawValue.capitalized)
                LabeledContent("Grace Period", value: "\(Int(rules.interest.gracePeriod / 3600)) hours")
                LabeledContent("Maximum Credit", value: "\(rules.maximumCreditBeers.formatted()) beers")
                LabeledContent("Credit Decay", value: rules.creditDecayRatePerWeek.formatted(.percent) + " / week")
            } header: {
                Text("The Rules")
            }

            Section {
                LabeledContent("Apple Health", value: "Not connected")
            } header: {
                Text("Health & Data")
            } footer: {
                Text("Only running workouts count toward your balance.")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
