import SwiftUI

/// Adapts to the phone's shape:
/// - Folded / narrow: mine on top, a tabbed panel underneath (one-handed).
/// - Unfolded / wide: shaft map | mine | upgrades & stats, side by side.
struct ContentView: View {
    @EnvironmentObject var game: GameModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: Panel = .upgrades
    @State private var widePanel: Panel = .upgrades

    enum Panel: String, CaseIterable, Identifiable {
        case upgrades = "Upgrades", shaft = "Shaft", stats = "Stats"
        var id: String { rawValue }
    }

    /// Width at which we switch to the unfolded layout.
    private let wideBreakpoint: CGFloat = 600

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= wideBreakpoint {
                    wideLayout(geo)
                } else {
                    compactLayout(geo)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            game.handleScenePhase(phase)
        }
        .sheet(isPresented: $game.showPrestige) { PrestigeView() }
        .sheet(isPresented: $game.showVictory) { VictoryView() }
        .sheet(item: $game.offlineReport) { report in OfflineView(report: report) }
    }

    private func compactLayout(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            HeaderBar()
            MineView()
                .frame(height: geo.size.height * 0.5)
            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            panelView(panel)
                .frame(maxHeight: .infinity)
        }
    }

    private func wideLayout(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("The Shaft").font(.headline)
                ShaftMapView()
            }
            .frame(width: geo.size.width * 0.22)

            VStack(spacing: 8) {
                HeaderBar()
                MineView()
            }

            VStack(spacing: 8) {
                Picker("Panel", selection: $widePanel) {
                    Text(Panel.upgrades.rawValue).tag(Panel.upgrades)
                    Text(Panel.stats.rawValue).tag(Panel.stats)
                }
                .pickerStyle(.segmented)
                panelView(widePanel)
            }
            .frame(width: geo.size.width * 0.32)
        }
    }

    @ViewBuilder
    private func panelView(_ p: Panel) -> some View {
        switch p {
        case .upgrades: UpgradesView()
        case .shaft: ShaftMapView()
        case .stats: StatsView()
        }
    }
}
