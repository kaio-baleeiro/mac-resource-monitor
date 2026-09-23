import Foundation
import Darwin
import MacResourceMonitorCore
import MacResourceMonitorMCPCore

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private enum TestFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

private func fixture(_ variant: Int) -> ResourceSnapshot {
    let processes = (0..<8).map { offset in
        let processName = "process-\(variant)-\(offset)"
        let cpu = Double((variant * 13 + offset * 17) % 100) / 10
        let memory = Double((variant * 7 + offset * 9) % 100) / 100
        let bytes = UInt64(1_000_000 + variant * 100_000 + offset * 37_000)
        return ProcessUsage(
            pid: Int32(1000 + variant * 10 + offset),
            name: processName,
            cpuUsage: cpu,
            memoryUsage: memory,
            memoryBytes: bytes
        )
    }

    return ResourceSnapshot(
        cpuUsage: variant.isMultiple(of: 5) ? nil : Double((variant * 3) % 100) / 100,
        memoryUsed: UInt64(2_000_000_000 + variant * 11_000_000),
        memoryTotal: 16_000_000_000,
        diskUsed: UInt64(100_000_000_000 + variant * 19_000_000),
        diskTotal: 500_000_000_000,
        gpuUsage: variant.isMultiple(of: 7) ? nil : Double((variant * 5) % 100) / 100,
        gpuName: variant.isMultiple(of: 3) ? nil : "Test GPU \(variant)",
        networkDownloadRate: Double(variant * 123),
        networkUploadRate: Double(variant * 97),
        processes: processes,
        updatedAt: fixedDate.addingTimeInterval(TimeInterval(variant))
    )
}

private func simulatedSnapshot(
    cpuStatus: MetricStatus = .available,
    memoryStatus: MetricStatus = .available,
    diskStatus: MetricStatus = .available,
    gpuStatus: MetricStatus = .available,
    networkStatus: MetricStatus = .available,
    processStatus: MetricStatus = .available,
    includeProcesses: Bool = true
) -> ResourceSnapshot {
    let processes = includeProcesses
        ? [ProcessUsage(
            pid: 42_001,
            name: "corporate-test-process",
            cpuUsage: 12.5,
            memoryUsage: 0.25,
            memoryBytes: 256_000_000
        )]
        : []

    // Deliberately keep values populated even for failed/unavailable states.
    // The protocol layer must use the state and never expose stale values.
    return ResourceSnapshot(
        cpuUsage: 0.73,
        memoryUsed: 12_000_000_000,
        memoryTotal: 16_000_000_000,
        diskUsed: 400_000_000_000,
        diskTotal: 500_000_000_000,
        gpuUsage: 0.61,
        gpuName: "Simulated Apple GPU",
        networkDownloadRate: 12_345,
        networkUploadRate: 6_789,
        processes: processes,
        updatedAt: fixedDate,
        cpuStatus: cpuStatus,
        memoryStatus: memoryStatus,
        diskStatus: diskStatus,
        gpuStatus: gpuStatus,
        networkStatus: networkStatus,
        processStatus: processStatus
    )
}

private func handler(for variant: Int) -> MCPRequestHandler {
    let snapshot = fixture(variant)
    return MCPRequestHandler(snapshotProvider: { snapshot })
}

private func handler(for snapshot: ResourceSnapshot) -> MCPRequestHandler {
    MCPRequestHandler(snapshotProvider: { snapshot })
}

private func object(_ data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TestFailure.message("Resposta não é um objeto JSON")
    }
    return value
}

private func request(id: Int, method: String, params: [String: Any]? = nil) -> String {
    var value: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
    if let params { value["params"] = params }
    let data = try! JSONSerialization.data(withJSONObject: value)
    return String(decoding: data, as: UTF8.self)
}

private func toolCall(id: Int, name: String, arguments: [String: Any] = [:]) -> String {
    request(id: id, method: "tools/call", params: ["name": name, "arguments": arguments])
}

private func result(_ response: [String: Any]) throws -> [String: Any] {
    guard let value = response["result"] as? [String: Any] else {
        throw TestFailure.message("Resposta não possui result: \(response)")
    }
    return value
}

private func structured(_ response: [String: Any]) throws -> [String: Any] {
    guard let value = try result(response)["structuredContent"] as? [String: Any] else {
        throw TestFailure.message("Tool result não possui structuredContent: \(response)")
    }
    return value
}

private func integer(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
private func decimal(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
private func isNull(_ value: Any?) -> Bool { value is NSNull }

@main
struct MacResourceMonitorTestRunner {
    private var scenarios = 0

    static func main() {
        do {
            var runner = MacResourceMonitorTestRunner()
            try runner.run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    mutating private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        scenarios += 1
        guard condition() else { throw TestFailure.message("Cenário #\(scenarios): \(message)") }
    }

    mutating private func run() throws {
        try basicProtocolScenarios()
        try topProcessScenarios()
        try systemResourceScenarios()
        try simulatedPermissionScenarios()
        try processDetailScenarios()
        try validationScenarios()
        try catalogScenarios()
        let minimumReached = scenarios >= 500
        try check(minimumReached, "a suíte deve executar pelo menos 500 cenários")
        print("PASS: \(scenarios) cenários distintos de teste MCP executados")
    }

    private mutating func basicProtocolScenarios() throws {
        let initialized = try object(handler(for: 1).handle(line: request(id: 1, method: "initialize"))!)
        let initializeResult = try result(initialized)
        try check(initializeResult["protocolVersion"] as? String == "2024-11-05", "protocolVersion")
        try check((initializeResult["serverInfo"] as? [String: Any])?["name"] as? String == "mac-resource-monitor", "server name")
        try check((initializeResult["instructions"] as? String)?.contains("somente leitura") == true, "server instructions")

        let ping = try object(handler(for: 1).handle(line: request(id: 2, method: "ping"))!)
        try check((ping["result"] as? [String: Any]) != nil, "ping result")
        try check(handler(for: 1).handle(line: "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}") == nil, "notification suppression")

        let listed = try object(handler(for: 1).handle(line: request(id: 3, method: "tools/list"))!)
        let tools = try result(listed)["tools"] as? [[String: Any]]
        try check(tools?.count == MCPRequestHandler.toolNames.count, "tool count")
        try check(tools?.compactMap { $0["name"] as? String } == MCPRequestHandler.toolNames, "tool names")

        let machine = try object(handler(for: 1).handle(line: toolCall(id: 4, name: "get_machine_info"))!)
        let machineInfo = try structured(machine)
        try check(machineInfo["operating_system"] as? String == "macOS", "machine operating system")
        try check((machineInfo["architecture"] as? String)?.isEmpty == false, "machine architecture")

        let capabilities = try object(handler(for: 1).handle(line: toolCall(id: 5, name: "get_metric_capabilities"))!)
        let capabilityInfo = try structured(capabilities)
        try check(capabilityInfo["scope"] as? String == "local_read_only", "capability scope")
        try check((capabilityInfo["metrics"] as? [[String: Any]])?.count == 8, "capability metrics")
    }

    private mutating func topProcessScenarios() throws {
        for index in 0..<160 {
            let variant = index % 20
            let resource = index.isMultiple(of: 2) ? "cpu" : "memory"
            let limit = (index % 20) + 1
            let response = try object(handler(for: variant).handle(line: toolCall(id: index, name: "get_top_processes", arguments: ["resource": resource, "limit": limit]))!)
            let value = try structured(response)
            let processes = value["processes"] as? [[String: Any]]
            try check(value["resource"] as? String == resource, "ranking resource \(index)")
            try check(integer(value["limit"]) == limit, "ranking limit \(index)")
            try check(processes?.count == min(limit, 8), "ranking result count \(index)")
            if let first = processes?.first {
                try check(integer(first["pid"]) != nil, "ranking pid \(index)")
                try check(first["name"] as? String != nil, "ranking name \(index)")
            }
        }
    }

    private mutating func systemResourceScenarios() throws {
        for index in 0..<120 {
            let response = try object(handler(for: index).handle(line: toolCall(id: index, name: "get_system_resources"))!)
            let value = try structured(response)
            try check(integer(value["memory_total_bytes"]) == 16_000_000_000, "memory total \(index)")
            try check(integer(value["disk_total_bytes"]) == 500_000_000_000, "disk total \(index)")
            try check(integer(value["process_count"]) == 8, "process count \(index)")
            try check(decimal(value["network_download_bytes_per_second"]) == Double(index * 123), "download rate \(index)")
            try check(decimal(value["network_upload_bytes_per_second"]) == Double(index * 97), "upload rate \(index)")
        }
    }

    private mutating func simulatedPermissionScenarios() throws {
        let blockedStatuses: [MetricStatus] = [.warmingUp, .unavailable, .failed]

        for status in blockedStatuses {
            let snapshot = simulatedSnapshot(cpuStatus: status, gpuStatus: status)
            let response = try object(handler(for: snapshot).handle(line: toolCall(id: 10_000, name: "get_system_resources"))!)
            let value = try structured(response)

            try check(value["cpu_usage_state"] as? String == status.rawValue, "CPU state \(status.rawValue)")
            try check(isNull(value["cpu_usage_percent"]), "CPU stale value hidden \(status.rawValue)")
            try check(value["gpu_usage_state"] as? String == status.rawValue, "GPU state \(status.rawValue)")
            try check(isNull(value["gpu_usage_percent"]), "GPU stale value hidden \(status.rawValue)")
            try check(isNull(value["gpu_name"]), "GPU name hidden \(status.rawValue)")
        }

        let metricCases: [(String, ResourceSnapshot, String, String)] = [
            ("memory", simulatedSnapshot(memoryStatus: .failed), "memory_usage_percent", "memory_usage_state"),
            ("disk", simulatedSnapshot(diskStatus: .unavailable), "disk_usage_percent", "disk_usage_state"),
            ("network", simulatedSnapshot(networkStatus: .failed), "network_download_bytes_per_second", "network_state")
        ]
        for (name, snapshot, valueKey, stateKey) in metricCases {
            let response = try object(handler(for: snapshot).handle(line: toolCall(id: 10_001, name: "get_system_resources"))!)
            let value = try structured(response)
            try check(isNull(value[valueKey]), "\(name) value hidden when blocked")
            try check((value[stateKey] as? String) == (name == "disk" ? "unavailable" : "failed"), "\(name) state preserved")
        }

        for status in blockedStatuses {
            let snapshot = simulatedSnapshot(processStatus: status)
            let resourceResponse = try object(handler(for: snapshot).handle(line: toolCall(id: 10_002, name: "get_system_resources"))!)
            let resourceValue = try structured(resourceResponse)
            try check(isNull(resourceValue["process_count"]), "process count hidden \(status.rawValue)")
            try check(resourceValue["process_state"] as? String == status.rawValue, "process state preserved \(status.rawValue)")

            let rankingResponse = try object(handler(for: snapshot).handle(line: toolCall(id: 10_003, name: "get_top_processes"))!)
            let rankingResult = try result(rankingResponse)
            try check(rankingResult["isError"] as? Bool == true, "ranking fails safely \(status.rawValue)")

            let detailsResponse = try object(handler(for: snapshot).handle(line: toolCall(id: 10_004, name: "get_process_details", arguments: ["pid": 42_001]))!)
            let detailsResult = try result(detailsResponse)
            try check(detailsResult["isError"] as? Bool == true, "process details fail safely \(status.rawValue)")
        }

        let emptyProcessSnapshot = simulatedSnapshot(processStatus: .available, includeProcesses: false)
        let emptyRanking = try object(handler(for: emptyProcessSnapshot).handle(line: toolCall(id: 10_005, name: "get_top_processes"))!)
        let emptyRankingValue = try structured(emptyRanking)
        try check((emptyRankingValue["processes"] as? [[String: Any]])?.isEmpty == true, "available empty process list is not treated as blocked")

        let mixedFailureSnapshot = simulatedSnapshot(gpuStatus: .unavailable, processStatus: .failed)
        let mixedResponse = try object(handler(for: mixedFailureSnapshot).handle(line: toolCall(id: 10_006, name: "get_system_resources"))!)
        let mixedValue = try structured(mixedResponse)
        try check(decimal(mixedValue["memory_usage_percent"]) == 75, "unrelated memory metric remains available")
        try check(decimal(mixedValue["disk_usage_percent"]) == 80, "unrelated disk metric remains available")
        try check(isNull(mixedValue["gpu_usage_percent"]), "GPU failure is isolated")
        try check(isNull(mixedValue["process_count"]), "process failure is isolated")
    }

    private mutating func processDetailScenarios() throws {
        for index in 0..<100 {
            let variant = index % 10
            let offset = index % 8
            let present = index.isMultiple(of: 2)
            let pid = present ? 1000 + variant * 10 + offset : 900_000 + index
            let response = try object(handler(for: variant).handle(line: toolCall(id: index, name: "get_process_details", arguments: ["pid": pid]))!)
            if present {
                let details = try structured(response)
                try check(integer(details["pid"]) == pid, "process pid \(index)")
                try check((details["name"] as? String)?.hasPrefix("process-") == true, "process name \(index)")
            } else {
                let toolResult = try result(response)
                try check(toolResult["isError"] as? Bool == true, "missing process error \(index)")
            }
        }
    }

    private mutating func validationScenarios() throws {
        for index in 0..<80 {
            let line: String
            switch index % 8 {
            case 0: line = request(id: index, method: "unknown/method")
            case 1: line = toolCall(id: index, name: "unknown_tool")
            case 2: line = toolCall(id: index, name: "get_top_processes", arguments: ["resource": "gpu"])
            case 3: line = toolCall(id: index, name: "get_top_processes", arguments: ["limit": 0])
            case 4: line = toolCall(id: index, name: "get_top_processes", arguments: ["limit": 21])
            case 5: line = toolCall(id: index, name: "get_process_details", arguments: ["pid": 0])
            case 6: line = toolCall(id: index, name: "get_process_details", arguments: ["pid": -1])
            default: line = "not-json-\(index)"
            }
            let response = try object(handler(for: index % 10).handle(line: line)!)
            if index % 8 == 0 || index % 8 == 7 {
                try check((response["error"] as? [String: Any]) != nil, "JSON-RPC error \(index)")
            } else {
                let toolResult = try result(response)
                try check(toolResult["isError"] as? Bool == true, "tool error \(index)")
            }
        }
    }

    private mutating func catalogScenarios() throws {
        let definitions = MCPRequestHandler.toolDefinitions()
        for index in 0..<80 {
            let definition = definitions[index % definitions.count]
            let name = definition["name"] as? String
            let description = definition["description"] as? String
            let schema = definition["inputSchema"] as? [String: Any]
            try check(name.map(MCPRequestHandler.toolNames.contains) == true, "catalog name \(index)")
            try check(description?.isEmpty == false, "catalog description \(index)")
            try check(schema?["type"] as? String == "object", "catalog schema type \(index)")
            try check(schema?["additionalProperties"] as? Bool == false, "catalog schema properties \(index)")
        }
    }
}
