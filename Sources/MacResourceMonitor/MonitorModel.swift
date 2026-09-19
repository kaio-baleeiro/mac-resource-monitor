import Foundation
import Combine

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot: ResourceSnapshot?

    private let reader = MetricsReader()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func refresh() {
        snapshot = reader.read()
    }
}
