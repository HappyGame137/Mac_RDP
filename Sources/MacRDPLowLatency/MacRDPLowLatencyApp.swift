import SwiftUI

@main
struct MacRDPLowLatencyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 940, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
