import SwiftUI

@main
struct BeatsPlayerApp: App {
    @StateObject private var player = Player()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
