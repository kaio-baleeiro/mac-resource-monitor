import Foundation
import Combine
import MacResourceMonitorCore

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot: ResourceSnapshot?
    @Published private(set) var collectionState: CollectionState = .paused

    private let reader: MetricsReader
    private var collectionTask: Task<Void, Never>?

    init(reader: MetricsReader = MetricsReader()) {
        self.reader = reader
    }

    func setUIVisible(_ visible: Bool) {
        if visible {
            startCollectionIfNeeded()
        } else {
            stopCollection()
        }
    }

    func retry() {
        guard collectionTask == nil else { return }
        startCollectionIfNeeded()
    }

    private func startCollectionIfNeeded() {
        guard collectionTask == nil else { return }
        reader.resetBaselines()
        collectionState = .loading

        collectionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.collectOnce()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private func stopCollection() {
        collectionTask?.cancel()
        collectionTask = nil
        collectionState = .paused
        reader.resetBaselines()
    }

    private func collectOnce() async {
        let nextSnapshot = await reader.readAsync()
        guard !Task.isCancelled else { return }

        snapshot = nextSnapshot
        let statuses = [
            nextSnapshot.cpuStatus,
            nextSnapshot.memoryStatus,
            nextSnapshot.diskStatus,
            nextSnapshot.gpuStatus,
            nextSnapshot.networkStatus,
            nextSnapshot.processStatus
        ]
        if statuses.contains(.failed) {
            collectionState = .stale
        } else if statuses.contains(.warmingUp) {
            collectionState = .loading
        } else {
            collectionState = .updated
        }
    }

    deinit {
        collectionTask?.cancel()
    }
}

enum CollectionState: Equatable {
    case paused
    case loading
    case updated
    case stale
    case failed

    var label: String {
        switch self {
        case .paused: return "Monitor pausado"
        case .loading: return "Lendo recursos…"
        case .updated: return "Atualizado agora"
        case .stale: return "Dados desatualizados"
        case .failed: return "Falha na leitura"
        }
    }
}
