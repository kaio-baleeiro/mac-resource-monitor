import AppKit
import SwiftUI
import MacResourceMonitorCore

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    @State private var showingDetails = false
    @State private var selectedProcess: ProcessUsage?

    private let popoverWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = model.snapshot {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        if showingDetails {
                            detailsSummaryStrip(snapshot)
                        } else {
                            metricsGrid(snapshot)
                        }

                        if showingDetails {
                            Divider()
                            DetailsView(snapshot: snapshot, selectedProcess: $selectedProcess)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: showingDetails ? 520 : 260)
            } else {
                ProgressView("Lendo recursos do Mac…")
                    .frame(maxWidth: .infinity, minHeight: 190)
                    .accessibilityIdentifier("monitor.loading")
            }

            if showingDetails {
                Divider()
                footer
            }
        }
        .padding(18)
        // Keep the horizontal footprint stable so macOS preserves the
        // menu-bar popover anchor when details are opened.
        .frame(
            width: popoverWidth,
            height: showingDetails ? 620 : 320,
            alignment: .topLeading
        )
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear { model.setUIVisible(true) }
        .onDisappear { model.setUIVisible(false) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recursos do Mac")
                    .font(.headline)
                Text(showingDetails ? "Visão detalhada da máquina" : "Visão rápida da máquina")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingDetails.toggle()
            } label: {
                Label(
                    showingDetails ? "Resumo" : "Detalhes",
                    systemImage: showingDetails ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("monitor.summary.toggle")

            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }

    private func metricsGrid(_ snapshot: ResourceSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricCard(
                title: "CPU",
                value: percent(snapshot.cpuUsage),
                detail: "uso total",
                progress: snapshot.cpuUsage,
                status: snapshot.cpuStatus,
                color: .blue,
                warningThreshold: 0.9
            )
            MetricCard(
                title: "RAM",
                value: percent(snapshot.memoryUsage, status: snapshot.memoryStatus),
                detail: snapshot.memoryStatus == .available
                    ? "uso estimado · \(formatBytes(snapshot.memoryUsed)) de \(formatBytes(snapshot.memoryTotal))"
                    : statusText(snapshot.memoryStatus),
                progress: snapshot.memoryStatus == .available ? snapshot.memoryUsage : nil,
                status: snapshot.memoryStatus,
                color: .purple,
                warningThreshold: 0.9
            )
            MetricCard(
                title: "GPU",
                value: percent(snapshot.gpuUsage, status: snapshot.gpuStatus),
                detail: snapshot.gpuName ?? statusText(snapshot.gpuStatus),
                progress: snapshot.gpuStatus == .available ? snapshot.gpuUsage : nil,
                status: snapshot.gpuStatus,
                color: .orange,
                warningThreshold: 0.9
            )
            MetricCard(
                title: "Armazenamento",
                value: percent(snapshot.diskUsage, status: snapshot.diskStatus),
                detail: snapshot.diskStatus == .available
                    ? "ocupado · \(formatBytes(snapshot.diskUsed)) de \(formatBytes(snapshot.diskTotal))"
                    : statusText(snapshot.diskStatus),
                progress: snapshot.diskStatus == .available ? snapshot.diskUsage : nil,
                status: snapshot.diskStatus,
                color: .green,
                warningThreshold: 0.85
            )
        }
    }

    private func detailsSummaryStrip(_ snapshot: ResourceSnapshot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            SummaryMetric(
                title: "CPU",
                value: percent(snapshot.cpuUsage, status: snapshot.cpuStatus),
                color: .blue
            )
            SummaryMetric(
                title: "RAM",
                value: percent(snapshot.memoryUsage, status: snapshot.memoryStatus),
                color: .purple
            )
            SummaryMetric(
                title: "GPU",
                value: percent(snapshot.gpuUsage, status: snapshot.gpuStatus),
                color: .orange
            )
            SummaryMetric(
                title: "Disco",
                value: percent(snapshot.diskUsage, status: snapshot.diskStatus),
                color: .green
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitor.details.summary")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(collectionColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(model.collectionState.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .accessibilityIdentifier("monitor.quit")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estado da coleta: \(model.collectionState.label)")
    }

    private var collectionColor: Color {
        switch model.collectionState {
        case .updated: return .green
        case .loading, .stale: return .orange
        case .failed: return .red
        case .paused: return .secondary
        }
    }

    private func percent(_ value: Double?, status: MetricStatus = .available) -> String {
        guard status == .available, let value else { return "N/D" }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "N/D"
    }

    private func statusText(_ status: MetricStatus) -> String {
        switch status {
        case .available: return "Disponível"
        case .warmingUp: return "Aguardando amostra"
        case .unavailable: return "Indisponível"
        case .failed: return "Falha na leitura"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailsView: View {
    let snapshot: ResourceSnapshot
    @Binding var selectedProcess: ProcessUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DetailSummary(title: "Rede recebida", value: formatRate(snapshot.networkDownloadRate), color: .blue)
                DetailSummary(title: "Rede enviada", value: formatRate(snapshot.networkUploadRate), color: .indigo)
                DetailSummary(
                    title: "Processos visíveis",
                    value: snapshot.processStatus == .available ? "\(snapshot.processes.count)" : "N/D",
                    color: .secondary
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                ProcessListCard(
                    title: "Mais CPU",
                    icon: "cpu",
                    processes: topCPU,
                    value: { formatPercent($0.cpuUsage, fractionDigits: 1) },
                    detail: { "PID \($0.pid)" },
                    color: .blue,
                    onSelect: { selectedProcess = $0 }
                )
                ProcessListCard(
                    title: "Mais RAM",
                    icon: "memorychip",
                    processes: topMemory,
                    value: { formatBytes($0.memoryBytes) },
                    detail: { "PID \($0.pid)" },
                    color: .purple,
                    onSelect: { selectedProcess = $0 }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                LimitationCard(
                    title: "GPU por processo",
                    icon: "rectangle.3.group",
                    text: "O macOS fornece a utilização total da GPU, mas não expõe de forma confiável a divisão por processo para este app.",
                    color: .orange
                )
                LimitationCard(
                    title: "Disco por processo",
                    icon: "internaldrive",
                    text: "O armazenamento total está disponível no resumo. A atividade de leitura e escrita por processo não é coletada.",
                    color: .green
                )
            }
        }
        .popover(item: $selectedProcess) { process in
            ProcessDetailView(process: process)
        }
    }

    private var topCPU: [ProcessUsage] {
        snapshot.processes.sorted { lhs, rhs in
            lhs.cpuUsage == rhs.cpuUsage ? lhs.pid < rhs.pid : lhs.cpuUsage > rhs.cpuUsage
        }.prefix(6).map { $0 }
    }

    private var topMemory: [ProcessUsage] {
        snapshot.processes.sorted { lhs, rhs in
            lhs.memoryBytes == rhs.memoryBytes ? lhs.pid < rhs.pid : lhs.memoryBytes > rhs.memoryBytes
        }.prefix(6).map { $0 }
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}

private struct LimitationCard: View {
    let title: String
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailSummary: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProcessListCard: View {
    let title: String
    let icon: String
    let processes: [ProcessUsage]
    let value: (ProcessUsage) -> String
    let detail: (ProcessUsage) -> String
    let color: Color
    let onSelect: (ProcessUsage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)

            if processes.isEmpty {
                Text("Nenhum processo disponível")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    Button {
                        onSelect(process)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(process.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(detail(process))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Text(value(process))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(color)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(process.name), \(detail(process)), \(value(process))")
                    .accessibilityHint("Clique para ver os detalhes do processo")
                    .accessibilityIdentifier("monitor.process.\(process.pid)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double?
    let status: MetricStatus
    let color: Color
    let warningThreshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(valueColor)
            }

            if let progress {
                ProgressView(value: progress)
                    .tint(valueColor)
            } else {
                Text(statusLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(valueColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(detail), \(statusLabel)")
        .accessibilityIdentifier("monitor.metric.\(title.lowercased())")
    }

    private var statusLabel: String {
        switch status {
        case .available:
            guard let progress, progress >= warningThreshold else { return "Normal" }
            return "Atenção"
        case .warmingUp: return "Aguardando amostra"
        case .unavailable: return "Indisponível"
        case .failed: return "Falha na leitura"
        }
    }

    private var valueColor: Color {
        switch status {
        case .failed: return .red
        case .unavailable, .warmingUp: return .secondary
        case .available: return color
        }
    }
}

private struct ProcessDetailView: View {
    let process: ProcessUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(process.name)
                .font(.headline)
                .lineLimit(2)

            LabeledContent("PID", value: "\(process.pid)")
            LabeledContent("CPU", value: formatPercent(process.cpuUsage, fractionDigits: 1))
            LabeledContent("Memória", value: formatBytes(process.memoryBytes))

            Divider()

            HStack {
                Button("Copiar PID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(process.pid)", forType: .string)
                }
                Button("Monitor de Atividade") {
                    let path = "/System/Applications/Utilities/Activity Monitor.app"
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

private func formatPercent(_ value: Double, fractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = fractionDigits
    formatter.minimumFractionDigits = fractionDigits
    return formatter.string(from: NSNumber(value: value / 100)) ?? "N/D"
}

private func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
