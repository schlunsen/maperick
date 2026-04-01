import SwiftUI
import SceneKit

@main
struct MaperickApp: App {
    @State private var state = ConnectionState()

    var body: some Scene {
        // Menu bar item
        MenuBarExtra("Maperick", systemImage: "globe") {
            MenuBarPopoverView(state: state)
        }
        .menuBarExtraStyle(.window)

        // Full globe window (hidden by default, opened from menu bar)
        Window("Maperick — Globe", id: "globe-window") {
            GlobeWindowView(state: state)
                .frame(minWidth: 700, minHeight: 550)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 850)
        .defaultPosition(.topTrailing)
    }
}
