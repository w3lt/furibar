import SwiftUI
import FuribarApp

@main
struct Furibar: App {
    @State private var manager: ConnectionManager

    init() {
        let manager = ConnectionManager(preferences: Preferences())
        manager.start()
        _manager = State(initialValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(manager)
        } label: {
            MenuBarLabel(manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}
