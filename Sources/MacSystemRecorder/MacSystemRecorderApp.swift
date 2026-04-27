import SwiftUI

@main
struct MacSystemRecorderApp: App {
    @StateObject private var recorder = RecorderModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .frame(minWidth: 680, minHeight: 560)
        }
        .windowStyle(.titleBar)
    }
}
