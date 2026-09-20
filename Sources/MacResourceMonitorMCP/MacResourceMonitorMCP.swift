import Foundation
import MacResourceMonitorCore

@main
struct MacResourceMonitorMCP {
    static func main() {
        MCPServer().run()
    }
}

private final class MCPServer {
    private let reader = MetricsReader()
    private let dateFormatter = ISO8601DateFormatter()

    init() {
        // CPU utilization is calculated from two samples. Warm up the reader
        // so the first request from an agent returns a useful value.
        _ = reader.read()
        Thread.sleep(forTimeInterval: 0.15)
        _ = reader.read()
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            handle(line: line)
        }
    }

    private func handle(line: String) {
        do {
            guard let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                throw MCPError.invalidRequest
            }

            let method = request["method"] as? String ?? ""
            let id = request["id"] ?? NSNull()

            if method.hasPrefix("notifications/") {
                return
            }

            switch method {
            case "initialize":
                sendResult(id: id, result: initializeResult)
            case "ping":
                sendResult(id: id, result: [:])
            case "tools/list":
                sendResult(id: id, result: ["tools": toolDefinitions])
            case "tools/call":
                let params = request["params"] as? [String: Any] ?? [:]
                sendToolResult(id: id, params: params)
            default:
                sendError(id: id, code: -32601, message: "Método não suportado: \(method)")
            }
        } catch {
            sendError(id: NSNull(), code: -32600, message: "Requisição inválida")
        }
    }

    private var initializeResult: [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": [
                "name": "mac-resource-monitor",
                "version": "0.1.0"
            ],
            "instructions": "Use estas ferramentas para consultar o consumo atual de recursos deste Mac local. Os dados não saem da máquina."
        ]
    }

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "get_system_resources",
                "description": "Retorna o consumo atual de CPU, memória, GPU, disco principal e rede deste Mac.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "get_top_processes",
                "description": "Lista os processos que mais consomem CPU ou memória neste Mac.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "resource": [
                            "type": "string",
                            "enum": ["cpu", "memory"],
                            "description": "Recurso usado para ordenar a lista. Padrão: cpu."
                        ],
                        "limit": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 20,
                            "description": "Quantidade máxima de processos. Padrão: 5."
                        ]
                    ],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private func sendToolResult(id: Any, params: [String: Any]) {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "get_system_resources":
            let snapshot = reader.read()
            sendStructuredToolResult(id: id, value: systemResourcePayload(snapshot))
        case "get_top_processes":
            let resource = arguments["resource"] as? String ?? "cpu"
            guard resource == "cpu" || resource == "memory" else {
                sendStructuredToolError(id: id, message: "resource deve ser cpu ou memory")
                return
            }
            let limit = min(max(arguments["limit"] as? Int ?? 5, 1), 20)
            let snapshot = reader.read()
            let processes = snapshot.processes.sorted {
                resource == "cpu" ? $0.cpuUsage > $1.cpuUsage : $0.memoryBytes > $1.memoryBytes
            }
            let payload: [String: Any] = [
                "resource": resource,
                "limit": limit,
                "updated_at": dateFormatter.string(from: snapshot.updatedAt),
                "processes": processes.prefix(limit).map(processPayload)
            ]
            sendStructuredToolResult(id: id, value: payload)
        default:
            sendStructuredToolError(id: id, message: "Ferramenta não suportada: \(name)")
        }
    }

    private func systemResourcePayload(_ snapshot: ResourceSnapshot) -> [String: Any] {
        [
            "updated_at": dateFormatter.string(from: snapshot.updatedAt),
            "cpu_usage_percent": numberOrNull(snapshot.cpuUsage.map { $0 * 100 }),
            "memory_usage_percent": snapshot.memoryUsage * 100,
            "memory_used_bytes": snapshot.memoryUsed,
            "memory_total_bytes": snapshot.memoryTotal,
            "disk_usage_percent": snapshot.diskUsage * 100,
            "disk_used_bytes": snapshot.diskUsed,
            "disk_total_bytes": snapshot.diskTotal,
            "gpu_usage_percent": numberOrNull(snapshot.gpuUsage.map { $0 * 100 }),
            "gpu_name": snapshot.gpuName ?? NSNull(),
            "network_download_bytes_per_second": snapshot.networkDownloadRate,
            "network_upload_bytes_per_second": snapshot.networkUploadRate,
            "process_count": snapshot.processes.count
        ]
    }

    private func processPayload(_ process: ProcessUsage) -> [String: Any] {
        [
            "pid": process.pid,
            "name": process.name,
            "cpu_usage_percent": process.cpuUsage,
            "memory_usage_percent": process.memoryUsage * 100,
            "memory_bytes": process.memoryBytes
        ]
    }

    private func numberOrNull(_ value: Double?) -> Any {
        value ?? NSNull()
    }

    private func sendStructuredToolResult(id: Any, value: [String: Any]) {
        let text = encode(value)
        sendResult(id: id, result: [
            "content": [["type": "text", "text": text]]
        ])
    }

    private func sendStructuredToolError(id: Any, message: String) {
        sendResult(id: id, result: [
            "isError": true,
            "content": [["type": "text", "text": message]]
        ])
    }

    private func sendResult(id: Any, result: [String: Any]) {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func sendError(id: Any, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func write(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}

private enum MCPError: Error {
    case invalidRequest
}
