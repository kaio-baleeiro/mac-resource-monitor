import SwiftUI

@main
struct MacResourceMonitorApp: App {
    @StateObject private var model = MonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MonitorView(model: model)
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .accessibilityLabel("Recursos do Mac")
                .help("Mostrar recursos do Mac")
        }
        .menuBarExtraStyle(.window)
    }
}
