import SwiftUI

@main
struct ImageInspectorApp: App {
    var body: some Scene {
        WindowGroup("Image Inspector") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
    }
}
