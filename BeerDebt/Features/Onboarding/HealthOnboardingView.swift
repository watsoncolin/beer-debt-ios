import SwiftUI

/// Minimal first-run flow (spec §20): explain the one permission, ask for it,
/// handle denial gracefully (the app still works — beers just never get paid).
struct HealthOnboardingView: View {
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.run")
                .font(.system(size: 64))
                .foregroundStyle(Theme.credit)
            Text("Runs pay your tab.")
                .font(.title.weight(.heavy))
            Text("Beer Debt reads your running workouts from Apple Health. Only running counts — walking the dog doesn't pay for beer.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Connect Apple Health") {
                // TODO: HealthKitService.requestAuthorization()
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(24)
    }
}

#Preview {
    HealthOnboardingView()
}
