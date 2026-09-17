import SwiftUI

@main
struct ImageInspectorApp: App {
    @StateObject private var store = HeaderFooterStore()

    var body: some Scene {
        WindowGroup("Image Inspector") {
            ContentView()
                .environmentObject(store)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
    }
}
