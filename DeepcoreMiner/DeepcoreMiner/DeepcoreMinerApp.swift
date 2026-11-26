import SwiftUI

@main
struct DeepcoreMinerApp: App {
    @StateObject private var game = GameModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
        }
    }
}
