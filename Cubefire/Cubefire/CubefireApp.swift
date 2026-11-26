import SwiftUI

@main
struct CubefireApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        WindowGroup {
            MenuRoot()
                .environmentObject(store)
        }
    }
}
