import AppKit
import SwiftUI

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let snapshot = model.snapshot {
                if showingDetails {
                    DetailsView(snapshot: snapshot)
                } else {
                    metricsGrid(snapshot)
                }
            } else {
                ProgressView("Lendo recursos...")
                    .frame(maxWidth: .infinity, minHeight: 190)
            }
            Divider()
            footer
        }
        .padding(18)
        // Keep the horizontal footprint stable so macOS does not move the
        // menu-bar popover to the opposite side when details are opened.
        .frame(width: 360, height: showingDetails ? 660 : 330, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
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
                Label(showingDetails ? "Resumo" : "Detalhes", systemImage: showingDetails ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title2)
                .foregroundStyle(.tint)
        }
    }

    private func metricsGrid(_ snapshot: ResourceSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricCard(title: "CPU", value: percent(snapshot.cpuUsage), detail: "uso total", progress: snapshot.cpuUsage, color: .blue)
            MetricCard(title: "RAM", value: percent(snapshot.memoryUsage), detail: "\(formatBytes(snapshot.memoryUsed)) de \(formatBytes(snapshot.memoryTotal))", progress: snapshot.memoryUsage, color: .purple)
            MetricCard(title: "GPU", value: percent(snapshot.gpuUsage), detail: snapshot.gpuName ?? "uso gráfico", progress: snapshot.gpuUsage, color: .orange)
            MetricCard(title: "Disco principal", value: percent(snapshot.diskUsage), detail: "\(formatBytes(snapshot.diskUsed)) de \(formatBytes(snapshot.diskTotal))", progress: snapshot.diskUsage, color: .green)
        }
    }

    private var footer: some View {
        HStack {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text("Atualização automática a cada segundo")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button(showingDetails ? "Voltar ao resumo" : "Ver detalhes") {
                showingDetails.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "N/D" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct DetailsView: View {
    let snapshot: ResourceSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    DetailSummary(title: "Rede recebida", value: formatRate(snapshot.networkDownloadRate), color: .blue)
                    DetailSummary(title: "Rede enviada", value: formatRate(snapshot.networkUploadRate), color: .indigo)
                    DetailSummary(title: "Processos lidos", value: "\(snapshot.processes.count)", color: .secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProcessListCard(title: "Mais CPU", icon: "cpu", processes: snapshot.processes.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(6).map { $0 }, value: { String(format: "%.1f%%", $0.cpuUsage) }, detail: { "PID \($0.pid)" }, color: .blue)
                    ProcessListCard(title: "Mais RAM", icon: "memorychip", processes: snapshot.processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(6).map { $0 }, value: { formatBytes($0.memoryBytes) }, detail: { "PID \($0.pid)" }, color: .purple)
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
                        text: "O espaço total está disponível no resumo. A atividade de leitura e escrita por processo exige uma coleta privilegiada no macOS.",
                        color: .green
                    )
                }
            }
        }
        .frame(height: 520)
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(color)
            }
            ProgressView(value: progress ?? 0)
                .tint(color)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}
