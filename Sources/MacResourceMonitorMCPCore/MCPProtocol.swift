import Foundation
import Darwin
import MacResourceMonitorCore

public struct MCPRequestHandler {
    public typealias SnapshotProvider = () -> ResourceSnapshot

    private let snapshotProvider: SnapshotProvider

    public init(snapshotProvider: @escaping SnapshotProvider) {
        self.snapshotProvider = snapshotProvider
    }

    public func handle(line: String) -> Data? {
        do {
            guard let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let method = request["method"] as? String else {
                return responseError(id: NSNull(), code: -32600, message: "Requisição inválida")
            }

            if method.hasPrefix("notifications/") {
                return nil
            }

            let id = request["id"] ?? NSNull()
            switch method {
            case "initialize":
                return responseResult(id: id, result: initializeResult)
            case "ping":
                return responseResult(id: id, result: [:])
            case "tools/list":
                return responseResult(id: id, result: ["tools": Self.toolDefinitions()])
            case "tools/call":
                let params = request["params"] as? [String: Any] ?? [:]
                return callTool(id: id, params: params)
            default:
                return responseError(id: id, code: -32601, message: "Método não suportado: \(method)")
            }
        } catch {
            return responseError(id: NSNull(), code: -32600, message: "Requisição inválida")
        }
    }

    public static let toolNames = [
        "get_system_resources",
        "get_top_processes",
        "get_process_details",
        "get_machine_info",
        "get_metric_capabilities"
    ]

    public static let serverInstructions = "Use as ferramentas para consultar o consumo atual e os processos deste Mac local. Os dados são somente leitura, não saem da máquina e não incluem conteúdo de arquivos. Comece por get_system_resources para um panorama; use get_top_processes para ranking; use get_process_details para investigar um PID; use get_machine_info e get_metric_capabilities para contexto e limitações."

    public static func toolDefinitions() -> [[String: Any]] {
        [
        [
            "name": "get_system_resources",
            "description": "Retorna o consumo atual de CPU, memória, GPU, disco principal, rede e quantidade de processos deste Mac.",
            "inputSchema": objectSchema()
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
                        "description": "Quantidade de processos entre 1 e 20. Padrão: 5."
                    ]
                ],
                "additionalProperties": false
            ]
        ],
        [
            "name": "get_process_details",
            "description": "Retorna os dados atuais de um processo pelo PID, ou informa que ele já não está disponível.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "pid": [
                        "type": "integer",
                        "minimum": 1,
                        "description": "PID do processo a consultar."
                    ]
                ],
                "required": ["pid"],
                "additionalProperties": false
            ]
        ],
        [
            "name": "get_machine_info",
            "description": "Retorna contexto estável da máquina: sistema operacional, arquitetura, CPUs, memória física e GPU detectada.",
            "inputSchema": objectSchema()
        ],
        [
            "name": "get_metric_capabilities",
            "description": "Explica quais métricas estão disponíveis e como interpretar valores ausentes ou aproximados.",
            "inputSchema": objectSchema()
        ]
        ]
    }

    private var initializeResult: [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": [
                "name": "mac-resource-monitor",
                "version": "0.2.0"
            ],
            "instructions": Self.serverInstructions
        ]
    }

    private func callTool(id: Any, params: [String: Any]) -> Data {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "get_system_resources":
            return success(id: id, value: systemResourcePayload(snapshotProvider()))
        case "get_top_processes":
            return topProcesses(id: id, arguments: arguments)
        case "get_process_details":
            return processDetails(id: id, arguments: arguments)
        case "get_machine_info":
            return success(id: id, value: machineInfo(snapshotProvider()))
        case "get_metric_capabilities":
            return success(id: id, value: metricCapabilities)
        default:
            return toolError(id: id, message: "Ferramenta não suportada: \(name)")
        }
    }

    private func topProcesses(id: Any, arguments: [String: Any]) -> Data {
        let resource = arguments["resource"] as? String ?? "cpu"
        guard resource == "cpu" || resource == "memory" else {
            return toolError(id: id, message: "resource deve ser cpu ou memory")
        }

        let limit = arguments["limit"] as? Int ?? 5
        guard (1...20).contains(limit) else {
            return toolError(id: id, message: "limit deve estar entre 1 e 20")
        }

        let snapshot = snapshotProvider()
        let processes = snapshot.processes.sorted {
            resource == "cpu" ? $0.cpuUsage > $1.cpuUsage : $0.memoryBytes > $1.memoryBytes
        }
        let payload: [String: Any] = [
            "resource": resource,
            "limit": limit,
            "updated_at": timestamp(snapshot.updatedAt),
            "processes": processes.prefix(limit).map(processPayload)
        ]
        return success(id: id, value: payload)
    }

    private func processDetails(id: Any, arguments: [String: Any]) -> Data {
        guard let pid = arguments["pid"] as? Int, pid > 0 else {
            return toolError(id: id, message: "pid deve ser um inteiro positivo")
        }
        let snapshot = snapshotProvider()
        guard let process = snapshot.processes.first(where: { $0.pid == Int32(pid) }) else {
            return toolError(id: id, message: "Processo não encontrado: \(pid)")
        }
        return success(id: id, value: processPayload(process))
    }

    private func systemResourcePayload(_ snapshot: ResourceSnapshot) -> [String: Any] {
        [
            "updated_at": timestamp(snapshot.updatedAt),
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

    private func machineInfo(_ snapshot: ResourceSnapshot) -> [String: Any] {
        [
            "operating_system": "macOS",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": machineArchitecture(),
            "logical_cpu_count": ProcessInfo.processInfo.processorCount,
            "active_cpu_count": ProcessInfo.processInfo.activeProcessorCount,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "gpu_name": snapshot.gpuName ?? NSNull()
        ]
    }

    private var metricCapabilities: [String: Any] {
        [
            "scope": "local_read_only",
            "metrics": [
                ["name": "cpu_usage_percent", "available": true, "notes": "Amostra instantânea agregada; pode ser nula na primeira leitura."],
                ["name": "memory_usage_percent", "available": true, "notes": "Inclui páginas ativas, inativas, wired e compressor."],
                ["name": "disk_usage_percent", "available": true, "notes": "Volume principal montado em /."],
                ["name": "gpu_usage_percent", "available": true, "notes": "Pode ser nula quando o macOS não publica a utilização do acelerador."],
                ["name": "network_bytes_per_second", "available": true, "notes": "Estimativa baseada em interfaces ativas não-loopback."],
                ["name": "process_cpu_and_memory", "available": true, "notes": "Lista derivada de processos visíveis ao usuário que executa o servidor."],
                ["name": "process_command_arguments", "available": false, "notes": "Não são coletados para reduzir exposição de dados locais."],
                ["name": "file_contents", "available": false, "notes": "Nunca são lidos por este servidor." ]
            ],
            "limitations": [
                "Os dados representam uma leitura do momento, não um histórico persistido.",
                "Permissões do macOS podem limitar quais processos aparecem.",
                "O servidor usa transporte stdio local e não abre portas de rede."
            ]
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

    private func success(id: Any, value: [String: Any]) -> Data {
        let text = encode(value)
        return responseResult(id: id, result: [
            "content": [["type": "text", "text": text]],
            "structuredContent": value
        ])
    }

    private func toolError(id: Any, message: String) -> Data {
        responseResult(id: id, result: [
            "isError": true,
            "content": [["type": "text", "text": message]]
        ])
    }

    private func responseResult(id: Any, result: [String: Any]) -> Data {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func responseError(id: Any, code: Int, message: String) -> Data {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func write(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func numberOrNull(_ value: Double?) -> Any {
        value ?? NSNull()
    }

    private func machineArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private static func objectSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [:],
            "additionalProperties": false
        ]
    }
}
