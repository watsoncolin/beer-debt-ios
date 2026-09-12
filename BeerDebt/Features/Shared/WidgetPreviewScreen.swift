import SwiftUI
import WidgetKit

/// DEBUG-only: renders the widget faces at Home Screen sizes so they can be
/// screenshotted from the simulator (`-debugScreen widgets`). Not linked to
/// the real widget timeline; it replays the app's ledger directly.
struct WidgetPreviewScreen: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        let entry = BalanceEntry(date: .now, report: store.report())
        ScrollView {
            VStack(spacing: 24) {
                widgetFrame(width: 170, height: 170) {
                    BalanceWidgetView(entry: entry, familyOverride: .systemSmall)
                }
                widgetFrame(width: 364, height: 170) {
                    BalanceWidgetView(entry: entry, familyOverride: .systemMedium)
                }
                VStack(alignment: .leading, spacing: 8) {
                    BalanceWidgetView(entry: entry, familyOverride: .accessoryRectangular)
                        .frame(width: 172, height: 72)
                        .padding(8)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    BalanceWidgetView(entry: entry, familyOverride: .accessoryInline)
                        .padding(8)
                        .background(Color.black.opacity(0.8), in: Capsule())
                }
                .foregroundStyle(.white)
            }
            .padding(24)
        }
        .forestScreen()
        .navigationTitle("Widgets")
    }

    private func widgetFrame<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(
                LinearGradient(colors: [Theme.forest, Theme.forestDeep], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
    }
}
