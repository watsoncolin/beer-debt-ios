import SwiftUI

/// Minimal first-run flow (spec §20): explain the one permission, ask for it,
/// and handle "not now" gracefully. The app still works without Health; the
/// beers just never get paid.
struct HealthOnboardingView: View {
    @Environment(HealthSync.self) private var sync
    @State private var connecting = false
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 20) {
                Spacer()

                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                Text("Beer Debt")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.cream)
                Text("Drink now. Run later.")
                    .font(.title3)
                    .foregroundStyle(Theme.cream.opacity(0.7))

                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    rule("mug.fill", "Every beer costs a mile.", "Tap + Beer and it goes on your tab.")
                    rule("figure.run", "Runs pay the tab.", "Apple Health hands over your runs. Only running counts. We'll ping you when one lands.")
                    rule("percent", "Ignore it and it grows.", "Interest starts after 24 hours. The rules are yours to tune.")
                }
                .padding(20)
                .background(Theme.forestDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))

                Spacer()

                Button {
                    connecting = true
                    Task {
                        await sync.connect()
                        if sync.isConnected {
                            await sync.enableRunNotifications()
                        }
                        connecting = false
                        onDone()
                    }
                } label: {
                    Text(connecting ? "Connecting…" : "Connect Apple Health")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(connecting)

                Button("Not now") { onDone() }
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .padding(.bottom, 8)
            }
            .padding(24)
        }
    }

    private func rule(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
