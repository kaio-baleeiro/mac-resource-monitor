import AppKit
import SwiftUI

@main
struct MacResourceMonitorApp: App {
    @StateObject private var model = MonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MonitorView(model: model)
        } label: {
            menuBarIcon
                .accessibilityLabel("Recursos do Mac")
                .help("Mostrar recursos do Mac")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: Image {
        guard let url = Bundle.main.url(forResource: "MacResourceMonitorIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return Image(systemName: "gauge.with.dots.needle.67percent")
        }

        image.size = NSSize(width: 18, height: 18)
        return Image(nsImage: image)
            .renderingMode(.original)
    }
}
